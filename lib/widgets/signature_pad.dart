import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../theme/app_theme.dart';

/// Widget de assinatura touch com botões de "Limpar" e "OK".
///
/// **Uso:**
/// ```dart
/// SignaturePad(
///   height: 220,
///   onConfirmed: (svg) async { ... use o SVG ... },
/// )
/// ```
///
/// Retorna o desenho como SVG string via `onConfirmed`. É pequeno o
/// suficiente (< 5KB tipicamente) para enviar direto no body do endpoint
/// `bdt/jornada/marco` sem uploads separados.
///
/// Ver `docs/ARCHITECTURE.md` §4.8 para o padrão de widget composto.
class SignaturePad extends StatefulWidget {
  final double height;
  final Future<void> Function(String svg)? onConfirmed;

  const SignaturePad({
    super.key,
    this.height = 220,
    this.onConfirmed,
  });

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  late final SignatureController _ctrl;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _ctrl = SignatureController(
      penStrokeWidth: 2.2,
      penColor: Colors.black,
      exportBackgroundColor: Colors.transparent,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get isEmpty => _ctrl.isEmpty;

  /// Exporta o desenho atual como SVG string. `null` se vazio.
  String? currentSvg() {
    if (_ctrl.isEmpty) return null;
    return _ctrl.toRawSVG();
  }

  void clear() => _ctrl.clear();

  Future<void> _handleConfirm() async {
    if (widget.onConfirmed == null || _ctrl.isEmpty || _enviando) return;
    final svg = _ctrl.toRawSVG();
    if (svg == null) return;
    setState(() => _enviando = true);
    try {
      await widget.onConfirmed!(svg);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black26),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Signature(
            controller: _ctrl,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _enviando ? null : clear,
                icon: const Icon(Icons.refresh),
                label: const Text('Limpar'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _enviando ? null : _handleConfirm,
                icon: _enviando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Confirmar assinatura'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
