import '../api/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bdt_resumo.dart';
import 'location_service.dart';

class BdtService {
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

  /// Detalhes completos do BDT
  static Future<Map<String, dynamic>?> detalhes(int bdtId) async {
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
    if (resolvedLoc == null) return false;

    final payload = <String, dynamic>{
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      if (agendaId != null) "agenda_id": agendaId,
      if (trechoId != null) "trecho_id": trechoId,
      "loc": resolvedLoc,
    };

    final res = await ApiClient.post("transporte/api/bdt/localizacao", payload);
    return res != null && res["success"] == true;
  }

  /// Salva campos do formulário do BDT (baseado no papel)
  static Future<bool> salvarCamposBdt({
    required int bdtId,
    required Map<String, dynamic> campos,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/salvar", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      "campos": campos,
    });

    return res != null && res["success"] == true;
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

    // ✅ rota nova (se existir no backend)
    var res = await ApiClient.post("transporte/api/bdt/trecho/extra/criar", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      "origem": origem,
      "destino": destino,
      if (agendaId != null) "agenda_id": agendaId,
    });

    // ✅ fallback rota antiga (se seu routes ainda usa trechos/create)
    if (res == null || res["success"] != true) {
      res = await ApiClient.post("transporte/api/bdt/trechos/create", {
        "bdt_id": bdtId,
        "usuario_id": usuarioId,
        "fk_agenda": agendaId, // null => extra
        "origem": origem,
        "destino": destino,
      });
    }

    return res != null && res["success"] == true;
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
}
