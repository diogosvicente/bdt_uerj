import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/credentials_storage.dart';
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
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
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
    super.dispose();
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
    );

    if (!mounted) return;

    if (result.ok) {
      await _persistPreferences();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, "/home");
      return;
    }

    setState(() => loading = false);

    // Se o backend disse que o captcha reciclou, atualiza a imagem.
    if (result.captchaReloadRequired) {
      captchaController.clear();
      // ignore: discarded_futures
      captchaState?.reload();
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
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: SingleChildScrollView(
              child: loading
                  ? const Loading(text: "Entrando no BDT UERJ...")
                  : Column(
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

                        ElevatedButton(
                          onPressed: _doLogin,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                          ),
                          child: const Text("Entrar"),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
