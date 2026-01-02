import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/bdt_service.dart';
import '../models/bdt_resumo.dart';
import '../widgets/app_scaffold.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<BdtResumo>> future;

  @override
  void initState() {
    super.initState();
    future = BdtService.listarDoDia();
  }

  Future<void> _reload() async {
    setState(() => future = BdtService.listarDoDia());
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, "/login");
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      showBackButton: false,
      title: "BDT e-Prefeitura",
      subtitle: "Hoje",
      onRefresh: _reload,
      onLogout: _logout,
      body: FutureBuilder<List<BdtResumo>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const Center(child: Text("Nenhum BDT encontrado para hoje."));
          }

          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, i) {
              final b = items[i];
              return ListTile(
                title: Text(b.titulo),
                subtitle: Text(b.subtitulo),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pushNamed(context, "/bdt", arguments: b.id),
              );
            },
          );
        },
      ),
    );
  }
}
