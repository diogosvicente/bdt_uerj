import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../formatters/cpf_input_formatter.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/captcha_field.dart';

/// Sprint MSEC.8 (2026-07-28) — "Esqueci minha senha".
///
/// Route: `/esqueci-senha`.
///
/// # Escopo
///
/// A tela **só dispara o e-mail**. A troca da senha em si acontece no
/// navegador, pelo link que chega na caixa de entrada (mesmo fluxo e
/// mesmo token do web). Não replicamos a tela de redefinição aqui porque
/// isso espalharia regra sensível — validação/expiração/consumo do token
/// e política de senha — em dois lugares
/// ([[bdt_uerj_reusar_codigo_web]]). Como o link abre no navegador do
/// próprio celular, o condutor resolve tudo sem trocar de aparelho.
///
/// # Mensagem propositalmente vaga
///
/// O backend responde **a mesma coisa** exista ou não o CPF, pra não
/// permitir descobrir quais CPFs estão cadastrados. Por isso a tela
/// nunca afirma "e-mail enviado" — ela repete a frase condicional que
/// vem do backend ("Se este CPF estiver cadastrado…").
///
/// # Validação
///
/// Segue o padrão dos outros forms do app: `errorText` inline por campo
/// + banner `errorContainer` no topo pra erro de nível de form (rate
/// limit, falha de rede). O captcha reusa o `CaptchaField` do login.
class EsqueciSenhaPage extends StatefulWidget {
  const EsqueciSenhaPage({super.key});

  @override
  State<EsqueciSenhaPage> createState() => _EsqueciSenhaPageState();
}

class _EsqueciSenhaPageState extends State<EsqueciSenhaPage> {
  final _cpfCtrl = TextEditingController();
  final _captchaCtrl = TextEditingController();
  final _captchaKey = GlobalKey<CaptchaFieldState>();

  bool _enviando = false;
  String? _formError;
  String? _cpfError;

  /// Preenchido quando o backend confirma o disparo. Enquanto não for
  /// null, a tela mostra o estado "pronto" em vez do formulário.
  String? _mensagemSucesso;

  @override
  void dispose() {
    _cpfCtrl.dispose();
    _captchaCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_enviando) return;

    final cpf = _cpfCtrl.text.replaceAll(RegExp(r'\D'), '');

    setState(() {
      _formError = null;
      _cpfError = null;
    });

    if (cpf.isEmpty) {
      setState(() => _cpfError = 'Informe seu CPF.');
      return;
    }
    if (cpf.length != 11) {
      setState(() => _cpfError = 'O CPF deve ter 11 dígitos.');
      return;
    }

    // Captcha só é exigido se o backend disse que está ligado.
    final captchaState = _captchaKey.currentState;
    final captchaAtivo =
        captchaState != null && !captchaState.isDisabledByServer;
    if (captchaAtivo && _captchaCtrl.text.trim().isEmpty) {
      setState(() => _formError = 'Digite o texto do captcha.');
      return;
    }

    setState(() => _enviando = true);

    final r = await AuthService.esqueciSenha(
      cpf,
      captchaToken: captchaState?.token,
      captcha: captchaAtivo ? _captchaCtrl.text.trim() : null,
    );

    if (!mounted) return;
    setState(() => _enviando = false);

    if (r.ok) {
      setState(() {
        _mensagemSucesso = r.message?.trim().isNotEmpty == true
            ? r.message!
            : 'Se este CPF estiver cadastrado, enviamos um e-mail com o '
                'link para redefinir a senha.';
      });
      return;
    }

    // O state pode ter sido remontado durante o await.
    final captchaAtual = _captchaKey.currentState;

    if (r.captchaError) {
      captchaAtual?.showError(r.message);
      if (r.captchaReloadRequired) {
        _captchaCtrl.clear();
        captchaAtual?.reload();
      }
      return;
    }

    setState(() {
      _formError = r.message?.trim().isNotEmpty == true
          ? r.message!
          : 'Não foi possível enviar agora. Verifique a conexão e tente '
              'novamente.';
    });

    // Rate limit invalida o captcha atual no servidor — pede um novo pra
    // o condutor não digitar em cima de um desafio já queimado.
    if (r.throttled) {
      _captchaCtrl.clear();
      captchaAtual?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Esqueci minha senha')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: _mensagemSucesso != null ? _viewSucesso() : _viewForm(),
        ),
      ),
    );
  }

  Widget _viewForm() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Informe o CPF cadastrado. Enviaremos um e-mail com o link para '
          'criar uma senha nova.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        if (_formError != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: theme.colorScheme.errorContainer,
            ),
            child: Text(
              _formError!,
              style: TextStyle(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _cpfCtrl,
          keyboardType: TextInputType.number,
          enabled: !_enviando,
          // Mesma máscara do login — o condutor digita CPF nos dois
          // lugares, não faz sentido um aceitar formatado e o outro não.
          // O `_criar`/`_enviar` já limpa a pontuação antes de enviar.
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            CpfInputFormatter(),
          ],
          onChanged: (_) {
            if (_cpfError != null) setState(() => _cpfError = null);
          },
          decoration: InputDecoration(
            labelText: 'CPF',
            hintText: '000.000.000-00',
            prefixIcon: const Icon(Icons.badge_outlined),
            border: const OutlineInputBorder(),
            errorText: _cpfError,
          ),
        ),
        const SizedBox(height: 16),
        CaptchaField(key: _captchaKey, controller: _captchaCtrl),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _enviando ? null : _enviar,
          icon: _enviando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.mail_outline),
          label: const Text('Enviar link de redefinição'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _enviando ? null : () => Navigator.pop(context),
          child: const Text('Voltar ao login'),
        ),
      ],
    );
  }

  Widget _viewSucesso() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Icon(Icons.mark_email_read_outlined,
            size: 72, color: AppTheme.primary),
        const SizedBox(height: 16),
        Text(
          'Verifique seu e-mail',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _mensagemSucesso!,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: const Color(0xFFFFF3CD),
            border: Border.all(color: Colors.amber.shade700),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline,
                  size: 20, color: Colors.amber.shade900),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'O link abre no navegador do celular. Depois de criar a '
                  'senha nova, volte aqui e faça login.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
          child: const Text('Voltar ao login'),
        ),
        TextButton(
          onPressed: () {
            // Deixa tentar de novo (ex.: digitou o CPF errado). Volta ao
            // formulário com o campo preservado e um captcha novo.
            setState(() {
              _mensagemSucesso = null;
              _formError = null;
              _cpfError = null;
              _captchaCtrl.clear();
            });
            _captchaKey.currentState?.reload();
          },
          child: const Text('Tentar com outro CPF'),
        ),
      ],
    );
  }
}
