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
  final VoidCallback? onRefresh;
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
