import 'package:flutter/material.dart';

import '../services/captcha_service.dart';

/// Campo composto:
///   [imagem do captcha]  [🔄 recarregar]
///   [TextField "Digite o texto acima"]
///
/// Uso:
///   final ctrl = TextEditingController();
///   final key = GlobalKey<CaptchaFieldState>();
///   ...
///   CaptchaField(key: key, controller: ctrl)
///
/// Para saber o token atual: `key.currentState?.token`
/// Para recarregar após erro: `key.currentState?.reload()`
class CaptchaField extends StatefulWidget {
  final TextEditingController controller;

  /// Se true, mostra o campo mesmo enquanto o desafio ainda está sendo
  /// buscado (mostra um shimmer/loading). Padrão true.
  final bool autoLoadOnInit;

  const CaptchaField({
    super.key,
    required this.controller,
    this.autoLoadOnInit = true,
  });

  @override
  State<CaptchaField> createState() => CaptchaFieldState();
}

class CaptchaFieldState extends State<CaptchaField> {
  CaptchaChallenge? _challenge;
  bool _loading = false;
  Object? _error;

  /// Token atual do desafio, ou null se o captcha está desligado / não carregou.
  String? get token => _challenge?.token;

  /// True se o backend disse que o captcha está desligado — nesse caso a UI
  /// não precisa mostrar nada e o LoginPage pode pular a validação.
  bool get isDisabledByServer =>
      _challenge != null && !_challenge!.enabled;

  @override
  void initState() {
    super.initState();
    if (widget.autoLoadOnInit) {
      reload();
    }
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ch = await CaptchaService.fetchNew();
      if (!mounted) return;
      setState(() {
        _challenge = ch;
        _loading = false;
      });
      widget.controller.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Enquanto NÃO tivermos resposta do backend (primeira carga), não
    // ocupamos espaço nenhum na UI — isso evita o "flash" de um campo
    // com spinner que some 3s depois quando o backend responde
    // `enabled:false`. Só renderiza o widget quando temos certeza de que
    // o captcha está ativo.
    if (_challenge == null && _loading) {
      return const SizedBox.shrink();
    }
    if (isDisabledByServer) {
      // Backend desligou via env — não ocupa espaço na UI.
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _buildImageArea()),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Gerar outro captcha',
              onPressed: _loading ? null : reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.controller,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Digite o texto da imagem',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildImageArea() {
    const double imgHeight = 60;

    Widget content;
    if (_loading) {
      content = const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (_error != null) {
      content = const Center(
        child: Text(
          'Erro ao carregar captcha — toque no 🔄',
          style: TextStyle(fontSize: 12, color: Colors.red),
        ),
      );
    } else if (_challenge?.imageBytes != null) {
      content = Image.memory(
        _challenge!.imageBytes!,
        gaplessPlayback: true,
        fit: BoxFit.contain,
      );
    } else {
      content = const SizedBox.shrink();
    }

    return Container(
      height: imgHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: content,
    );
  }
}
