import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Sprint 18 W+M — thumbnail genérico de foto/documento.
///
/// Recebe:
///  - [docId]: id do documento em `doc_documentos` (identificador único
///    global — mesmo doc pode ser referenciado por várias telas);
///  - [fetcher]: callback assíncrono que baixa os bytes do binário
///    (`(docId) → Future<List<int>?>`). Passa `AbastecimentoFotoService.obter`,
///    `OcorrenciaService.obterFoto`, etc.
///  - [cacheNamespace]: string que separa caches por FLUXO. Necessário
///    porque doc_ids podem colidir entre fluxos (o `doc_id=42` do fluxo
///    abastecimento aponta pra arquivo diferente do `doc_id=42` do fluxo
///    ocorrência — na prática são globais, mas dependendo do endpoint
///    de obter, o ownership é distinto). Usar o próprio endpoint como
///    namespace evita bugs latentes.
///
/// # Migração
///
/// `FotoOcorrenciaThumb` (Sprint 17) virou um shim que instancia este
/// widget com o `OcorrenciaService.obterFoto` como fetcher — nenhum
/// caller antigo precisa mudar.
class FotoDocumentoThumb extends StatefulWidget {
  final int docId;
  final Future<List<int>?> Function(int docId) fetcher;
  final String cacheNamespace;
  final double size;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  const FotoDocumentoThumb({
    super.key,
    required this.docId,
    required this.fetcher,
    required this.cacheNamespace,
    this.size = 88,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  // Cache global keyed por (cacheNamespace, docId).
  // Evita rebaixar toda vez que a grade rerender + evita colisão de
  // docId entre fluxos.
  static final Map<String, Uint8List> _cache = {};

  static String _cacheKey(String ns, int docId) => '$ns::$docId';

  /// Limpa o cache de um fluxo específico — útil quando o usuário
  /// deleta uma foto e a UI dá refresh (evita mostrar bytes obsoletos
  /// se um docId for reutilizado no futuro).
  static void invalidate({required String cacheNamespace, int? docId}) {
    if (docId != null) {
      _cache.remove(_cacheKey(cacheNamespace, docId));
      return;
    }
    _cache.removeWhere((k, _) => k.startsWith('$cacheNamespace::'));
  }

  @override
  State<FotoDocumentoThumb> createState() => _FotoDocumentoThumbState();
}

class _FotoDocumentoThumbState extends State<FotoDocumentoThumb> {
  Uint8List? _bytes;
  bool _erro = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FotoDocumentoThumb old) {
    super.didUpdateWidget(old);
    if (old.docId != widget.docId ||
        old.cacheNamespace != widget.cacheNamespace) {
      _bytes = null;
      _erro = false;
      _load();
    }
  }

  Future<void> _load() async {
    final key = FotoDocumentoThumb._cacheKey(
      widget.cacheNamespace,
      widget.docId,
    );
    final cached = FotoDocumentoThumb._cache[key];
    if (cached != null) {
      setState(() => _bytes = cached);
      return;
    }
    final bytes = await widget.fetcher(widget.docId);
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _erro = true);
      return;
    }
    final u8 = Uint8List.fromList(bytes);
    FotoDocumentoThumb._cache[key] = u8;
    setState(() => _bytes = u8);
  }

  @override
  Widget build(BuildContext context) {
    final child = _bytes != null
        ? Image.memory(_bytes!, fit: BoxFit.cover)
        : Container(
            color: const Color(0xFFEEEEEE),
            alignment: Alignment.center,
            child: _erro
                ? const Icon(Icons.broken_image, color: Colors.black38)
                : const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
          );

    final container = SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipRRect(borderRadius: widget.borderRadius, child: child),
    );

    if (widget.onTap == null) return container;
    return InkWell(
      onTap: widget.onTap,
      borderRadius: widget.borderRadius,
      child: container,
    );
  }
}
