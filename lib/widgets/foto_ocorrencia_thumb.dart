import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/ocorrencia_service.dart';

/// Thumbnail de uma foto de ocorrência já persistida no servidor.
///
/// Baixa o binário sob demanda (`OcorrenciaService.obterFoto(docId)`),
/// mesmo padrão do MSEC.6 (endpoint com Bearer + ETag). Cache local
/// simples em memória por `docId` — evita rebaixar toda vez que a
/// grade rerender.
///
/// Sprint W+M (Sprint 17 W+M Fase 2). Widget PLATFORM-agnostic (só
/// consome bytes; não toca em plugin de OS).
class FotoOcorrenciaThumb extends StatefulWidget {
  final int docId;
  final double size;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  const FotoOcorrenciaThumb({
    super.key,
    required this.docId,
    this.size = 88,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  static final Map<int, Uint8List> _cache = {};

  @override
  State<FotoOcorrenciaThumb> createState() => _FotoOcorrenciaThumbState();
}

class _FotoOcorrenciaThumbState extends State<FotoOcorrenciaThumb> {
  Uint8List? _bytes;
  bool _erro = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FotoOcorrenciaThumb old) {
    super.didUpdateWidget(old);
    if (old.docId != widget.docId) {
      _bytes = null;
      _erro = false;
      _load();
    }
  }

  Future<void> _load() async {
    final cached = FotoOcorrenciaThumb._cache[widget.docId];
    if (cached != null) {
      setState(() => _bytes = cached);
      return;
    }
    final bytes = await OcorrenciaService.obterFoto(widget.docId);
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _erro = true);
      return;
    }
    final u8 = Uint8List.fromList(bytes);
    FotoOcorrenciaThumb._cache[widget.docId] = u8;
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
