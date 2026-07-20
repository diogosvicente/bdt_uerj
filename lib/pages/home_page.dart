import 'dart:async';

import 'package:flutter/material.dart';
import '../models/bdt_resumo.dart';
import '../models/pre_bdt_pendente.dart';
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

  /// Trava para não abrir o diálogo de confirmação de veículo em loop
  /// (o `build` roda várias vezes conforme o `FutureBuilder` resolve).
  /// É resetada quando a data muda — assim se o condutor voltar de `/bdt`
  /// e trocar a data, o auto-abrir volta a valer.
  bool _autoOpenTentado = false;

  /// True enquanto um `_reload` está no ar. Serve para suprimir o
  /// `_maybeAutoOpen` durante o refresh — abrir um AlertDialog enquanto
  /// o refresh ainda está no ar trava a animação em alguns Androids.
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    future = BdtService.listarDoDia(data: _apiDate(selectedDate));
    futurePendentes = BdtService.listarMeusPreBdtsPendentes();
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

  /// Recarrega a lista de BDTs do dia selecionado E a lista de Pré-BDTs
  /// pendentes do usuário. Ambas rolam em paralelo — o FutureBuilder de
  /// cada seção reage independente, então o card que voltar primeiro já
  /// aparece atualizado.
  Future<void> _reload() async {
    // Suprime o auto-open enquanto o refresh está no ar (evita AlertDialog
    // aparecer sobre a mensagem de "atualizada").
    _refreshing = true;
    // Marca como "já tentado" para o build atual não abrir dialog no
    // mesmo tick; será liberado no final quando limparmos _refreshing.
    _autoOpenTentado = true;

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
    } finally {
      // Fim do refresh: libera o auto-open pra próxima carga (se o usuário
      // trocar de data ou apertar 🔄 de novo).
      _refreshing = false;
      _autoOpenTentado = false;
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
    if (_refreshing) return; // não intromete durante refresh
    if (!_isHoje(selectedDate)) return;

    _autoOpenTentado = true;
    // Precisa esperar o frame terminar para não abrir dialog dentro do build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _refreshing) return;
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

  Future<void> _abrirPreBdtForm() async {
    // Quando volta do form (com Pré-BDT criado ou cancelado), recarrega
    // a lista de pendentes — é a forma mais direta de mostrar o recém-
    // criado sem exigir toque manual no 🔄.
    final result = await Navigator.pushNamed(context, '/pre_bdt/novo');
    if (!mounted) return;
    _autoOpenTentado = true; // evita auto-open acidental logo depois

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
    _autoOpenTentado = true; // evita auto-open acidental logo depois
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

        // Sprint M1 — auto-abrir BDT único (só hoje).
        if (!loading && items.length == 1) {
          _maybeAutoOpen(items.first);
        }

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
