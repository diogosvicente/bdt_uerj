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

  /// Inicia trecho (envia loc junto se tiver)
  static Future<bool> iniciarTrecho({
    required int bdtId,
    required int agendaId,
    required int trechoId,
  }) async {
    final usuarioId = await _userId();

    final loc = await LocationService.getLocPayload();

    final payload = <String, dynamic>{
      "bdt_id": bdtId,
      "agenda_id": agendaId,
      "trecho_id": trechoId,
      "usuario_id": usuarioId,
      if (loc != null) "loc": loc,
    };

    final res = await ApiClient.post("transporte/api/bdt/trecho/iniciar", payload);
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

    final res = await ApiClient.post("transporte/api/bdt/trecho/finalizar", payload);
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

    final Map<String, dynamic>? resolvedLoc = loc ?? await LocationService.getLocPayload();
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
}
