import 'foto_documento_client.dart';

/// Sprint 18 W+M — fotos de vistoria de uma manutenção (Antes / Depois).
///
/// A discriminação por fase é feita pelo `doc_tipo` no backend
/// (`FOTO_VISTORIA_ANTES` / `FOTO_VISTORIA_DEPOIS`), não por texto. O
/// mobile envia `fase=antes|depois` e o backend rota pra
/// `salvarAntes/salvarDepois` do `ManutencaoFotoService`.
class ManutencaoFotoService {
  static const _client = FotoDocumentoClient(
    uploadPath:  'transporte/api/bdt/manutencoes/fotos/upload',
    listarPath:  'transporte/api/bdt/manutencoes/fotos/listar',
    obterPath:   'transporte/api/bdt/manutencoes/fotos/obter',
    excluirPath: 'transporte/api/bdt/manutencoes/fotos/excluir',
    refField: 'id_manutencao',
  );

  static Future<List<FotoDocumentoRef>> listar(int manutencaoId) =>
      _client.listar(manutencaoId);

  static Future<List<int>?> obter(int docId, {int? manutencaoId}) =>
      _client.obter(docId, refId: manutencaoId);

  static Future<bool> excluir(int docId, {int? manutencaoId}) =>
      _client.excluir(docId, refId: manutencaoId);

  /// Sobe uma foto na fase indicada. `fase` deve ser `antes` ou `depois`.
  static Future<int> upload({
    required int manutencaoId,
    required List<int> bytes,
    required String filename,
    required String fase,
  }) {
    return _client.upload(
      refId: manutencaoId,
      bytes: bytes,
      filename: filename,
      extraFields: {'fase': fase},
    );
  }
}
