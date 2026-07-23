import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Preview compacto de uma assinatura capturada.
///
/// Recebe o SVG cru (`assinatura_svg`) que veio do endpoint
/// `POST bdt/jornada/estado` (`marcos[<slug>].assinatura.assinatura_svg`) —
/// mesmo formato produzido pelo `SignatureController.toRawSVG()` do
/// package `signature`. Renderiza dentro de uma moldura leve pra dar
/// contexto visual (senão o traço "flutua" no card).
///
/// Sprint W+M — permite ver a assinatura salva nas telas de marcos
/// (`ValidacaoInicioPage`, `BdtFormPage`). Retorna [SizedBox.shrink]
/// quando o SVG está vazio/nulo — sem placeholder, o caller decide
/// se quer render alternativo.
class AssinaturaPreview extends StatelessWidget {
  final String? svg;
  final double height;

  const AssinaturaPreview({
    super.key,
    required this.svg,
    this.height = 80,
  });

  @override
  Widget build(BuildContext context) {
    final raw = svg?.trim() ?? '';
    if (raw.isEmpty || !raw.contains('<svg')) {
      return const SizedBox.shrink();
    }

    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      padding: const EdgeInsets.all(6),
      alignment: Alignment.center,
      child: SvgPicture.string(
        raw,
        fit: BoxFit.contain,
        // Placeholder simples enquanto o parser inicial roda.
        placeholderBuilder: (_) => const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}
