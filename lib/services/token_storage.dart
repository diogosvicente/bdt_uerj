import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Armazenamento dos tokens de autenticação do usuário logado.
///
/// **Sprint MSEC.1 (2026-07-21)** — tokens saem de `SharedPreferences`
/// plaintext e passam pro `flutter_secure_storage` (Android Keystore /
/// iOS Keychain), mesmo padrão da senha.
///
/// **Sprint MSEC.4 (2026-07-21)** — passa a guardar dois tokens
/// separados:
///   - **access** (curto, ~15min) — enviado no header `Authorization`
///     em todo request. Quando expirar, o backend responde
///     `401 TOKEN_EXPIRED` e o `ApiClient` dispara `refresh`
///     automaticamente (transparente pra UI).
///   - **refresh** (longo, 24h ou 30d) — usado só pelo endpoint
///     `bdt/token/refresh` pra trocar por um novo par
///     (access+refresh rotacionado).
///
/// Categoria: STORAGE (`docs/ARCHITECTURE.md §4.4`).
class TokenStorage {
  // MSEC.1 — chave do access (era só 'token' antes)
  static const _kAccessSecure = 'auth_token_secure';
  // MSEC.4 — nova chave do refresh
  static const _kRefreshSecure = 'auth_refresh_secure';

  // Legacy — usada só pela migração 1x (SharedPreferences → secure)
  static const _kTokenLegacy = 'token';
  static const _kTokenMigrado = 'auth_token_migrado_secure';

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ── Access token ──────────────────────────────────────────────────

  /// Lê o access token atual. Migra automaticamente se ainda estiver
  /// no SharedPreferences antigo. Retorna `null` se não tem sessão.
  static Future<String?> readAccess() async {
    await _migrateLegacyIfNeeded();
    return _secure.read(key: _kAccessSecure);
  }

  static Future<void> writeAccess(String token) async {
    await _secure.write(key: _kAccessSecure, value: token);
    // limpa versão antiga em plaintext, se houver
    final p = await SharedPreferences.getInstance();
    await p.remove(_kTokenLegacy);
    await p.setBool(_kTokenMigrado, true);
  }

  // ── Refresh token ─────────────────────────────────────────────────

  /// Lê o refresh token. Retorna null se o app foi instalado ANTES da
  /// MSEC.4 (só tem access antigo) ou se está deslogado.
  static Future<String?> readRefresh() async {
    return _secure.read(key: _kRefreshSecure);
  }

  static Future<void> writeRefresh(String token) async {
    await _secure.write(key: _kRefreshSecure, value: token);
  }

  // ── Bulk ──────────────────────────────────────────────────────────

  /// Grava o par (access + refresh) — usado no login e no refresh.
  /// Um dos dois pode ser vazio (nunca deveria, mas defensivo).
  static Future<void> writePair({
    required String access,
    required String refresh,
  }) async {
    await writeAccess(access);
    if (refresh.isNotEmpty) await writeRefresh(refresh);
  }

  /// Apaga TUDO — access + refresh + chave legacy. Chamado no logout.
  static Future<void> clear() async {
    await _secure.delete(key: _kAccessSecure);
    await _secure.delete(key: _kRefreshSecure);
    final p = await SharedPreferences.getInstance();
    await p.remove(_kTokenLegacy);
    // `_kTokenMigrado` fica — migração 1x já rodou, não muda com logout.
  }

  // ── Legacy alias ──────────────────────────────────────────────────

  /// Alias pra `readAccess()`. Mantido pra código que ainda usa
  /// `TokenStorage.read()` da MSEC.1 (antes do refresh existir).
  @Deprecated('Use readAccess()')
  static Future<String?> read() => readAccess();

  /// Alias pra `writeAccess()`. Não guarda refresh — quem tem os dois
  /// deve usar `writePair()`.
  @Deprecated('Use writePair() com o par completo')
  static Future<void> write(String token) => writeAccess(token);

  // ── Migração transparente 1x ──────────────────────────────────────

  static Future<void> _migrateLegacyIfNeeded() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_kTokenMigrado) == true) return;

    final legacy = p.getString(_kTokenLegacy);
    if (legacy != null && legacy.isNotEmpty) {
      await _secure.write(key: _kAccessSecure, value: legacy);
    }
    await p.remove(_kTokenLegacy);
    await p.setBool(_kTokenMigrado, true);
  }
}
