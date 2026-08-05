import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Log unificado usado pelo app.
///
/// Escreve com **`dart:developer.log`** (aparece no DevTools/logcat com o
/// nome como tag) E **`print`** (aparece no `flutter run`/logcat sem
/// filtro). Em release build também escreve — o app não tem um trace
/// remoto, então sem log persistente não dá pra diagnosticar.
///
/// **Uso:**
/// ```dart
/// class BdtService {
///   static const _log = Logger('BDT-SVC');
///
///   static Future<bool> foo() async {
///     _log.info('foo start');
///     // ...
///   }
/// }
/// ```
///
/// **Tags convencionadas** (ver `docs/ARCHITECTURE.md` §4.9):
/// - Services API: `AUTH-SVC`, `BDT-SVC`, `CAPTCHA-SVC`
/// - Services STORAGE: `CREDS-STORE`, `GPS-QUEUE`
/// - Services DOMAIN: `GPS-LIVE`, `OUTLIER-FILTER`
/// - Services PLATFORM: `BG-GPS`, `LOC-PERM`
class Logger {
  final String tag;
  const Logger(this.tag);

  /// Mensagem informativa (fluxo normal — start/success/estado).
  ///
  /// ⚠️ Escreve **em release também** (ver doc da classe). Nunca passe aqui
  /// nada derivado de payload de rede sem sanitizar — use [debug].
  void info(String msg) => _emit(msg);

  /// Diagnóstico que **só existe em debug**.
  ///
  /// Sprint 028 de segurança, item A7-mobile (2026-08-05). Existe porque o
  /// resto desta classe escreve em release de propósito — decisão correta
  /// para mensagens de fluxo, e errada para qualquer coisa derivada de
  /// tráfego: o `api_client` imprimia CPF, senha e tokens no logcat de
  /// aparelhos de produção.
  ///
  /// Note que **`debugPrint` não resolveria**: apesar do nome, ele não é
  /// removido em release — só estrangula a taxa de saída para não perder
  /// linhas. A guarda tem que ser `kDebugMode`, explícita.
  ///
  /// Mesmo em debug, sanitize antes: durante teste contra a base real são
  /// CPFs de pessoas de verdade. Use `PiiSanitizer` (`utils/pii_sanitizer.dart`).
  void debug(String msg) {
    if (kDebugMode) _emit(msg);
  }

  /// Condição inesperada mas recuperável (ex.: HTTP 4xx, cache miss).
  void warn(String msg) => _emit('WARN: $msg');

  /// Falha real (exceção). Em debug também loga stack curta.
  void error(String msg, [Object? e, StackTrace? st]) {
    _emit('ERROR: $msg${e == null ? "" : " | $e"}');
    if (st != null && kDebugMode) {
      _emit('  st: ${st.toString().split("\n").take(3).join(" | ")}');
    }
  }

  void _emit(String msg) {
    developer.log(msg, name: tag);
    // ignore: avoid_print
    print('[$tag] $msg');
  }
}
