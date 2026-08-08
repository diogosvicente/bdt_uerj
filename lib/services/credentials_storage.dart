import 'package:shared_preferences/shared_preferences.dart';

/// Armazenamento da preferência "Manter conectado" do login.
class CredentialsStorage {
  static const _kFlagManterConectado = 'login_manter_conectado';

  static Future<bool> getManterConectado() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kFlagManterConectado) ?? false;
  }

  static Future<void> setManterConectado(bool manterConectado) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kFlagManterConectado, manterConectado);
  }
}
