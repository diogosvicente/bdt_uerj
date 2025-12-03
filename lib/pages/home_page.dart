import 'package:flutter/material.dart';
import '../services/bdt_service.dart';
import '../services/auth_service.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _abrirBdt(BuildContext context) async {
    final bdtId = await BdtService.abrirBDT();

    if (!context.mounted) return;

    if (bdtId != null) {
      Navigator.pushNamed(context, "/bdt", arguments: bdtId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Não foi possível abrir o BDT do dia."),
        ),
      );
    }
  }

  Future<void> _logout(BuildContext context) async {
    await AuthService.logout();
    if (!context.mounted) return;
    Navigator.pushReplacementNamed(context, "/login");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("BDT UERJ"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () => _abrirBdt(context),
          child: const Text("Abrir BDT do Dia"),
        ),
      ),
    );
  }
}
