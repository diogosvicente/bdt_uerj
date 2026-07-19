import 'package:flutter/material.dart';

/// Tema global do app.
///
/// Centralizado aqui para que o `main.dart` fique enxuto (`theme:
/// AppTheme.light()`). Novas features devem preferir os tokens públicos
/// (`AppTheme.primary`, `AppTheme.success`, etc.) em vez de literais de
/// cor em cada widget.
///
/// Ver `docs/ARCHITECTURE.md` §4.12.
class AppTheme {
  AppTheme._();

  // ── Tokens ────────────────────────────────────────────────────────

  /// Azul institucional UERJ, usado no `AppNavbar` e em botões primários.
  static const Color primary = Color(0xFF0D47A1);

  /// Verde para status "OK" (online, ponto enviado).
  static const Color success = Color(0xFF2E7D32);

  /// Laranja para alertas "atenção" (fila crescendo).
  static const Color warning = Color(0xFFE65100);

  /// Vermelho para erros/estado crítico.
  static const Color danger = Color(0xFFC62828);

  // ── ThemeData ─────────────────────────────────────────────────────

  /// Tema claro padrão do app.
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: primary,
      // Bordas padrão para inputs (evita repetir OutlineInputBorder em todo
      // TextField do projeto).
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }
}
