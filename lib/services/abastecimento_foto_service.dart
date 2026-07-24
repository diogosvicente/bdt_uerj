import '../api/api_client.dart';
import '../utils/logger.dart';
import 'foto_documento_client.dart';

/// Sprint 18 W+M — fotos de um abastecimento (paridade com o form web).
///
/// Wrapper fino sobre [FotoDocumentoClient] + método específico para o
/// catálogo de subtipos (Odômetro, Bomba, Tanque, Cartão, Outros). O
/// upload aceita:
///  - `tipoFotoId`: item do catálogo → vira a `descricao` (subtipo);
///  - `isNotaFiscal`: rota o backend pra `salvarNotaFiscal` (aceita PDF
///    e grava descrição fixa "Nota Fiscal", separando-a das demais).
///
/// Backend reusa `AbastecimentoFotoService` + `DocumentoService` — todos
/// os arquivos ficam em `doc_documentos` + `doc_referencias` + storage
/// físico do padrão §9.1.
class AbastecimentoFotoService {
  static const _log = Logger('ABS-FOTO');

  static const _client = FotoDocumentoClient(
    uploadPath:  'transporte/api/bdt/abastecimentos/fotos/upload',
    listarPath:  'transporte/api/bdt/abastecimentos/fotos/listar',
    obterPath:   'transporte/api/bdt/abastecimentos/fotos/obter',
    excluirPath: 'transporte/api/bdt/abastecimentos/fotos/excluir',
    refField: 'id_abastecimento',
  );

  static Future<List<FotoDocumentoRef>> listar(int abastecimentoId) =>
      _client.listar(abastecimentoId);

  static Future<List<int>?> obter(int docId, {int? abastecimentoId}) =>
      _client.obter(docId, refId: abastecimentoId);

  static Future<bool> excluir(int docId, {int? abastecimentoId}) =>
      _client.excluir(docId, refId: abastecimentoId);

  /// Sobe uma foto de comprovação. `tipoFotoId` (do catálogo) e
  /// `isNotaFiscal` são mutuamente exclusivos: se `isNotaFiscal=true`,
  /// o backend ignora `tipoFotoId` e força o subtipo "Nota Fiscal".
  static Future<int> upload({
    required int abastecimentoId,
    required List<int> bytes,
    required String filename,
    int? tipoFotoId,
    bool isNotaFiscal = false,
  }) {
    return _client.upload(
      refId: abastecimentoId,
      bytes: bytes,
      filename: filename,
      extraFields: {
        if (isNotaFiscal) 'is_nota_fiscal': '1',
        if (!isNotaFiscal && tipoFotoId != null && tipoFotoId > 0)
          'fk_tipo_foto': '$tipoFotoId',
      },
    );
  }

  /// Sprint 18 W+M — Catálogo dos subtipos de foto de comprovação.
  /// Backend retorna a lista SEM a "Nota Fiscal" (que tem botão próprio
  /// na UI). Fallback local se a chamada falhar — igual ao padrão dos
  /// tipos de combustível: dropdown nunca fica vazio.
  static Future<List<Map<String, dynamic>>> listarTiposFoto() async {
    final res = await ApiClient.post(
      'transporte/api/bdt/abastecimentos/tipos-fotos',
      const {},
    );
    if (res['success'] != true) {
      _log.warn(
        'listarTiposFoto FALHOU (usando fallback local): '
        'http=${res['http_status']} status=${res['status']} '
        'msg=${res['message']}',
      );
      return _tiposFallback;
    }
    final list = (res['data'] as List<dynamic>? ?? const []);
    final tipos = list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((m) => (m['nome']?.toString() ?? '').isNotEmpty)
        .toList();
    return tipos.isEmpty ? _tiposFallback : tipos;
  }

  /// Fallback estático — espelha o seeder `TrnspAbastecimentoTipoFotoSeeder`
  /// (menos "Nota Fiscal", igual ao endpoint). Se o admin cadastrar tipo
  /// novo no web, ele só aparece online — offline mostra os 5 canônicos.
  static const List<Map<String, dynamic>> _tiposFallback = [
    {'id': 1, 'nome': 'Odômetro'},
    {'id': 2, 'nome': 'Bomba de combustível'},
    {'id': 3, 'nome': 'Tanque/Entrada de combustível'},
    {'id': 5, 'nome': 'Cartão de combustível'},
    {'id': 6, 'nome': 'Outros'},
  ];
}
