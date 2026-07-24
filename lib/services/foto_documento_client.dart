import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../utils/logger.dart';

/// Sprint 18 W+M — cliente genérico pros endpoints de foto/anexo do
/// módulo Transporte no backend.
///
/// Todos os fluxos (Ocorrência, Carga do Pré-BDT, Abastecimento,
/// Manutenção) expõem os MESMOS 4 endpoints:
///   POST bdt/<fluxo>/fotos/upload    (multipart)
///   POST bdt/<fluxo>/fotos/listar    (JSON)
///   POST bdt/<fluxo>/fotos/obter     (JSON → binário + ETag)
///   POST bdt/<fluxo>/fotos/excluir   (JSON)
///
/// A única diferença por fluxo é:
///  - o NOME do endpoint (path);
///  - o campo REFERÊNCIA no payload (`id_ocorrencia` / `bdt_id` /
///    `id_abastecimento` / `id_manutencao`);
///  - campos EXTRA opcionais no upload (fk_tipo_foto, fase, is_nota_fiscal).
///
/// Este cliente parametriza tudo isso — os wrappers específicos por fluxo
/// (OcorrenciaService, AbastecimentoFotoService, ...) são thin wrappers
/// que instanciam o cliente com os endpoints/refField corretos.
///
/// # Reuso
///
/// No backend, todos os endpoints delegam pro `DocumentoService::save…`
/// (fonte única). Aqui no mobile, todos os fluxos delegam pra este cliente.
/// Zero duplicação — se o formato do response mudar, muda em UM lugar.
class FotoDocumentoClient {
  static const _log = Logger('FOTO-DOC');

  /// Endpoint de upload (path completo após `transporte/api/`). Ex:
  /// `transporte/api/bdt/abastecimentos/fotos/upload`.
  final String uploadPath;
  final String listarPath;
  final String obterPath;
  final String excluirPath;

  /// Nome do campo no payload que identifica a referência do fluxo.
  /// Ex: `id_abastecimento`, `id_manutencao`, `id_ocorrencia`, `bdt_id`.
  final String refField;

  const FotoDocumentoClient({
    required this.uploadPath,
    required this.listarPath,
    required this.obterPath,
    required this.excluirPath,
    required this.refField,
  });

  static Future<int> _userId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('usuario_id') ?? 0;
  }

  /// Sobe uma foto. `refId` é o valor do campo [refField]. Campos extras
  /// (ex: `fk_tipo_foto`, `fase`, `is_nota_fiscal`) vão em [extraFields].
  ///
  /// Retorna o docId no sucesso, ou 0 em falha.
  Future<int> upload({
    required int refId,
    required List<int> bytes,
    required String filename,
    Map<String, String>? extraFields,
  }) async {
    final usuarioId = await _userId();
    final res = await ApiClient.postMultipart(
      uploadPath,
      fields: {
        'usuario_id': '$usuarioId',
        refField: '$refId',
        ...?extraFields,
      },
      fileField: 'foto',
      fileBytes: bytes,
      filename: filename,
    );
    if (res['success'] != true) {
      _log.warn(
        'upload $uploadPath refId=$refId FALHOU: '
        'http=${res['http_status']} status=${res['status']} '
        'msg=${res['message']}',
      );
      return 0;
    }
    final data = res['data'];
    if (data is! Map) return 0;
    // Backend novo usa `doc_id`; endpoint antigo de ocorrência (pré-Sprint
    // 18) usava `id`. Aceita ambos pra sobreviver a redeploys parciais.
    final raw = data['doc_id'] ?? data['id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  /// Lista as fotos (metadata) da referência.
  Future<List<FotoDocumentoRef>> listar(int refId) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post(listarPath, {
      'usuario_id': usuarioId,
      refField: refId,
    });
    if (res['success'] != true) {
      _log.warn(
        'listar $listarPath refId=$refId FALHOU: ${res['message']}',
      );
      return const [];
    }
    final list = (res['data'] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => FotoDocumentoRef.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Baixa o binário de uma foto. `refId` opcional — quando presente é
  /// enviado no payload pro backend validar ownership contextual (foto
  /// pertence à referência informada). Quando o backend NÃO exige, pode
  /// ser omitido (endpoints legados só validam pelo docId).
  Future<List<int>?> obter(int docId, {int? refId}) async {
    final usuarioId = await _userId();
    return ApiClient.postForBytes(obterPath, {
      'usuario_id': usuarioId,
      'doc_id': docId,
      if (refId != null && refId > 0) refField: refId,
    });
  }

  /// Remove uma foto. `refId` opcional (mesmo racional de [obter]).
  Future<bool> excluir(int docId, {int? refId}) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post(excluirPath, {
      'usuario_id': usuarioId,
      'doc_id': docId,
      if (refId != null && refId > 0) refField: refId,
    });
    return res['success'] == true;
  }
}

/// Referência leve pra uma foto persistida — mesmo shape que o backend
/// devolve em `fotos/listar`. Substitui o `OcorrenciaFotoRef` antigo
/// (mantido como alias em ocorrencia_service.dart pra retrocompat).
///
/// `descricao` é o SUBTIPO no fluxo Abastecimento (Odômetro, Bomba, Nota
/// Fiscal…). Nos outros fluxos costuma ser fixo (Foto da ocorrência,
/// Foto de carga, Foto antes/depois da manutenção). `fkTipo` é o
/// `doc_tipos.id` — útil pra distinguir fase Antes/Depois na manutenção
/// sem parsear texto.
class FotoDocumentoRef {
  final int id;
  final String? mimeType;
  final String? createdAt;
  final String? descricao;
  final int? fkTipo;

  const FotoDocumentoRef({
    required this.id,
    this.mimeType,
    this.createdAt,
    this.descricao,
    this.fkTipo,
  });

  factory FotoDocumentoRef.fromJson(Map<String, dynamic> j) {
    final rawId = j['id'];
    final rawTipo = j['fk_tipo'];
    return FotoDocumentoRef(
      id: rawId is int ? rawId : (int.tryParse(rawId?.toString() ?? '') ?? 0),
      mimeType: j['mime_type']?.toString(),
      createdAt: j['created_at']?.toString(),
      descricao: j['descricao']?.toString(),
      fkTipo: rawTipo is int
          ? rawTipo
          : int.tryParse(rawTipo?.toString() ?? ''),
    );
  }
}
