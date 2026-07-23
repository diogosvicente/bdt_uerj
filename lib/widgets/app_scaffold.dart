import 'package:flutter/material.dart';
import 'app_navbar.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    required this.title,
    required this.subtitle,
    this.onRefresh,
    this.onLogout,
    this.showBackButton = true,
    this.floatingActionButton,
  });

  final Widget body;
  final String title;
  final String subtitle;
  // Aceita função async para permitir feedback visual (spinner na navbar
  // enquanto o refresh está rodando). Callers síncronos podem passar
  // `() async { doStuff(); }`.
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLogout;
  final bool showBackButton;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppNavbar(
        title: title,
        subtitle: subtitle,
        onRefresh: onRefresh,
        onLogout: onLogout,
        showBackButton: showBackButton,
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}
