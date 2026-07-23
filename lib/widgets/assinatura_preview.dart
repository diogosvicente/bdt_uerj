import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/date_fmt.dart';

/// Botão compacto que abre um modal com a assinatura do marco.
///
/// O SVG cru (`assinatura_svg`) vem do endpoint `POST bdt/jornada/estado`
/// (`marcos[<slug>].assinatura.assinatura_svg`) — mesmo formato
/// produzido pelo `SignatureController.toRawSVG()` do package `signature`.
///
/// Sprint W+M — antes esse widget renderizava o traço direto no card,
/// mas o usuário pediu pra não expor a assinatura em disclosure passiva:
/// vira botão explícito → modal → dá a opção "Editar" quando o caller
/// passa [onEditar] (sem callback, sem botão). Retorna [SizedBox.shrink]
/// quando não tem SVG (assinatura ainda não registrada).
class AssinaturaViewButton extends StatelessWidget {
  final String? svg;

  /// Rótulo do marco pra montar o título do modal ("Partida", "Hora de saída").
  final String marcoLabel;

  /// Metadados textuais mostrados dentro do modal (opcionais).
  final String? assinadoPor;
  final String? signatarioTipo;
  final String? dataHora;
  final String? observacao;

  /// Se != null, mostra botão "Editar" no modal — chamado após fechar.
  /// Pai é responsável por levar o usuário ao form de nova assinatura.
  final VoidCallback? onEditar;

  const AssinaturaViewButton({
    super.key,
    required this.svg,
    required this.marcoLabel,
    this.assinadoPor,
    this.signatarioTipo,
    this.dataHora,
    this.observacao,
    this.onEditar,
  });

  bool get _temSvg {
    final raw = svg?.trim() ?? '';
    return raw.isNotEmpty && raw.contains('<svg');
  }

  Future<void> _abrirModal(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dctx) => _AssinaturaDialog(
        svg: svg!,
        marcoLabel: marcoLabel,
        assinadoPor: assinadoPor,
        signatarioTipo: signatarioTipo,
        dataHora: dataHora,
        observacao: observacao,
        onEditar: onEditar == null
            ? null
            : () {
                Navigator.pop(dctx);
                onEditar!();
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_temSvg) return const SizedBox.shrink();

    return OutlinedButton.icon(
      onPressed: () => _abrirModal(context),
      icon: const Icon(Icons.gesture, size: 18),
      label: const Text('Ver assinatura'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _AssinaturaDialog extends StatelessWidget {
  final String svg;
  final String marcoLabel;
  final String? assinadoPor;
  final String? signatarioTipo;
  final String? dataHora;
  final String? observacao;
  final VoidCallback? onEditar;

  const _AssinaturaDialog({
    required this.svg,
    required this.marcoLabel,
    this.assinadoPor,
    this.signatarioTipo,
    this.dataHora,
    this.observacao,
    this.onEditar,
  });

  @override
  Widget build(BuildContext context) {
    final autor = (assinadoPor ?? '').trim();
    final tipo = (signatarioTipo ?? '').trim();
    final dh = (dataHora ?? '').trim();
    final obs = (observacao ?? '').trim();

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.gesture, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Assinatura — $marcoLabel',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 160, maxHeight: 260),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              padding: const EdgeInsets.all(8),
              alignment: Alignment.center,
              child: SvgPicture.string(svg, fit: BoxFit.contain),
            ),
            if (autor.isNotEmpty ||
                tipo.isNotEmpty ||
                dh.isNotEmpty ||
                obs.isNotEmpty) ...[
              const SizedBox(height: 14),
              if (autor.isNotEmpty)
                _linha(Icons.person, tipo.isNotEmpty ? '$autor · $tipo' : autor),
              if (dh.isNotEmpty)
                _linha(Icons.schedule, DateFmt.dataHoraBr(dh)),
              if (obs.isNotEmpty) _linha(Icons.notes, obs),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
        if (onEditar != null)
          FilledButton.icon(
            onPressed: onEditar,
            icon: const Icon(Icons.edit),
            label: const Text('Editar'),
          ),
      ],
    );
  }

  Widget _linha(IconData ic, String txt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ic, size: 16, color: Colors.black54),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              txt,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
