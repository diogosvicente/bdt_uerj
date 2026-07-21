import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/credentials_storage.dart';
import '../services/token_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/loading.dart';
import '../widgets/captcha_field.dart';
import '../formatters/cpf_input_formatter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final cpfController = TextEditingController();
  final senhaController = TextEditingController();
  final captchaController = TextEditingController();

  // Chave para acessar o CaptchaField (token atual, reload após erro).
  final _captchaKey = GlobalKey<CaptchaFieldState>();

  bool loading = false;
  bool _obscurePassword = true;
  bool _lembrarSenha = false;
  bool _manterConectado = false;

  /// Evita processar 2× (initState + didChangeDependencies).
  bool _bootstrapped = false;

  /// MSEC.3 — segundos restantes até o rate-limit do backend expirar.
  /// > 0 = botão "Entrar" desabilitado + banner com contagem regressiva.
  /// Zerado = botão liberado, banner some. `_throttleTimer` faz o
  /// decremento a cada 1s.
  int _throttleSecondsLeft = 0;
  Timer? _throttleTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;
    _bootstrap();
  }

  /// Carrega preferências salvas. Se "manter conectado" estiver ligado E
  /// houver token, valida o token contra o backend e vai direto pra /home
  /// sem mostrar a tela.
  Future<void> _bootstrap() async {
    _lembrarSenha = await CredentialsStorage.getLembrarSenha();
    _manterConectado = await CredentialsStorage.getManterConectado();

    if (_lembrarSenha) {
      cpfController.text = (await CredentialsStorage.getCpf()) ?? '';
      senhaController.text = (await CredentialsStorage.getSenha()) ?? '';
    }

    if (_manterConectado) {
      // MSEC.1 — token lido do secure storage, não mais SharedPreferences.
      final token = await TokenStorage.read();
      if (token != null && token.isNotEmpty) {
        // Valida o token contra o backend antes de auto-logar.
        // Se estiver expirado/inválido, cai pra tela de login normal.
        final ok = await AuthService.verifyToken();
        if (!mounted) return;
        if (ok) {
          Navigator.pushReplacementNamed(context, '/home');
          return;
        }
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> _persistPreferences() async {
    await CredentialsStorage.setFlags(
      lembrarSenha: _lembrarSenha,
      manterConectado: _manterConectado,
    );

    if (_lembrarSenha) {
      // grava CPF sem máscara para reduzir ambiguidade
      final rawCpf = cpfController.text.replaceAll(RegExp(r'\D'), '');
      await CredentialsStorage.setCpf(rawCpf);
      await CredentialsStorage.setSenha(senhaController.text);
    } else {
      await CredentialsStorage.clear();
    }
  }

  @override
  void dispose() {
    cpfController.dispose();
    senhaController.dispose();
    captchaController.dispose();
    _throttleTimer?.cancel();
    super.dispose();
  }

  /// MSEC.3 — inicia a contagem regressiva do rate-limit. Cancela
  /// timer anterior (se houver), seta o contador, e agenda tick 1s.
  /// Ao zerar, timer pára e botão libera.
  void _iniciarThrottle(int segundos, String? mensagemBackend) {
    _throttleTimer?.cancel();
    setState(() => _throttleSecondsLeft = segundos > 0 ? segundos : 60);

    _throttleTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_throttleSecondsLeft > 0) _throttleSecondsLeft--;
        if (_throttleSecondsLeft == 0) {
          t.cancel();
          _throttleTimer = null;
        }
      });
    });

    // Feedback imediato — snackbar breve, o banner permanente cuida
    // do resto (contagem regressiva).
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            (mensagemBackend ?? '').trim().isNotEmpty
                ? mensagemBackend!
                : 'Muitas tentativas de login. Aguarde um momento.',
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
  }

  Future<void> _doLogin() async {
    // remove máscara (deixa só números)
    final rawCpf = cpfController.text.replaceAll(RegExp(r'\D'), '');
    final senha = senhaController.text;

    // validação básica antes de chamar a API
    if (rawCpf.length != 11 || senha.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Informe um CPF válido (11 dígitos) e a senha."),
        ),
      );
      return;
    }

    // captcha: só valida se o backend estiver com o desafio ativo
    final captchaState = _captchaKey.currentState;
    final captchaAtivo = captchaState != null && !captchaState.isDisabledByServer;

    if (captchaAtivo && captchaController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Digite o texto do captcha."),
        ),
      );
      return;
    }

    setState(() => loading = true);

    final result = await AuthService.login(
      rawCpf,
      senha,
      captchaToken: captchaState?.token,
      captcha: captchaAtivo ? captchaController.text.trim() : null,
      // MSEC.4 — se marcou "Manter conectado", refresh token dura 30d;
      // caso contrário 24h. O access sempre é 15min e roda no ApiClient.
      manterConectado: _manterConectado,
    );

    if (!mounted) return;

    if (result.ok) {
      await _persistPreferences();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, "/home");
      return;
    }

    setState(() => loading = false);

    // Reobtém o state atual pelo GlobalKey — a referência antiga capturada
    // antes do await pode estar defunct se o CaptchaField foi remontado.
    final captchaStateAtual = _captchaKey.currentState;

    if (result.throttled) {
      // MSEC.3 — backend disse 429. Inicia countdown que bloqueia o
      // botão "Entrar" até zerar. Snackbar longo (não vai sumir sozinho
      // — o timer decide) com contagem regressiva.
      _iniciarThrottle(result.retryAfterSeconds, result.message);
      return;
    }

    if (result.captchaError) {
      // Backend rejeitou o captcha: o banner de erro dentro do
      // CaptchaField já é destacado (borda vermelha, ícone e título),
      // então não usa snackbar aqui — seria redundante e pior de ler.
      // Se o backend descartou o token (captchaReloadRequired), pedimos
      // um novo desafio ANTES de mostrar a mensagem final — assim o
      // aviso é mais preciso ("uma nova imagem já foi carregada").
      final novaImagem = result.captchaReloadRequired;
      if (novaImagem) {
        captchaController.clear();
        // ignore: discarded_futures
        captchaStateAtual?.reload();
      }
      final base = (result.message ?? '').trim().isEmpty
          ? 'Confira as letras/números da imagem e tente novamente.'
          : result.message!.trim();
      final msgFinal = novaImagem
          ? '$base Uma nova imagem foi carregada.'
          : base;
      captchaStateAtual?.showError(msgFinal);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.message ?? 'CPF ou senha inválidos.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // NÃO removemos o formulário da árvore durante o loading — se ele
    // sai, o CaptchaField é disposado e o GlobalKey capturado antes do
    // await fica defunct (crash "setState after dispose"). Em vez disso,
    // deixamos o form sempre montado, com opacidade e bloqueio de
    // toque, e sobrepomos um Loading centralizado. Assim o state do
    // captcha sobrevive à resposta de erro do backend e permite marcar
    // o campo em vermelho.
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: SingleChildScrollView(
                  child: AbsorbPointer(
                    absorbing: loading,
                    child: Opacity(
                      opacity: loading ? 0.4 : 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                        // LOGO DO E-PREFEITURA
                        Center(
                          child: Image.asset(
                            "assets/images/logomarca-uerj.png",
                            height: 120,
                          ),
                        ),

                        const SizedBox(height: 20),

                        const Text(
                          "BDT UERJ",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 6),

                        const Text(
                          "Módulo de Transporte — e-Prefeitura UERJ",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),

                        const SizedBox(height: 40),

                        // CAMPO CPF
                        TextField(
                          controller: cpfController,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                            CpfInputFormatter(),
                          ],
                          decoration: const InputDecoration(
                            labelText: "CPF",
                            hintText: "000.000.000-00",
                            border: OutlineInputBorder(),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // CAMPO SENHA (com ícone de mostrar/esconder)
                        TextField(
                          controller: senhaController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: "Senha",
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? "Mostrar senha"
                                  : "Ocultar senha",
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // CAPTCHA (some sozinho se backend desligar via env)
                        CaptchaField(
                          key: _captchaKey,
                          controller: captchaController,
                        ),

                        const SizedBox(height: 8),

                        // OPÇÕES: lembrar senha + manter conectado
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CheckboxListTile(
                              value: _lembrarSenha,
                              onChanged: (v) => setState(
                                () => _lembrarSenha = v ?? false,
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: const Text("Lembrar senha"),
                              subtitle: const Text(
                                "Preenche CPF e senha automaticamente na próxima vez.",
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            CheckboxListTile(
                              value: _manterConectado,
                              onChanged: (v) => setState(
                                () => _manterConectado = v ?? false,
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: const Text("Manter conectado"),
                              subtitle: const Text(
                                "Pula esta tela ao abrir o app se você já tiver logado.",
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        if (_throttleSecondsLeft > 0) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withValues(alpha: 0.08),
                              border: Border.all(
                                  color: AppTheme.danger, width: 1.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.timer_outlined,
                                    color: AppTheme.danger, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Muitas tentativas. Aguarde '
                                    '${_throttleSecondsLeft}s antes de tentar novamente.',
                                    style: const TextStyle(
                                      color: AppTheme.danger,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        ElevatedButton(
                          // MSEC.3 — botão bloqueia enquanto rate-limit
                          // do backend não zerar. Timer decrementa
                          // `_throttleSecondsLeft` a cada 1s.
                          onPressed: _throttleSecondsLeft > 0 ? null : _doLogin,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                          ),
                          child: Text(
                            _throttleSecondsLeft > 0
                                ? 'Aguarde ${_throttleSecondsLeft}s'
                                : 'Entrar',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (loading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x11000000),
                child: Center(child: Loading(text: "Entrando no BDT UERJ...")),
              ),
            ),
        ],
      ),
    ),
    );
  }
}
