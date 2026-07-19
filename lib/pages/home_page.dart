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

  /// Trava para não abrir o diálogo de confirmação de veículo em loop
  /// (o `build` roda várias vezes conforme o `FutureBuilder` resolve).
  /// É resetada quando a data muda ou o refresh é acionado — assim se o
  /// condutor voltar de `/bdt` e trocar a data, o auto-abrir volta a valer.
  bool _autoOpenTentado = false;

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

  bool _isHoje(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
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
      _autoOpenTentado = false; // nova data → volta a valer o auto-abrir
    });
  }

  /// Recarrega a lista de BDTs do dia selecionado.
  Future<void> _reload() async {
    _autoOpenTentado = false; // usuário pediu refresh → auto-abrir volta a valer
    final novo = BdtService.listarDoDia(data: _apiDate(selectedDate));
    setState(() => future = novo);
    try {
      final lista = await novo;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              lista.isEmpty
                  ? 'Nenhum BDT para ${_uiDate(selectedDate)}.'
                  : 'Lista atualizada (${lista.length} BDT${lista.length > 1 ? "s" : ""}).',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('Falha ao atualizar: $e')),
        );
    }
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, "/login");
  }

  /// Sprint M1 — abertura direta do BDT:
  /// se hoje e o condutor tem exatamente 1 BDT, mostra um diálogo de
  /// confirmação de veículo (placa + marca/modelo) antes de navegar.
  /// Se ele "Cancelar", cai na lista normalmente.
  void _maybeAutoOpen(BdtResumo unico) {
    if (_autoOpenTentado) return;
    if (!_isHoje(selectedDate)) return;

    _autoOpenTentado = true;
    // Precisa esperar o frame terminar para não abrir dialog dentro do build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _abrirConfirmacaoVeiculo(unico);
    });
  }

  Future<void> _abrirConfirmacaoVeiculo(BdtResumo bdt) async {
    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Confirmar veículo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Você tem apenas um BDT hoje. Confirme o veículo antes de abrir:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              _linhaVeiculo(icone: Icons.confirmation_number, label: 'Placa', valor: bdt.placa),
              _linhaVeiculo(icone: Icons.directions_car, label: 'Marca', valor: bdt.marcaNome ?? '—'),
              _linhaVeiculo(icone: Icons.category, label: 'Modelo', valor: bdt.modeloNome ?? '—'),
              const SizedBox(height: 10),
              Text(
                bdt.titulo,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Escolher outro'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar e abrir'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (confirmar == true) {
      Navigator.pushNamed(context, '/bdt', arguments: bdt.id);
    }
    // Se recusar, fica na lista — o auto-open não repete nesta carga.
  }

  Widget _linhaVeiculo({required IconData icone, required String label, required String valor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icone, size: 18, color: Colors.black54),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          Expanded(
            child: Text(
              valor.trim().isEmpty ? '—' : valor,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
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
          final items = snap.data ?? const <BdtResumo>[];

          // Sprint M1 — auto-abrir BDT único (só hoje).
          if (!loading && items.length == 1) {
            _maybeAutoOpen(items.first);
          }

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
              else if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(
                      "Nenhum BDT encontrado para ${_uiDate(selectedDate)}.",
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                Card(
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
                ),
            ],
          );
        },
      ),
    );
  }
}
