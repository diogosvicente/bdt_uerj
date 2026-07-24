import 'package:flutter/material.dart';

import '../services/ocorrencia_service.dart';
import 'foto_documento_thumb.dart';

/// Sprint 17 W+M — thumbnail de foto de ocorrência.
///
/// **Sprint 18 refactor:** virou um shim sobre o widget genérico
/// [FotoDocumentoThumb], que aceita qualquer fetcher (abastecimento,
/// manutenção, carga, ocorrência). Zero mudança pra callers antigos.
class FotoOcorrenciaThumb extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    return FotoDocumentoThumb(
      docId: docId,
      fetcher: OcorrenciaService.obterFoto,
      cacheNamespace: 'ocorrencia',
      size: size,
      onTap: onTap,
      borderRadius: borderRadius,
    );
  }
}
