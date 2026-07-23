import 'dart:async';

import 'package:flutter/material.dart';
import '../models/bdt_resumo.dart';
import '../models/pre_bdt_pendente.dart';
import '../services/alertas_service.dart';
import '../services/auth_service.dart';
import '../services/bdt_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DateTime selectedDate = DateTime.now();
  late Future<List<BdtResumo>> future;
  late Future<List<PreBdtPendente>> futurePendentes;

  @override
  void initState() {
    super.initState();
    future = BdtService.listarDoDia(data: _apiDate(selectedDate));
    futurePendentes = BdtService.listarMeusPreBdtsPendentes();

    // Sprint M5 — assim que a lista do dia terminar de carregar (sem
    // esperar refresh manual), agenda os alertas 1h/30min antes de
    // cada BDT com hora prevista futura.
    future.then((bdts) {
      if (!mounted) return;
      // fire-and-forget — falha aqui não bloqueia o app.
      // ignore: discarded_futures
      AlertasService.sincronizarComBdtsDoDia(bdts);
    });
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

  /// Recarrega a lista de BDTs do dia selecionado E a lista de Pré-BDTs
  /// pendentes do usuário. Ambas rolam em paralelo — o FutureBuilder de
  /// cada seção reage independente, então o card que voltar primeiro já
  /// aparece atualizado.
  Future<void> _reload() async {
    final novo = BdtService.listarDoDia(data: _apiDate(selectedDate));
    final novosPendentes = BdtService.listarMeusPreBdtsPendentes();
    setState(() {
      future = novo;
      futurePendentes = novosPendentes;
    });

    // Timeout defensivo: se o ApiClient.post travar antes do próprio
    // timeout dele (10s), garantimos que o snackbar de "demorou" cai em
    // ≤15s. Aguardamos as duas futuras juntas para o feedback ser único.
    try {
      final results = await Future.wait<Object>([
        novo,
        novosPendentes,
      ]).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final lista = results[0] as List<BdtResumo>;
      final pendentes = results[1] as List<PreBdtPendente>;

      // Re-sincroniza os alertas com a lista fresca — se o admin mudou
      // horário/reagendou/removeu BDT, isso corrige o schedule.
      // ignore: discarded_futures
      AlertasService.sincronizarComBdtsDoDia(lista);

      final partes = <String>[
        lista.isEmpty
            ? 'nenhum BDT em ${_uiDate(selectedDate)}'
            : '${lista.length} BDT${lista.length > 1 ? "s" : ""}',
        if (pendentes.isNotEmpty)
          '${pendentes.length} Pré-BDT${pendentes.length > 1 ? "s" : ""} pendente${pendentes.length > 1 ? "s" : ""}',
      ];
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Atualizado — ${partes.join(", ")}.'),
            duration: const Duration(seconds: 2),
          ),
        );
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('A resposta demorou demais. Verifique a conexão e tente novamente.'),
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

  Future<void> _abrirPreBdtForm() async {
    // Quando volta do form (com Pré-BDT criado ou cancelado), recarrega
    // a lista de pendentes — é a forma mais direta de mostrar o recém-
    // criado sem exigir toque manual no 🔄.
    final result = await Navigator.pushNamed(context, '/pre_bdt/novo');
    if (!mounted) return;
    if (result == true) {
      setState(() {
        futurePendentes = BdtService.listarMeusPreBdtsPendentes();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      showBackButton: false,
      title: "BDT e-Prefeitura",
      subtitle: _uiDate(selectedDate),
      onRefresh: _reload,
      onLogout: _logout,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirPreBdtForm,
        icon: const Icon(Icons.rocket_launch_outlined),
        label: const Text('Novo Pré-BDT'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
        children: [
          _cardData(),
          const SizedBox(height: 10),
          _secaoPendentes(),
          const SizedBox(height: 10),
          _secaoBdtsDoDia(),
          const SizedBox(height: 10),
          _cardFerramentas(),
        ],
      ),
    );
  }

  /// Card compacto de atalhos institucionais que não dependem de um BDT
  /// específico. Hoje só o histórico de ocorrências; a ideia é que
  /// abastecimento livre e manutenção livre (fora do BDT) entrem aqui
  /// no futuro, sem poluir a AppBar / o menu do avatar.
  Widget _cardFerramentas() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: const [
                Icon(Icons.apps, size: 18, color: Colors.black54),
                SizedBox(width: 8),
                Text(
                  'Ferramentas',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.3,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFFFF3CD),
              foregroundColor: Color(0xFF856404),
              child: Icon(Icons.warning_amber_rounded),
            ),
            title: const Text(
              'Histórico de ocorrências',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Ocorrências registradas no sistema (todos os veículos)',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.black38),
            onTap: () => Navigator.pushNamed(
              context,
              '/ocorrencias/historico',
            ),
          ),
        ],
      ),
    );
  }

  // ─── seções ────────────────────────────────────────────────────────

  Widget _cardData() {
    return Card(
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
    );
  }

  /// Pré-BDTs criados por mim que ainda estão pendentes. Some quando não
  /// tem nenhum — sem "estado vazio" chamativo, pra não poluir a home de
  /// quem nunca criou Pré-BDT.
  Widget _secaoPendentes() {
    return FutureBuilder<List<PreBdtPendente>>(
      future: futurePendentes,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final items = snap.data ?? const <PreBdtPendente>[];

        if (loading) {
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            ),
          );
        }

        if (items.isEmpty) {
          return const SizedBox.shrink();
        }

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_top, color: AppTheme.warning),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Meus Pré-BDTs aguardando aprovação',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${items.length}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 8),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 0),
                itemBuilder: (context, i) => _tilePendente(items[i]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tilePendente(PreBdtPendente p) {
    final trechosLabel = p.trechos.isEmpty
        ? 'Sem trechos previstos'
        : p.trechos.map((t) => '${t.origem} → ${t.destino}').join(' · ');

    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Color(0x22F59E0B),
        child: Icon(Icons.pending_actions, color: AppTheme.warning),
      ),
      title: Text(
        p.protocolo.isNotEmpty ? p.protocolo : p.titulo,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.veiculoLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            trechosLabel,
            style: const TextStyle(fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: const Icon(Icons.edit_outlined),
      isThreeLine: true,
      onTap: () => _abrirEdicaoPreBdt(p.id),
    );
  }

  Future<void> _abrirEdicaoPreBdt(int bdtId) async {
    final result = await Navigator.pushNamed(
      context,
      '/pre_bdt/editar',
      arguments: bdtId,
    );
    if (!mounted) return;
    if (result == true) {
      setState(() {
        futurePendentes = BdtService.listarMeusPreBdtsPendentes();
      });
    }
  }

  Widget _secaoBdtsDoDia() {
    return FutureBuilder<List<BdtResumo>>(
      future: future,
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final items = snap.data ?? const <BdtResumo>[];

        if (loading) {
          return const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 14, 14, 6),
                child: Row(
                  children: [
                    Icon(Icons.assignment_turned_in_outlined),
                    SizedBox(width: 8),
                    Text(
                      'BDTs do dia',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const Divider(height: 8),
              ListView.separated(
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
            ],
          ),
        );
      },
    );
  }
}
