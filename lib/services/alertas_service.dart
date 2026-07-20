import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/bdt_resumo.dart';
import '../utils/logger.dart';

/// Sprint M5 — Alertas locais de preparação do BDT.
///
/// Categoria PLATFORM (`docs/ARCHITECTURE.md` §4.6). Agenda duas
/// notificações por BDT:
/// - **1h antes** da saída prevista → "Prepare-se: BDT sai em 1h"
/// - **30min antes** → "Está na hora de deslocar"
///
/// Ambas são notificações locais (não passam por servidor). Ao tocar,
/// o app abre a tela do BDT (deep-link via payload). Os alertas são
/// re-sincronizados sempre que a HomePage carrega a lista do dia —
/// se o admin remanejar um BDT, o próximo refresh corrige o schedule.
class AlertasService {
  static const _log = Logger('ALERTAS-SVC');

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Callback invocado ao tocar numa notificação. Setado pelo `main.dart`
  /// no bootstrap — geralmente navega para `/bdt` com o bdtId do payload.
  static void Function(int bdtId)? onTap;

  static const String _channelId = 'bdt_alertas_saida';
  static const String _channelName = 'Alertas de saída';
  static const String _channelDesc =
      'Avisa 1h e 30min antes de cada BDT programado.';

  /// True depois que `init()` completou com sucesso — protege contra
  /// duplo-init e contra tentativas de agendar antes do plugin estar pronto.
  static bool _ready = false;

  /// Inicializa o plugin, o timezone e as permissões nativas. Idempotente.
  /// Deve rodar antes de qualquer `sincronizarComBdtsDoDia`.
  static Future<void> init() async {
    if (_ready) return;

    tzdata.initializeTimeZones();
    // Sistema de agendamento usa `tz.local` — o dispositivo já expõe
    // o fuso do usuário (America/Sao_Paulo em produção). Sem hardcode:
    // se um condutor cruzar fuso, os alertas seguem ele.

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        final id = int.tryParse(resp.payload ?? '') ?? 0;
        if (id > 0 && onTap != null) onTap!(id);
      },
    );

    // Cria o canal Android (só assim as notificações têm som/badge).
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );

    // Permissão de notificação (Android 13+). Silencioso — se o usuário
    // negar, os alertas simplesmente não aparecem, mas nada quebra.
    await Permission.notification.request();

    _ready = true;
    _log.info('init OK');
  }

  /// Sincroniza os alertas locais com a lista de BDTs do dia atual.
  ///
  /// Estratégia: cancela **todos** os alertas conhecidos do app
  /// (`cancelAll` só afeta as notificações que ESTE app agendou) e
  /// re-agenda 2 alertas por BDT com `horaSaidaPrevista` futura.
  /// Isso mantém o cronograma sempre consistente com a última resposta
  /// do backend — se o admin mudou horário, o próximo refresh corrige.
  static Future<void> sincronizarComBdtsDoDia(List<BdtResumo> bdts) async {
    if (!_ready) {
      _log.warn('sincronizar chamado antes de init; ignorando.');
      return;
    }

    await _plugin.cancelAll();

    final agora = DateTime.now();
    int agendados = 0;

    for (final b in bdts) {
      final saida = b.horaSaidaPrevista;
      if (saida == null || !saida.isAfter(agora)) continue;

      await _agendarAlerta(
        bdt: b,
        quando: saida.subtract(const Duration(hours: 1)),
        idOffset: 1,
        titulo: 'Prepare-se: ${b.titulo} sai em 1h',
        corpo: _corpoParaBdt(b, saida, 'em 1h'),
      );
      await _agendarAlerta(
        bdt: b,
        quando: saida.subtract(const Duration(minutes: 30)),
        idOffset: 2,
        titulo: 'Hora de deslocar: ${b.titulo}',
        corpo: _corpoParaBdt(b, saida, 'em 30min'),
      );
      agendados++;
    }

    _log.info('sincronizado: ${bdts.length} BDT(s), '
        '$agendados com alerta futuro.');
  }

  /// Cancela ambos os alertas (1h e 30min) de um BDT específico.
  /// Deve ser chamado quando o BDT é encerrado ou o condutor já iniciou
  /// o primeiro trecho — nenhum dos avisos faz sentido mais.
  static Future<void> cancelarBdt(int bdtId) async {
    if (!_ready) return;
    await _plugin.cancel(_alertId(bdtId, 1));
    await _plugin.cancel(_alertId(bdtId, 2));
    _log.info('cancelado alertas do BDT #$bdtId');
  }

  // ── privados ─────────────────────────────────────────────────────

  /// IDs previsíveis: `bdtId*10 + (1 ou 2)`. Como `bdtId` cabe em int32
  /// facilmente, `bdtId*10+N` também cabe (limite do plugin é int32).
  static int _alertId(int bdtId, int offset) => bdtId * 10 + offset;

  static String _corpoParaBdt(BdtResumo b, DateTime saida, String antes) {
    String two(int v) => v.toString().padLeft(2, '0');
    final hm = '${two(saida.hour)}:${two(saida.minute)}';
    return 'Saída prevista às $hm ($antes). ${b.placa}'
        '${b.marcaNome != null ? ' — ${b.marcaNome} ${b.modeloNome ?? ''}' : ''}';
  }

  static Future<void> _agendarAlerta({
    required BdtResumo bdt,
    required DateTime quando,
    required int idOffset,
    required String titulo,
    required String corpo,
  }) async {
    if (!quando.isAfter(DateTime.now())) return; // já era

    try {
      await _plugin.zonedSchedule(
        _alertId(bdt.id, idOffset),
        titulo,
        corpo,
        tz.TZDateTime.from(quando, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: bdt.id.toString(),
      );
    } catch (e, st) {
      // Falha comum: `SCHEDULE_EXACT_ALARM` negada pelo usuário em
      // Android 12+. Cai pra inexato — o alerta ainda dispara, com
      // atraso de alguns minutos. Não quebra a UX.
      if (kDebugMode) _log.warn('exactAllowWhileIdle falhou: $e');
      try {
        await _plugin.zonedSchedule(
          _alertId(bdt.id, idOffset),
          titulo,
          corpo,
          tz.TZDateTime.from(quando, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: _channelDesc,
              importance: Importance.high,
              priority: Priority.high,
              category: AndroidNotificationCategory.reminder,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: bdt.id.toString(),
        );
      } catch (e2) {
        _log.error('inexactAllowWhileIdle também falhou', e2, st);
      }
    }
  }
}
