import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache local da foto do condutor logado (Sprint MSEC.6).
///
/// Arquivo vive em `getApplicationDocumentsDirectory()` — **privado
/// ao app no Android**, não acessível por outros apps nem por adb sem
/// root. Não vai em SharedPreferences (grande) nem em external storage
/// (público). Metadados de cache (ETag + timestamp) vão em prefs
/// porque são pequenos e o tamanho não justifica secure_storage.
///
/// Categoria: STORAGE (`docs/ARCHITECTURE.md §4.4`) — nunca chama
/// HTTP; se precisar buscar do backend, é o `UsuarioFotoService`.
class UsuarioFotoStorage {
  /// Nome fixo (não usa ID do usuário) porque `clear()` no logout
  /// garante que a próxima sessão começa limpa. Um único condutor
  /// por instalação do app.
  static const String _fileName = 'usuario_foto.bin';

  static const String _kEtag      = 'usuario_foto_etag';
  static const String _kUpdatedAt = 'usuario_foto_updated_at_ms';
  static const String _kMime      = 'usuario_foto_mime';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Retorna o arquivo local da foto, ou `null` se não existe.
  /// **Não** valida TTL — quem decide se refetch é o `UsuarioFotoService`.
  static Future<File?> read() async {
    final f = await _file();
    return (await f.exists()) ? f : null;
  }

  /// Grava a foto nova. `etag` é o header `ETag` recebido do backend
  /// (para revalidação com `If-None-Match` na próxima chamada).
  static Future<void> write(
    Uint8List bytes, {
    String? etag,
    String? mime,
  }) async {
    final f = await _file();
    await f.writeAsBytes(bytes, flush: true);

    final prefs = await SharedPreferences.getInstance();
    if (etag != null && etag.isNotEmpty) {
      await prefs.setString(_kEtag, etag);
    }
    if (mime != null && mime.isNotEmpty) {
      await prefs.setString(_kMime, mime);
    }
    await prefs.setInt(_kUpdatedAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// ETag salvo — enviado no header `If-None-Match` da próxima
  /// requisição pra revalidar sem baixar de novo.
  static Future<String?> etag() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kEtag);
  }

  /// Marca "agora" como último check — usado quando o backend retorna
  /// 304 Not Modified (o arquivo continua igual, mas queremos resetar
  /// o TTL pra não bater no backend a cada segundo).
  static Future<void> touch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kUpdatedAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// Idade do cache. Se nunca gravou, retorna algo grande pra o
  /// service tratar como "expirado".
  static Future<Duration> age() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_kUpdatedAt) ?? 0;
    if (ms == 0) return const Duration(days: 999);
    return DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  /// Apaga TUDO — arquivo + metadados. Chamado no `AuthService.logout()`
  /// pra próximo condutor não ver foto do anterior.
  static Future<void> clear() async {
    final f = await _file();
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {
        // arquivo pode estar sendo lido pelo widget — tenta zerar
        try { await f.writeAsBytes(const []); } catch (_) {}
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEtag);
    await prefs.remove(_kUpdatedAt);
    await prefs.remove(_kMime);
  }
}
