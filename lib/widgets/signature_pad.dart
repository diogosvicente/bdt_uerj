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

  /// Mensagem de erro sob o painel — mesmo papel do `errorText` de um
  /// `TextField`, para a assinatura seguir o padrão de required inline dos
  /// outros forms do BDT.
  final String? errorText;

  /// Chamado quando o usuário confirma com o painel VAZIO.
  ///
  /// Antes de 2026-08-10 esse caso caía num `return` mudo: a pessoa tocava
  /// "Confirmar assinatura" e não acontecia nada — nem envio, nem aviso. O
  /// campo de nome ao lado já apontava o erro inline; a assinatura, que é o
  /// objeto da tela, era a única coisa que falhava em silêncio.
  final VoidCallback? onEmptyConfirm;

  const SignaturePad({
    super.key,
    this.height = 220,
    this.onConfirmed,
    this.errorText,
    this.onEmptyConfirm,
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
    if (widget.onConfirmed == null || _enviando) return;

    // Painel vazio agora AVISA em vez de retornar calado.
    if (_ctrl.isEmpty) {
      widget.onEmptyConfirm?.call();

      return;
    }

    final svg = _ctrl.toRawSVG();

    // `toRawSVG()` devolver null com o painel não-vazio não deveria acontecer,
    // mas se acontecer o usuário precisa saber — antes isso também era um
    // `return` mudo.
    if (svg == null) {
      widget.onEmptyConfirm?.call();

      return;
    }
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
            // Borda vermelha quando há erro, como o `OutlineInputBorder` de um
            // `TextField` em estado de erro faz.
            border: Border.all(
              color: widget.errorText != null
                  ? Theme.of(context).colorScheme.error
                  : Colors.black26,
              width: widget.errorText != null ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Signature(
            controller: _ctrl,
            backgroundColor: Colors.white,
          ),
        ),

        // Mesma posição, cor e tamanho do `errorText` de um `TextField`.
        if (widget.errorText != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              widget.errorText!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],

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
