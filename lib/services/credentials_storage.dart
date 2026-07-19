import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Armazenamento das credenciais salvas do login ("Lembrar senha").
///
/// - **CPF** fica em `SharedPreferences` — não é sensível.
/// - **Senha** fica em `flutter_secure_storage` — Android Keystore /
///   iOS Keychain. Não sobrevive a `adb backup`, e o SO garante isolamento
///   entre apps.
///
/// A primeira execução após atualizar o app migra a senha antiga
/// (que estava em SharedPreferences plaintext) automaticamente.
class CredentialsStorage {
  // Chaves em SharedPreferences (compatibilidade)
  static const _kFlagLembrar = 'login_lembrar_senha';
  static const _kFlagManterConectado = 'login_manter_conectado';
  static const _kCpfSalvo = 'login_cpf_salvo';
  // Chave antiga (SharedPreferences) — usada só para migração pra secure.
  static const _kSenhaSalvaLegacy = 'login_senha_salva';
  static const _kSenhaMigrada = 'login_senha_migrada_secure';

  // Chave em secure storage
  static const _kSenhaSalvaSecure = 'login_senha_salva_secure';

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ------------------ Flags ------------------

  static Future<bool> getLembrarSenha() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kFlagLembrar) ?? false;
  }

  static Future<bool> getManterConectado() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kFlagManterConectado) ?? false;
  }

  static Future<void> setFlags({
    required bool lembrarSenha,
    required bool manterConectado,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kFlagLembrar, lembrarSenha);
    await p.setBool(_kFlagManterConectado, manterConectado);
  }

  // ------------------ CPF ------------------

  static Future<String?> getCpf() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kCpfSalvo);
  }

  static Future<void> setCpf(String cpf) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCpfSalvo, cpf);
  }

  // ------------------ Senha ------------------
  //
  // Toda leitura de senha passa antes por _migrateLegacyIfNeeded() para
  // pegar quem já tinha "lembrar senha" ligado numa versão antiga do app.

  static Future<String?> getSenha() async {
    await _migrateLegacyIfNeeded();
    return _secure.read(key: _kSenhaSalvaSecure);
  }

  static Future<void> setSenha(String senha) async {
    await _secure.write(key: _kSenhaSalvaSecure, value: senha);
    // Se ainda houver a versão antiga em plaintext, apaga.
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSenhaSalvaLegacy);
    await p.setBool(_kSenhaMigrada, true);
  }

  // ------------------ Limpeza (quando usuário desmarca "Lembrar senha") ------------------

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kCpfSalvo);
    await p.remove(_kSenhaSalvaLegacy);
    await _secure.delete(key: _kSenhaSalvaSecure);
  }

  // ------------------ Migração transparente ------------------

  static Future<void> _migrateLegacyIfNeeded() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_kSenhaMigrada) == true) return;

    final legacy = p.getString(_kSenhaSalvaLegacy);
    if (legacy != null && legacy.isNotEmpty) {
      await _secure.write(key: _kSenhaSalvaSecure, value: legacy);
    }
    await p.remove(_kSenhaSalvaLegacy);
    await p.setBool(_kSenhaMigrada, true);
  }
}
