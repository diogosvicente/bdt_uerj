import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/bdt_resumo.dart';
import '../models/feedback_condutor.dart';
import '../models/passageiro.dart';
import '../models/pre_bdt_pendente.dart';
import '../models/veiculo.dart';
import '../utils/logger.dart';
import 'location_service.dart';

class BdtService {
  static const _log = Logger('BDT-SVC');

  static Future<int> _userId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('usuario_id') ?? 0;
  }

  /// Lista BDTs do dia
  static Future<List<BdtResumo>> listarDoDia({String? data}) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/dia", {
      if (data != null) "data": data,
      // ✅ backend já resolve via token, mas esse fallback ajuda enquanto você ajusta tudo
      "usuario_id": usuarioId,
    });

    if (res == null || res['success'] != true) return [];

    final list = (res['data'] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => BdtResumo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Detalhes completos do BDT.
  /// Sempre retorna Map (o ApiClient padroniza erros como Map com
  /// `success:false`).
  static Future<Map<String, dynamic>> detalhes(int bdtId) async {
    final usuarioId = await _userId();

    return await ApiClient.post("transporte/api/bdt/detalhes", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
    });
  }

  /// Inicia trecho (agendaId opcional => trecho extra)
  static Future<bool> iniciarTrecho({
    required int bdtId,
    int? agendaId,
    required int trechoId,
  }) async {
    final usuarioId = await _userId();

    final loc = await LocationService.getLocPayload();

    final payload = <String, dynamic>{
      "bdt_id": bdtId,
      "trecho_id": trechoId,
      "usuario_id": usuarioId,
      if (agendaId != null && agendaId > 0) "agenda_id": agendaId,
      if (loc != null) "loc": loc,
    };

    final res = await ApiClient.post(
      "transporte/api/bdt/trecho/iniciar",
      payload,
    );
    return res != null && res["success"] == true;
  }

  /// Finaliza trecho (envia loc junto se tiver)
  static Future<bool> finalizarTrecho({
    required int bdtId,
    required int trechoId,
  }) async {
    final usuarioId = await _userId();

    final loc = await LocationService.getLocPayload();

    final payload = <String, dynamic>{
      "bdt_id": bdtId,
      "trecho_id": trechoId,
      "usuario_id": usuarioId,
      if (loc != null) "loc": loc,
    };

    final res = await ApiClient.post(
      "transporte/api/bdt/trecho/finalizar",
      payload,
    );
    return res != null && res["success"] == true;
  }

  /// Envia 1 ponto de localização (tracking)
  static Future<bool> enviarLocalizacao({
    required int bdtId,
    int? agendaId,
    int? trechoId,
    Map<String, dynamic>? loc, // se vier null, ele tenta pegar do GPS agora
  }) async {
    final usuarioId = await _userId();

    final Map<String, dynamic>? resolvedLoc =
        loc ?? await LocationService.getLocPayload();
    if (resolvedLoc == null) {
      _log.warn('enviarLocalizacao: SEM POSIÇÃO (loc=null)');
      return false;
    }

    if (usuarioId <= 0) {
      _log.warn('enviarLocalizacao: usuario_id inválido ($usuarioId) — sem login?');
    }

    final payload = <String, dynamic>{
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      if (agendaId != null) "agenda_id": agendaId,
      if (trechoId != null) "trecho_id": trechoId,
      "loc": resolvedLoc,
    };

    final res = await ApiClient.post("transporte/api/bdt/localizacao", payload);
    final ok = res["success"] == true;
    final httpStatus = res["http_status"];
    final msg = res["message"] ?? res["status"];
    _log.info(
      'enviarLocalizacao: ${ok ? "OK" : "FALHA"} '
      'http=$httpStatus bdt=$bdtId trecho=$trechoId msg=$msg',
    );
    return ok;
  }

  // ==========================================================
  // MARCOS DA JORNADA (substitui o antigo bdt/salvar)
  // Marcos válidos no backend: partida | apresentacao | embarque_passageiro
  // ==========================================================

  /// Marcos válidos aceitos pelo backend (BdtJornadaService::ORDEM).
  static const List<String> marcosValidos = <String>[
    "partida",
    "apresentacao",
    "embarque_passageiro",
  ];

  /// Registra um marco da jornada. O backend grava origem="mobile"
  /// automaticamente — não enviar campo "origem".
  static Future<Map<String, dynamic>> registrarMarcoJornada({
    required int bdtId,
    required String marco,
    String? observacao,
  }) async {
    final usuarioId = await _userId();

    final payload = <String, dynamic>{
      "bdt_id": bdtId,
      "marco": marco,
      "usuario_id": usuarioId,
      if (observacao != null && observacao.trim().isNotEmpty)
        "observacao": observacao.trim(),
    };

    final res = await ApiClient.post(
      "transporte/api/bdt/jornada/marco",
      payload,
    );

    return Map<String, dynamic>.from(res);
  }

  /// Retorna o estado dos três marcos + histórico de assinaturas.
  /// Estrutura esperada:
  ///   {
  ///     "marcos": {
  ///       "partida":             {"datahora": "...", "assinatura": {...} | null},
  ///       "apresentacao":        {"datahora": "...", "assinatura": {...} | null},
  ///       "embarque_passageiro": {"datahora": "...", "assinatura": {...} | null}
  ///     },
  ///     "historico": [...]
  ///   }
  static Future<Map<String, dynamic>?> estadoJornada(int bdtId) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/jornada/estado", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
    });

    if (res["success"] != true) return null;
    return res;
  }

  // =========================
  // TRECHOS (CRUD)
  // =========================

  static Future<bool> criarTrechoExtra({
    required int bdtId,
    required String origem,
    required String destino,
    int? agendaId, // opcional
  }) async {
    final usuarioId = await _userId();

    // Rota canônica do backend atual: transporte/api/bdt/trechos/create
    final res = await ApiClient.post("transporte/api/bdt/trechos/create", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      "fk_agenda": agendaId, // null => extra
      "origem": origem,
      "destino": destino,
    });

    return res["success"] == true;
  }

  static Future<bool> atualizarTrecho({
    required int bdtId,
    required int trechoId,
    required String origem,
    required String destino,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/trechos/update", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      "trecho_id": trechoId,
      "origem": origem,
      "destino": destino,
    });

    return res != null && res["success"] == true;
  }

  static Future<bool> atualizarTrechoExecucao({
    required int bdtId,
    required int trechoId,
    required Map<String, dynamic> data,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post(
      "transporte/api/bdt/trecho/execucao/update",
      {
        "bdt_id": bdtId,
        "trecho_id": trechoId,
        "usuario_id": usuarioId, // fallback (token ideal)
        ...data, // datahora_saida, odometro_saida, datahora_chegada, odometro_chegada
      },
    );

    return res != null && res["success"] == true;
  }

  static Future<bool> excluirTrecho({
    required int bdtId,
    required int trechoId,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/trechos/delete", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      "trecho_id": trechoId,
    });

    return res != null && res["success"] == true;
  }

  // =========================
  // ABASTECIMENTOS (CRUD)
  // =========================

  static Future<List<Map<String, dynamic>>> listarAbastecimentos({
    required int bdtId,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/abastecimentos/list", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
    });

    if (res == null || res["success"] != true) return [];
    final list = (res["data"] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<bool> criarAbastecimento({
    required int bdtId,
    required Map<String, dynamic> data,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post(
      "transporte/api/bdt/abastecimentos/create",
      {"bdt_id": bdtId, "usuario_id": usuarioId, ...data},
    );

    return res != null && res["success"] == true;
  }

  static Future<bool> atualizarAbastecimento({
    required int bdtId,
    required int abastecimentoId,
    required Map<String, dynamic> data,
  }) async {
    final usuarioId = await _userId();

    final res =
        await ApiClient.post("transporte/api/bdt/abastecimentos/update", {
          "bdt_id": bdtId,
          "usuario_id": usuarioId,
          "abastecimento_id": abastecimentoId,
          ...data,
        });

    return res != null && res["success"] == true;
  }

  static Future<bool> excluirAbastecimento({
    required int bdtId,
    required int abastecimentoId,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post(
      "transporte/api/bdt/abastecimentos/delete",
      {
        "bdt_id": bdtId,
        "usuario_id": usuarioId,
        "abastecimento_id": abastecimentoId,
      },
    );

    return res != null && res["success"] == true;
  }

  // =========================
  // MANUTENÇÕES (CRUD)
  // =========================

  static Future<List<Map<String, dynamic>>> listarManutencoes({
    required int bdtId,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/manutencoes/list", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
    });

    if (res == null || res["success"] != true) return [];
    final list = (res["data"] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<bool> criarManutencao({
    required int bdtId,
    required Map<String, dynamic> data,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/manutencoes/create", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      ...data,
    });

    return res != null && res["success"] == true;
  }

  static Future<bool> atualizarManutencao({
    required int bdtId,
    required int manutencaoId,
    required Map<String, dynamic> data,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/manutencoes/update", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      "manutencao_id": manutencaoId,
      ...data,
    });

    return res != null && res["success"] == true;
  }

  static Future<bool> excluirManutencao({
    required int bdtId,
    required int manutencaoId,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/manutencoes/delete", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      "manutencao_id": manutencaoId,
    });

    return res != null && res["success"] == true;
  }

  static Future<bool> excluirTrechoExtra({
    required int bdtId,
    required int trechoId,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/trechos/delete", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      "trecho_id": trechoId,
    });

    return res != null && res["success"] == true;
  }

  // ==========================================================
  // Reabertura de BDT
  // Backend: POST transporte/api/bdt/reabrir
  // Regras:
  //   - Só BDTs com status Encerrado (3) ou Cancelado (4)
  //   - Justificativa obrigatória (mínimo 10 caracteres)
  //   - Origem gravada como "mobile" no histórico (o backend força)
  //
  // Retorna um Map com { "success": bool, "message": String?, payload... }
  // para que a UI mostre o motivo da falha (permissão, status inválido, etc).
  // ==========================================================
  static Future<Map<String, dynamic>> reabrirBdt({
    required int bdtId,
    required String justificativa,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/reabrir", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      "justificativa": justificativa.trim(),
    });

    if (res == null) {
      return {"success": false, "message": "Falha de comunicação."};
    }
    // ApiClient já padroniza a resposta com success/message
    return Map<String, dynamic>.from(res);
  }

  // ==========================================================
  // Sprint M3 — Pré-BDT (condutor pré-cria um BDT via app)
  //
  // Envia:
  //   {
  //     fk_veiculo: int,
  //     data_referencia: 'YYYY-MM-DD' (opcional),
  //     observacoes_gerais: string?,
  //     trechos: [
  //       { origem, destino, saida?, chegada?, obs? }
  //     ]
  //   }
  //
  // Retorna: { success, message, bdt_id?, protocolo? }
  // ==========================================================

  /// Lista os Pré-BDTs do usuário logado que ainda estão aguardando
  /// aprovação do admin (Sprint M3, tela inicial do app).
  static Future<List<PreBdtPendente>> listarMeusPreBdtsPendentes() async {
    final usuarioId = await _userId();
    final res = await ApiClient.post(
      'transporte/api/bdt/pre-bdt/meus-pendentes',
      {'usuario_id': usuarioId},
    );
    if (res['success'] != true) {
      _log.warn('listarMeusPreBdtsPendentes FALHOU: ${res['message']}');
      return const [];
    }
    final list = (res['data'] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => PreBdtPendente.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Autocomplete de veículos (Sprint M3).
  /// `q` vazio → 12 veículos mais recentes (para o campo abrir com opções).
  /// Backend faz LIKE em placa + modelo + marca.
  static Future<List<Veiculo>> buscarVeiculos({
    String q = '',
    int limit = 12,
  }) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post('transporte/api/bdt/veiculos/buscar', {
      'usuario_id': usuarioId,
      if (q.trim().isNotEmpty) 'q': q.trim(),
      'limit': limit,
    });
    if (res['success'] != true) {
      _log.warn('buscarVeiculos FALHOU: ${res['message']}');
      return const [];
    }
    final list = (res['data'] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => Veiculo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<Map<String, dynamic>> criarPreBdt({
    required int fkVeiculo,
    String? dataReferencia,
    String? observacoesGerais,
    required List<Map<String, dynamic>> trechos,
  }) async {
    final usuarioId = await _userId();

    final payload = <String, dynamic>{
      'usuario_id': usuarioId,
      'fk_veiculo': fkVeiculo,
      if (dataReferencia != null && dataReferencia.isNotEmpty)
        'data_referencia': dataReferencia,
      if (observacoesGerais != null && observacoesGerais.trim().isNotEmpty)
        'observacoes_gerais': observacoesGerais.trim(),
      'trechos': trechos,
    };

    final res = await ApiClient.post(
      'transporte/api/bdt/pre-bdt/criar',
      payload,
    );

    return Map<String, dynamic>.from(res);
  }

  // ==========================================================
  // Sprint M4 — Validação de atendimento
  // ==========================================================

  /// Registra um marco da jornada COM assinatura opcional (M4).
  /// Reusa o endpoint bdt/jornada/marco que já suporta os campos novos.
  static Future<Map<String, dynamic>> registrarMarcoComAssinatura({
    required int bdtId,
    required String marco, // partida|apresentacao|embarque_passageiro
    String? observacao,
    String? assinaturaSvg,
    String? signatarioNome,
    String? signatarioTipo, // condutor|passageiro|outro
  }) async {
    final usuarioId = await _userId();

    final payload = <String, dynamic>{
      'bdt_id': bdtId,
      'marco': marco,
      'usuario_id': usuarioId,
      if (observacao != null && observacao.trim().isNotEmpty)
        'observacao': observacao.trim(),
      if (assinaturaSvg != null && assinaturaSvg.trim().isNotEmpty)
        'assinatura_svg': assinaturaSvg,
      if (signatarioNome != null && signatarioNome.trim().isNotEmpty)
        'signatario_nome': signatarioNome.trim(),
      if (signatarioTipo != null && signatarioTipo.trim().isNotEmpty)
        'signatario_tipo': signatarioTipo,
    };

    final res = await ApiClient.post(
      'transporte/api/bdt/jornada/marco',
      payload,
    );
    _log.info('registrarMarcoComAssinatura marco=$marco ok=${res["success"]}');
    return Map<String, dynamic>.from(res);
  }

  /// Lista passageiros previstos do BDT (M4.1).
  static Future<List<Passageiro>> listarPassageiros(int bdtId) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post('transporte/api/bdt/passageiros/listar', {
      'bdt_id': bdtId,
      'usuario_id': usuarioId,
    });
    if (res['success'] != true) {
      _log.warn('listarPassageiros FALHOU: ${res['message']}');
      return const [];
    }
    final list = (res['data'] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => Passageiro.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Envia bulk update de presença/embarque_extra dos passageiros (M4.1).
  static Future<bool> marcarPresencaPassageiros({
    required int bdtId,
    required List<Map<String, dynamic>> updates,
  }) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post(
      'transporte/api/bdt/passageiros/marcar-presenca',
      {
        'bdt_id': bdtId,
        'usuario_id': usuarioId,
        'updates': updates,
      },
    );
    final ok = res['success'] == true;
    _log.info('marcarPresencaPassageiros ok=$ok updated=${res['atualizados']}');
    return ok;
  }

  /// Encerra o BDT (M4.3). Mudança para status ENCERRADO=3.
  static Future<Map<String, dynamic>> encerrarBdt({
    required int bdtId,
    String? observacao,
  }) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post('transporte/api/bdt/encerrar', {
      'bdt_id': bdtId,
      'usuario_id': usuarioId,
      if (observacao != null && observacao.trim().isNotEmpty)
        'observacao': observacao.trim(),
    });
    _log.info('encerrarBdt ok=${res["success"]} msg=${res["message"]}');
    return Map<String, dynamic>.from(res);
  }

  /// Registra o feedback do condutor sobre a viagem (M4.3).
  /// Upsert do lado backend: 1 feedback por BDT.
  static Future<bool> registrarFeedbackCondutor({
    required int bdtId,
    required int nota, // 1-5
    String? comentario,
  }) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post(
      'transporte/api/bdt/feedback-condutor/registrar',
      {
        'bdt_id': bdtId,
        'usuario_id': usuarioId,
        'nota': nota,
        if (comentario != null && comentario.trim().isNotEmpty)
          'comentario': comentario.trim(),
      },
    );
    final ok = res['success'] == true;
    _log.info('registrarFeedbackCondutor ok=$ok nota=$nota');
    return ok;
  }

  /// Obtém feedback existente (para a UI mostrar em modo readonly).
  static Future<FeedbackCondutor?> obterFeedbackCondutor(int bdtId) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post(
      'transporte/api/bdt/feedback-condutor/obter',
      {'bdt_id': bdtId, 'usuario_id': usuarioId},
    );
    if (res['success'] != true) return null;
    final j = res['feedback'];
    if (j is! Map) return null;
    return FeedbackCondutor.fromJson(Map<String, dynamic>.from(j));
  }
}
