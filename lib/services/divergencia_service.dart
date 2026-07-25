import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../utils/logger.dart';
import 'foto_documento_client.dart';

/// Sprint 6 W+M — divergências do BDT (motor W10 exposto pro condutor).
///
/// Condutor no destino descobre que a carga real não bate com o
/// declarado (excesso, dimensão errada, item errado, avaria, carga
/// que não estava prevista) — **REGISTRA** aqui. Admin **DECIDE**
/// no web (cancelar reabre solicitação pra reagendamento).
///
/// Regra [[bdt_uerj_sem_travas_so_alertas]]: `registrar` nunca 422 por
/// "já existe outro registro"; devolve o existente com `jaExistia=true`
/// e o mobile mostra alerta amarelo permitindo editar/ver em vez de
/// travar o condutor.
class DivergenciaService {
  static const _log = Logger('DIV-SVC');

  static Future<int> _userId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('usuario_id') ?? 0;
  }

  /// Registra divergência de carga. O backend classifica sozinho o tipo
  /// (`carga` vs `carga_nao_prevista`) com base na solicitação.
  ///
  /// `real` traz o que o condutor MEDIU no destino (opcionais — condutor
  /// pode registrar só a `descricao` se não conseguiu pesar/medir).
  static Future<RegistrarDivergenciaResult> registrar({
    required int bdtId,
    required String descricao,
    double? pesoKg,
    double? comprimentoM,
    double? larguraM,
    double? alturaM,
  }) async {
    final usuarioId = await _userId();
    final real = <String, dynamic>{};
    if (pesoKg != null) real['peso_kg'] = pesoKg;
    if (comprimentoM != null) real['comprimento_m'] = comprimentoM;
    if (larguraM != null) real['largura_m'] = larguraM;
    if (alturaM != null) real['altura_m'] = alturaM;

    final res = await ApiClient.post(
      'transporte/api/bdt/divergencias/registrar',
      {
        'usuario_id': usuarioId,
        'bdt_id': bdtId,
        'descricao': descricao.trim(),
        if (real.isNotEmpty) 'real': real,
      },
    );
    _log.info('registrar#$bdtId http=${res["http_status"]} ok=${res["success"]}');

    final ok = res['success'] == true;
    return RegistrarDivergenciaResult(
      ok: ok,
      id: _asInt(res['id']),
      jaExistia: res['ja_existia'] == true,
      mensagem: res['message']?.toString() ??
          (ok ? 'Divergência registrada.' : 'Falha ao registrar.'),
    );
  }

  /// Lista as divergências deste BDT (independente da decisão).
  static Future<List<DivergenciaResumo>> listarDoBdt(int bdtId) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post(
      'transporte/api/bdt/divergencias/listar',
      {'usuario_id': usuarioId, 'bdt_id': bdtId},
    );
    if (res['success'] != true) {
      _log.warn('listarDoBdt#$bdtId FALHOU: ${res['message']}');
      return const [];
    }
    final list = (res['data'] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => DivergenciaResumo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // Fotos via FotoDocumentoClient genérico.
  static const _fotoClient = FotoDocumentoClient(
    uploadPath:  'transporte/api/bdt/divergencias/fotos/upload',
    listarPath:  'transporte/api/bdt/divergencias/fotos/listar',
    obterPath:   'transporte/api/bdt/divergencias/fotos/obter',
    excluirPath: 'transporte/api/bdt/divergencias/fotos/excluir',
    refField: 'id_divergencia',
  );

  static Future<List<FotoDocumentoRef>> listarFotos(int divergenciaId) =>
      _fotoClient.listar(divergenciaId);

  static Future<List<int>?> obterFoto(int docId, {int? divergenciaId}) =>
      _fotoClient.obter(docId, refId: divergenciaId);

  static Future<bool> excluirFoto(int docId, {int? divergenciaId}) =>
      _fotoClient.excluir(docId, refId: divergenciaId);

  static Future<int> uploadFoto({
    required int divergenciaId,
    required List<int> bytes,
    required String filename,
  }) {
    return _fotoClient.upload(
      refId: divergenciaId,
      bytes: bytes,
      filename: filename,
    );
  }

  static int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }
}

class RegistrarDivergenciaResult {
  final bool ok;
  final int id;
  final bool jaExistia;
  final String mensagem;
  const RegistrarDivergenciaResult({
    required this.ok,
    required this.id,
    required this.jaExistia,
    required this.mensagem,
  });
}

/// Linha da lista de divergências do BDT — mesmo shape que o endpoint
/// `bdt/divergencias/listar` devolve. Inclui `qtdFotos` pro badge.
class DivergenciaResumo {
  final int id;
  final String tipo;
  final String tipoLabel;
  final String? descricao;
  final String? realJson;
  final String? declaradoJson;
  final String? severidade;

  /// Estado da decisão: `pendente` | `cancelado` | `prosseguido`.
  final String? decisao;
  final String? decisaoObs;

  final String? criadoEm;
  final String? criadoPorNome;
  final String? decididoEm;
  final int qtdFotos;

  const DivergenciaResumo({
    required this.id,
    required this.tipo,
    required this.tipoLabel,
    this.descricao,
    this.realJson,
    this.declaradoJson,
    this.severidade,
    this.decisao,
    this.decisaoObs,
    this.criadoEm,
    this.criadoPorNome,
    this.decididoEm,
    this.qtdFotos = 0,
  });

  bool get pendente => (decisao ?? 'pendente') == 'pendente';
  bool get canceladoPeloAdmin => decisao == 'cancelado';
  bool get prosseguidoPeloAdmin => decisao == 'prosseguido';

  factory DivergenciaResumo.fromJson(Map<String, dynamic> j) {
    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }
    return DivergenciaResumo(
      id: asInt(j['id']) ?? 0,
      tipo: (j['tipo'] ?? '').toString(),
      tipoLabel: (j['tipo_label'] ?? '').toString(),
      descricao: j['descricao']?.toString(),
      realJson: j['real_json']?.toString(),
      declaradoJson: j['declarado_json']?.toString(),
      severidade: j['severidade']?.toString(),
      decisao: j['decisao']?.toString(),
      decisaoObs: j['decisao_obs']?.toString(),
      criadoEm: j['criado_em']?.toString(),
      criadoPorNome: j['criado_por_nome']?.toString(),
      decididoEm: j['decidido_em']?.toString(),
      qtdFotos: asInt(j['qtd_fotos']) ?? 0,
    );
  }
}
