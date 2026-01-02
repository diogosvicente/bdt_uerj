import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

class AuthService {
  static Future<bool> login(String cpf, String senha) async {
    final res = await ApiClient.post(
      'transporte/api/login',
      {
        'cpf': cpf,
        'senha': senha,
      },
    );

    if (res == null) {
      print('Erro login: resposta nula (talvez status != 200)');
      return false;
    }

    print('Resposta login: $res');

    if (res['success'] != true) {
      print('Login falhou: ${res['message']}');
      return false;
    }

    final usuario = res['usuario'] as Map<String, dynamic>?;

    if (usuario == null) {
      print('Resposta sem campo "usuario"');
      return false;
    }

    final prefs = await SharedPreferences.getInstance();

    // token
    if (res['token'] != null) {
      await prefs.setString('token', res['token'].toString());
    }

    // id (pode vir int OU string)
    final dynamic rawId = usuario['id'];
    final int usuarioId = rawId is int
        ? rawId
        : int.tryParse(rawId.toString()) ?? 0;

    await prefs.setInt('usuario_id', usuarioId);

    // demais campos
    await prefs.setString('usuario_nome',  usuario['nome']?.toString()  ?? '');
    await prefs.setString('usuario_email', usuario['email']?.toString() ?? '');
    await prefs.setString('usuario_cpf',   usuario['cpf']?.toString()   ?? '');

    return true;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('usuario_id');
    await prefs.remove('usuario_nome');
    await prefs.remove('usuario_email');
    await prefs.remove('usuario_cpf');
  }
}
