import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/ocorrencia.dart';
import '../models/ocorrencia_filtros.dart';
import '../utils/logger.dart';

/// Sprint W+M (Sprint 17 web / W15 F3) — Histórico institucional de
/// ocorrências. Fachada tipada dos 3 endpoints
/// `POST transporte/api/bdt/ocorrencias/{historico,detalhes,filtros}`.
///
/// [[bdt_uerj_reusar_codigo_web]]: os endpoints são wrappers do
/// `OcorrenciaService` do web — mesma lista/detalhe/filtros que o admin
/// vê em `/transporte/admin/ocorrencias/historico`.
///
/// Categoria: **API** (só HTTP + Model, nada de storage/OS).
class OcorrenciaService {
  static const _log = Logger('OCORRENCIA-SVC');

  static Future<int> _userId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('usuario_id') ?? 0;
  }

  /// Lista o histórico com filtros opcionais (todos como null = sem filtro,
  /// igual à tela admin do web). Datas em ISO `YYYY-MM-DD`.
  ///
  /// Retorna lista vazia em qualquer falha de rede/backend — a UI mostra
  /// "nenhuma ocorrência" e o [Logger] guarda o motivo.
  static Future<List<Ocorrencia>> historico({
    int? veiculoId,
    int? condutorId,
    int? tipoId,
    String? de,
    String? ate,
  }) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post('transporte/api/bdt/ocorrencias/historico', {
      'usuario_id': usuarioId,
      if (veiculoId != null && veiculoId > 0) 'veiculo': veiculoId,
      if (condutorId != null && condutorId > 0) 'condutor': condutorId,
      if (tipoId != null && tipoId > 0) 'tipo': tipoId,
      if (de != null && de.isNotEmpty) 'de': de,
      if (ate != null && ate.isNotEmpty) 'ate': ate,
    });
    if (res['success'] != true) {
      _log.warn('historico FALHOU: ${res['message']}');
      return const [];
    }
    final list = (res['data'] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => Ocorrencia.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Detalhe de uma ocorrência. Retorna `null` se não encontrada (404)
  /// ou falha de rede — a UI mostra estado de erro.
  static Future<Ocorrencia?> detalhes(int id) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post('transporte/api/bdt/ocorrencias/detalhes', {
      'usuario_id': usuarioId,
      'id': id,
    });
    if (res['success'] != true) {
      _log.warn('detalhes#$id FALHOU: ${res['message']}');
      return null;
    }
    final data = res['data'];
    if (data is! Map) return null;
    return Ocorrencia.fromJson(Map<String, dynamic>.from(data));
  }

  /// Listas usadas nos filtros (veículos, condutores, tipos) —
  /// numa única chamada, pra evitar 3 requests da UI. Sempre retorna
  /// um [OcorrenciaFiltros] vazio em caso de falha (UI continua funcional
  /// sem filtros).
  static Future<OcorrenciaFiltros> filtros() async {
    final usuarioId = await _userId();
    final res = await ApiClient.post('transporte/api/bdt/ocorrencias/filtros', {
      'usuario_id': usuarioId,
    });
    if (res['success'] != true) {
      _log.warn('filtros FALHOU: ${res['message']}');
      return const OcorrenciaFiltros();
    }
    final data = res['data'];
    if (data is! Map) return const OcorrenciaFiltros();
    return OcorrenciaFiltros.fromJson(Map<String, dynamic>.from(data));
  }
}
