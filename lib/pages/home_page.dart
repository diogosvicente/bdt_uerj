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
  DateTime selectedDate = DateTime.now();
  late Future<List<BdtResumo>> future;

  @override
  void initState() {
    super.initState();
    future = BdtService.listarDoDia(data: _apiDate(selectedDate));
  }

  String _apiDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return "${d.year}-${two(d.month)}-${two(d.day)}";
  }

  String _uiDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return "${two(d.day)}/${two(d.month)}/${d.year}";
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked == null) return;

    setState(() {
      selectedDate = picked;
      future = BdtService.listarDoDia(data: _apiDate(selectedDate));
    });
  }

  Future<void> _reload() async {
    setState(() => future = BdtService.listarDoDia(data: _apiDate(selectedDate)));
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
      subtitle: _uiDate(selectedDate),
      onRefresh: _reload,
      onLogout: _logout,
      body: FutureBuilder<List<BdtResumo>>(
        future: future,
        builder: (context, snap) {
          final loading = snap.connectionState != ConnectionState.done;

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
            children: [
              // seletor de data (enterprise)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.event),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Data do BDT", style: TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(_uiDate(selectedDate), style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_month),
                        label: const Text("Alterar"),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              if (loading)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                Builder(builder: (_) {
                  final items = snap.data ?? [];

                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text(
                          "Nenhum BDT encontrado para ${_uiDate(selectedDate)}.",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 0),
                      itemBuilder: (context, i) {
                        final b = items[i];
                        return ListTile(
                          title: Text(b.titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(b.subtitulo),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pushNamed(context, "/bdt", arguments: b.id),
                        );
                      },
                    ),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }
}
