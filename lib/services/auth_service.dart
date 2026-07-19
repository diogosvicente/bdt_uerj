import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

/// Resultado do login. Precisamos distinguir os casos para que a UI possa,
/// por exemplo, recarregar o captcha se ele falhar.
class LoginResult {
  final bool ok;
  final String? message;
  final bool captchaError;
  final bool captchaReloadRequired;

  const LoginResult._({
    required this.ok,
    this.message,
    this.captchaError = false,
    this.captchaReloadRequired = false,
  });

  factory LoginResult.success() => const LoginResult._(ok: true);
  factory LoginResult.failure(String? msg) =>
      LoginResult._(ok: false, message: msg);
  factory LoginResult.captchaFailure(String? msg, {required bool reload}) =>
      LoginResult._(
        ok: false,
        message: msg,
        captchaError: true,
        captchaReloadRequired: reload,
      );
}

class AuthService {
  /// Executa o login. Se o backend estiver com captcha habilitado,
  /// [captchaToken] e [captcha] são obrigatórios.
  static Future<LoginResult> login(
    String cpf,
    String senha, {
    String? captchaToken,
    String? captcha,
  }) async {
    final payload = <String, dynamic>{
      'cpf': cpf,
      'senha': senha,
      if (captchaToken != null && captchaToken.isNotEmpty)
        'captcha_token': captchaToken,
      if (captcha != null && captcha.isNotEmpty) 'captcha': captcha,
    };

    final res = await ApiClient.post('transporte/api/login', payload);

    if (res['success'] != true) {
      final status = (res['status'] ?? '').toString();
      final msg = res['message']?.toString();

      if (status == 'CAPTCHA_ERROR') {
        return LoginResult.captchaFailure(
          msg,
          reload: res['captcha_reload'] == true,
        );
      }
      return LoginResult.failure(msg);
    }

    final usuario = res['usuario'] as Map<String, dynamic>?;
    if (usuario == null) {
      return LoginResult.failure('Resposta sem dados do usuário.');
    }

    final prefs = await SharedPreferences.getInstance();

    if (res['token'] != null) {
      await prefs.setString('token', res['token'].toString());
    }

    final dynamic rawId = usuario['id'];
    final int usuarioId = rawId is int
        ? rawId
        : int.tryParse(rawId.toString()) ?? 0;
    await prefs.setInt('usuario_id', usuarioId);

    await prefs.setString('usuario_nome', usuario['nome']?.toString() ?? '');
    await prefs.setString('usuario_email', usuario['email']?.toString() ?? '');
    await prefs.setString('usuario_cpf', usuario['cpf']?.toString() ?? '');

    return LoginResult.success();
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('usuario_id');
    await prefs.remove('usuario_nome');
    await prefs.remove('usuario_email');
    await prefs.remove('usuario_cpf');

    // Desliga "manter conectado" — senão, ao voltar pra tela de login,
    // o auto-redirect da LoginPage tenta reautenticar sem token e o
    // usuário fica preso num loop. As credenciais salvas ("lembrar senha")
    // NÃO são apagadas: o usuário provavelmente vai querer entrar de novo
    // com o mesmo CPF/senha.
    await prefs.remove('login_manter_conectado');
  }
}
