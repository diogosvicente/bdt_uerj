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
  void info(String msg) => _emit(msg);

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
