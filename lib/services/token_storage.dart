import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Armazenamento do token de autenticação (Bearer) do usuário logado.
///
/// **Sprint MSEC.1 (2026-07-21)** — antes, o token vivia em
/// `SharedPreferences` plaintext. Se o device fosse rootado ou o
/// backup extraído, o token vazava e — como não expira até a MSEC.4 —
/// o abuso era indefinido. Agora vive em `flutter_secure_storage`
/// (Android Keystore / iOS Keychain), mesmo padrão da senha.
///
/// A primeira execução após atualizar o app migra o token antigo
/// (que estava em `SharedPreferences.getString('token')`)
/// automaticamente — o usuário nem percebe.
///
/// Categoria: STORAGE (`docs/ARCHITECTURE.md §4.4`). Nunca chama
/// HTTP; se precisar validar contra o backend, é o `AuthService`
/// que orquestra.
class TokenStorage {
  /// Chave em secure storage — não usa a mesma string 'token' antiga
  /// pra deixar óbvio que estamos num namespace diferente.
  static const _kTokenSecure = 'auth_token_secure';

  /// Chave ANTIGA em SharedPreferences — usada só pra migração.
  /// Depois de migrar, `_kTokenMigrado` = true e a leitura vai direto
  /// no secure_storage.
  static const _kTokenLegacy = 'token';
  static const _kTokenMigrado = 'auth_token_migrado_secure';

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Lê o token atual. Migra automaticamente se ainda estiver no
  /// SharedPreferences antigo. Retorna `null` se não tem token.
  static Future<String?> read() async {
    await _migrateLegacyIfNeeded();
    return _secure.read(key: _kTokenSecure);
  }

  /// Grava o token novo — chamado no login. Também remove qualquer
  /// resquício da versão antiga em plaintext (defesa em profundidade).
  static Future<void> write(String token) async {
    await _secure.write(key: _kTokenSecure, value: token);
    final p = await SharedPreferences.getInstance();
    await p.remove(_kTokenLegacy);
    await p.setBool(_kTokenMigrado, true);
  }

  /// Apaga o token — chamado no logout. Limpa AMBOS os locais (secure
  /// e o legacy) por segurança, mesmo se a migração nunca rodou.
  static Future<void> clear() async {
    await _secure.delete(key: _kTokenSecure);
    final p = await SharedPreferences.getInstance();
    await p.remove(_kTokenLegacy);
    // O `_kTokenMigrado` fica — é flag de "migração 1x já rodou",
    // não muda com logout.
  }

  static Future<void> _migrateLegacyIfNeeded() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_kTokenMigrado) == true) return;

    final legacy = p.getString(_kTokenLegacy);
    if (legacy != null && legacy.isNotEmpty) {
      await _secure.write(key: _kTokenSecure, value: legacy);
    }
    await p.remove(_kTokenLegacy);
    await p.setBool(_kTokenMigrado, true);
  }
}
