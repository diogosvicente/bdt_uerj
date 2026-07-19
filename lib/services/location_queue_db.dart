import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Fila persistente de pontos GPS aguardando envio ao backend.
///
/// **Modelo de dados**: um único ponto por linha. O payload que vai pro
/// `POST transporte/api/bdt/localizacao` é armazenado como JSON no campo
/// [_kCPayload], pronto para reenvio sem retrabalho.
///
/// **Fluxo esperado**:
/// 1. `enqueue(payload)` — grava logo depois de coletar o ponto.
/// 2. Um worker chama `takePending(limit)` para pegar um lote.
/// 3. Para cada ponto enviado com sucesso: `markSent(id)`.
/// 4. Para cada ponto que falhou: `markFailed(id)` incrementa tentativas.
///    Quando `attempts >= maxAttempts`, é apagado (não faz sentido bater
///    infinitamente).
///
/// **Isolate-safe**: cada isolate abre sua própria conexão via [instance].
/// O sqflite gerencia locks internos, então o isolate do foreground
/// service e o principal podem escrever/ler concorrentemente sem corromper.
class LocationQueueDb {
  static const String _kDbName = 'bdt_gps_queue.db';
  static const int _kDbVersion = 1;
  static const String _kTable = 'pending_locations';

  // Colunas
  static const String _kCId = 'id';
  static const String _kCBdtId = 'bdt_id';
  static const String _kCAgendaId = 'agenda_id';
  static const String _kCTrechoId = 'trecho_id';
  static const String _kCPayload = 'payload_json';
  static const String _kCCapturedAt = 'captured_at';
  static const String _kCCreatedAt = 'created_at';
  static const String _kCAttempts = 'attempts';
  static const String _kCLastError = 'last_error';

  /// Máximo de tentativas antes de descartar um ponto.
  /// 10 dá ~5 minutos com retry a cada 30s — se depois disso não foi,
  /// provavelmente o backend rejeitou por regra de negócio (BDT
  /// encerrado, trecho já finalizado etc.), então descartar é OK.
  static const int maxAttempts = 10;

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final path = p.join(dir, _kDbName);
    _db = await openDatabase(
      path,
      version: _kDbVersion,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE $_kTable (
            $_kCId          INTEGER PRIMARY KEY AUTOINCREMENT,
            $_kCBdtId       INTEGER NOT NULL,
            $_kCAgendaId    INTEGER,
            $_kCTrechoId    INTEGER NOT NULL,
            $_kCPayload     TEXT    NOT NULL,
            $_kCCapturedAt  TEXT    NOT NULL,
            $_kCCreatedAt   INTEGER NOT NULL,
            $_kCAttempts    INTEGER NOT NULL DEFAULT 0,
            $_kCLastError   TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_${_kTable}_captured '
          'ON $_kTable ($_kCBdtId, $_kCCapturedAt)',
        );
      },
    );
    return _db!;
  }

  /// Grava um ponto na fila. Retorna o `id` local.
  Future<int> enqueue({
    required int bdtId,
    int? agendaId,
    required int trechoId,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _open();
    // captured_at do payload é o momento REAL da leitura GPS;
    // usamos ele pra manter ordem cronológica no envio.
    final capturedAt = (payload['loc'] is Map)
        ? ((payload['loc'] as Map)['captured_at']?.toString() ?? '')
        : '';
    return db.insert(_kTable, {
      _kCBdtId: bdtId,
      _kCAgendaId: agendaId,
      _kCTrechoId: trechoId,
      _kCPayload: jsonEncode(payload),
      _kCCapturedAt: capturedAt,
      _kCCreatedAt: DateTime.now().millisecondsSinceEpoch,
      _kCAttempts: 0,
    });
  }

  /// Retorna até [limit] pontos pendentes, mais antigos primeiro.
  Future<List<PendingPoint>> takePending({int limit = 20}) async {
    final db = await _open();
    final rows = await db.query(
      _kTable,
      orderBy: '$_kCCapturedAt ASC, $_kCCreatedAt ASC',
      limit: limit,
    );
    return rows.map(PendingPoint._fromRow).toList();
  }

  /// Confirma envio com sucesso — remove o ponto.
  Future<void> markSent(int id) async {
    final db = await _open();
    await db.delete(_kTable, where: '$_kCId = ?', whereArgs: [id]);
  }

  /// Marca falha — incrementa tentativas. Se passar de [maxAttempts],
  /// apaga o ponto (não vamos ficar tentando pra sempre).
  Future<void> markFailed(int id, {String? error}) async {
    final db = await _open();
    final rows = await db.query(
      _kTable,
      columns: [_kCAttempts],
      where: '$_kCId = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final attempts = (rows.first[_kCAttempts] as int? ?? 0) + 1;
    if (attempts >= maxAttempts) {
      await db.delete(_kTable, where: '$_kCId = ?', whereArgs: [id]);
      return;
    }
    await db.update(
      _kTable,
      {_kCAttempts: attempts, _kCLastError: error},
      where: '$_kCId = ?',
      whereArgs: [id],
    );
  }

  /// Total de pontos na fila (todos os BDTs). Útil pra UI.
  Future<int> countPending() async {
    final db = await _open();
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM $_kTable');
    return (r.first['c'] as int?) ?? 0;
  }

  /// Total de pontos pendentes para um BDT/trecho específico.
  Future<int> countPendingFor({required int bdtId, int? trechoId}) async {
    final db = await _open();
    if (trechoId != null) {
      final r = await db.rawQuery(
        'SELECT COUNT(*) as c FROM $_kTable WHERE $_kCBdtId = ? AND $_kCTrechoId = ?',
        [bdtId, trechoId],
      );
      return (r.first['c'] as int?) ?? 0;
    }
    final r = await db.rawQuery(
      'SELECT COUNT(*) as c FROM $_kTable WHERE $_kCBdtId = ?',
      [bdtId],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

/// Ponto pendente lido da fila.
class PendingPoint {
  final int id;
  final int bdtId;
  final int? agendaId;
  final int trechoId;
  final Map<String, dynamic> payload;
  final int attempts;

  const PendingPoint._({
    required this.id,
    required this.bdtId,
    required this.agendaId,
    required this.trechoId,
    required this.payload,
    required this.attempts,
  });

  factory PendingPoint._fromRow(Map<String, Object?> r) {
    return PendingPoint._(
      id: r[LocationQueueDb._kCId] as int,
      bdtId: r[LocationQueueDb._kCBdtId] as int,
      agendaId: r[LocationQueueDb._kCAgendaId] as int?,
      trechoId: r[LocationQueueDb._kCTrechoId] as int,
      payload: Map<String, dynamic>.from(
        jsonDecode(r[LocationQueueDb._kCPayload] as String) as Map,
      ),
      attempts: (r[LocationQueueDb._kCAttempts] as int?) ?? 0,
    );
  }
}
