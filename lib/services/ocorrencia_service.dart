import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/ocorrencia.dart';
import '../models/ocorrencia_filtros.dart';
import '../utils/logger.dart';
import 'foto_documento_client.dart';

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

  // ================= CRUD (Fase 1 — sem fotos) =====================

  /// Sprint W+M (Sprint 17 web F2) — catálogo de tipos de ocorrência
  /// pra popular o dropdown do form "Nova ocorrência". Fonte:
  /// `OcorrenciaTipoModel::getAllOrdenados()` do web via wrapper.
  ///
  /// Espelha [OcorrenciaFiltroItem] em shape ({id, label}) — reuso.
  static Future<List<OcorrenciaFiltroItem>> tipos() async {
    final usuarioId = await _userId();
    final res = await ApiClient.post('transporte/api/bdt/ocorrencias/tipos', {
      'usuario_id': usuarioId,
    });
    if (res['success'] != true) {
      _log.warn('tipos FALHOU: ${res['message']}');
      return const [];
    }
    final list = (res['data'] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => OcorrenciaFiltroItem.fromJson(
              Map<String, dynamic>.from(e),
              'nome',
            ))
        .toList();
  }

  /// Cria uma ocorrência no BDT em andamento. Retorna o `id` inserido,
  /// ou `0` em falha (a UI mostra `formError` a partir do `res['message']`).
  ///
  /// Backend valida ownership (só o condutor do BDT pode registrar).
  /// Fotos entram na Fase 2 (multipart upload dedicado).
  static Future<Map<String, dynamic>> criar({
    required int bdtId,
    required String titulo,
    String? descricao,
    int? fkOcorrenciaTipo,
    String? dataHora,
  }) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post('transporte/api/bdt/ocorrencias/criar', {
      'usuario_id': usuarioId,
      'bdt_id': bdtId,
      'titulo': titulo.trim(),
      if (descricao != null && descricao.trim().isNotEmpty)
        'descricao': descricao.trim(),
      if (fkOcorrenciaTipo != null && fkOcorrenciaTipo > 0)
        'fk_ocorrencia_tipo': fkOcorrenciaTipo,
      if (dataHora != null && dataHora.isNotEmpty) 'data_hora': dataHora,
    });
    _log.info('criar http=${res["http_status"]} ok=${res["success"]}');
    return res;
  }

  /// Soft-delete de uma ocorrência (exclui também as fotos anexadas).
  /// Backend valida ownership.
  static Future<bool> excluir(int id) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post('transporte/api/bdt/ocorrencias/excluir', {
      'usuario_id': usuarioId,
      'id': id,
    });
    return res['success'] == true;
  }

  // ================= FOTOS (Sprint 17 F2 + Sprint 18 refactor) =====

  /// Sprint 18 W+M — thin wrapper sobre o [FotoDocumentoClient] genérico.
  /// A API pública deste service continua igual (não quebra callers),
  /// mas a lógica de HTTP/multipart/parse vive num único lugar.
  static const _fotoClient = FotoDocumentoClient(
    uploadPath:  'transporte/api/bdt/ocorrencias/fotos/upload',
    listarPath:  'transporte/api/bdt/ocorrencias/fotos/listar',
    obterPath:   'transporte/api/bdt/ocorrencias/fotos/obter',
    excluirPath: 'transporte/api/bdt/ocorrencias/fotos/excluir',
    refField: 'id_ocorrencia',
  );

  /// Lista os IDs + metadados das fotos de uma ocorrência (sem os
  /// binários). A UI faz `obterFoto(docId)` sob demanda pra baixar cada
  /// binário — mesmo padrão MSEC.6.
  static Future<List<OcorrenciaFotoRef>> listarFotos(int ocorrenciaId) async {
    final refs = await _fotoClient.listar(ocorrenciaId);
    // Adapta pro tipo antigo (mantido pra retrocompat de callers).
    return refs
        .map((r) => OcorrenciaFotoRef(
              id: r.id,
              mimeType: r.mimeType,
              createdAt: r.createdAt,
            ))
        .toList();
  }

  /// Baixa o binário de uma foto específica (ownership validado
  /// server-side). Retorna `null` em falha — a UI mostra placeholder.
  static Future<List<int>?> obterFoto(int docId) => _fotoClient.obter(docId);

  /// Upload de uma foto pra ocorrência já criada. Retorna o `docId`
  /// no sucesso ou `0` em falha.
  static Future<int> uploadFoto({
    required int ocorrenciaId,
    required List<int> bytes,
    required String filename,
  }) {
    return _fotoClient.upload(
      refId: ocorrenciaId,
      bytes: bytes,
      filename: filename,
    );
  }

  /// Remove uma foto (soft-delete server-side + limpa arquivo físico).
  static Future<bool> excluirFoto(int docId) => _fotoClient.excluir(docId);
}

/// Referência leve pra uma foto já persistida (a UI faz `obterFoto`
/// sob demanda pra baixar o binário). Espelha `{id, mime_type,
/// created_at}` do endpoint `fotos/listar`.
class OcorrenciaFotoRef {
  final int id;
  final String? mimeType;
  final String? createdAt;

  const OcorrenciaFotoRef({
    required this.id,
    this.mimeType,
    this.createdAt,
  });

  factory OcorrenciaFotoRef.fromJson(Map<String, dynamic> j) {
    final rawId = j['id'];
    return OcorrenciaFotoRef(
      id: rawId is int ? rawId : (int.tryParse(rawId?.toString() ?? '') ?? 0),
      mimeType: j['mime_type']?.toString(),
      createdAt: j['created_at']?.toString(),
    );
  }
}
