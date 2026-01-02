import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../widgets/loading.dart';
import '../formatters/cpf_input_formatter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final cpfController = TextEditingController();
  final senhaController = TextEditingController();
  bool loading = false;

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

    setState(() => loading = true);

    final ok = await AuthService.login(
      rawCpf,      // passa CPF sem máscara
      senha,
    );

    setState(() => loading = false);

    if (!mounted) return;

    if (ok) {
      Navigator.pushReplacementNamed(context, "/home");
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("CPF ou senha inválidos."),
        ),
      );
    }
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

                        // CAMPO SENHA
                        TextField(
                          controller: senhaController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: "Senha",
                            border: OutlineInputBorder(),
                          ),
                        ),

                        const SizedBox(height: 24),

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
