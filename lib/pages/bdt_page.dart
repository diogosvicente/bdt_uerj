import 'package:flutter/material.dart';
import '../services/bdt_service.dart';
import '../services/gps_live_service.dart';
import '../widgets/app_scaffold.dart';

class BdtPage extends StatefulWidget {
  const BdtPage({super.key});

  @override
  State<BdtPage> createState() => _BdtPageState();
}

class _BdtPageState extends State<BdtPage> {
  bool busy = false;
  Map<String, dynamic>? payload;

  int? trackingAgendaId;
  int? trackingTrechoId;

  bool get isTracking => trackingAgendaId != null && trackingTrechoId != null;

  Future<void> _load(int bdtId) async {
    final res = await BdtService.detalhes(bdtId);

    if (!mounted) return;

    // ✅ mesmo erro (401/403/400) agora vem JSON; guardamos pra UI não travar
    setState(() => payload = res);

    // ✅ se existir trecho em andamento, liga o tracking automaticamente
    _syncTrackingFromPayload(bdtId);
  }

  void _syncTrackingFromPayload(int bdtId) {
    final ok = payload != null && payload!['success'] == true;
    if (!ok) {
      _stopTracking();
      return;
    }

    // ✅ opcional: se backend devolver trecho_em_andamento, usa direto
    final em = payload!['trecho_em_andamento'];
    if (em is Map) {
      final int aId = int.tryParse((em['agenda_id'] ?? 0).toString()) ?? 0;
      final int tId = int.tryParse((em['trecho_id'] ?? 0).toString()) ?? 0;

      if (aId > 0 && tId > 0) {
        // já está rastreando o mesmo?
        if (trackingAgendaId == aId && trackingTrechoId == tId) return;

        _startTracking(bdtId, aId, tId);
        return;
      }
    }

    // fallback: varre agendas/trechos
    final agendas = (payload!['agendas'] as List<dynamic>? ?? const []);
    for (final a in agendas) {
      final agenda = a as Map<String, dynamic>;
      final int agendaId = int.tryParse(agenda['fk_agenda'].toString()) ?? 0;

      final trechos = (agenda['trechos'] as List<dynamic>? ?? const []);
      for (final t in trechos) {
        final trecho = t as Map<String, dynamic>;
        final String status = (trecho['exec_status'] ?? 'pendente').toString();

        if (status == 'em_andamento') {
          final int trechoId = int.tryParse(trecho['id'].toString()) ?? 0;

          // já está rastreando o mesmo?
          if (trackingAgendaId == agendaId && trackingTrechoId == trechoId) return;

          _startTracking(bdtId, agendaId, trechoId);
          return;
        }
      }
    }

    // se não achou nenhum em andamento, garante que para
    _stopTracking();
  }

  void _startTracking(int bdtId, int agendaId, int trechoId) {
    // se já está rastreando esse mesmo, não faz nada
    if (trackingAgendaId == agendaId && trackingTrechoId == trechoId) return;

    // para qualquer tracking anterior
    _stopTracking();

    setState(() {
      trackingAgendaId = agendaId;
      trackingTrechoId = trechoId;
    });

    GpsLiveService.start(
      bdtId: bdtId,
      agendaId: agendaId,
      trechoId: trechoId,
      interval: const Duration(seconds: 5),
    );
  }

  void _stopTracking() {
    GpsLiveService.stop();

    if (trackingAgendaId != null || trackingTrechoId != null) {
      setState(() {
        trackingAgendaId = null;
        trackingTrechoId = null;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final int bdtId = ModalRoute.of(context)!.settings.arguments as int;
    _load(bdtId);
  }

  @override
  void dispose() {
    _stopTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int bdtId = ModalRoute.of(context)!.settings.arguments as int;

    final ok = payload != null && payload!['success'] == true;
    final bdt = ok ? (payload!['bdt'] as Map<String, dynamic>) : null;
    final agendas = ok ? (payload!['agendas'] as List<dynamic>) : const [];

    final titulo = bdt != null ? "BDT ${bdt['ano']}/${bdt['numero']}" : "BDT #$bdtId";
    final placa = (bdt != null && (bdt['placa'] ?? '').toString().isNotEmpty)
        ? (bdt['placa'] ?? '').toString()
        : null;

    final subtitle = placa != null ? "$titulo — $placa" : titulo;

    // ✅ se veio erro, mostra a mensagem
    if (payload != null && payload!['success'] != true) {
      final msg = (payload!['message'] ?? 'Erro ao carregar BDT.').toString();
      return AppScaffold(
        title: "BDT",
        subtitle: subtitle,
        onRefresh: () => _load(bdtId),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(msg, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => _load(bdtId),
                  child: const Text("Tentar novamente"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return AppScaffold(
      title: "BDT",
      subtitle: subtitle,
      onRefresh: () => _load(bdtId),
      body: (payload == null)
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: agendas.length,
              itemBuilder: (context, i) {
                final a = agendas[i] as Map<String, dynamic>;
                final int agendaId = int.tryParse(a['fk_agenda'].toString()) ?? 0;
                final trechos = (a['trechos'] as List<dynamic>? ?? []);

                return ExpansionTile(
                  title: Text("Agenda #$agendaId"),
                  subtitle: Text("${a['datahora_saida'] ?? ''} → ${a['datahora_retorno_previsto'] ?? ''}"),
                  children: trechos.map((t) {
                    final tt = t as Map<String, dynamic>;
                    final int trechoId = int.tryParse(tt['id'].toString()) ?? 0;
                    final String status = (tt['exec_status'] ?? 'pendente').toString();

                    final bool isTrackingThis =
                        (trackingAgendaId == agendaId && trackingTrechoId == trechoId);

                    Widget trailing;
                    if (busy) {
                      trailing = const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    } else if (status == 'em_andamento') {
                      trailing = TextButton(
                        onPressed: () async {
                          setState(() => busy = true);
                          final ok = await BdtService.finalizarTrecho(
                            bdtId: bdtId,
                            trechoId: trechoId,
                          );
                          if (!mounted) return;
                          setState(() => busy = false);

                          if (ok) _stopTracking();

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(ok ? "Trecho finalizado." : "Falha ao finalizar trecho.")),
                          );

                          await _load(bdtId);
                        },
                        child: const Text("Finalizar"),
                      );
                    } else if (status == 'pendente') {
                      trailing = TextButton(
                        onPressed: () async {
                          setState(() => busy = true);
                          final ok = await BdtService.iniciarTrecho(
                            bdtId: bdtId,
                            agendaId: agendaId,
                            trechoId: trechoId,
                          );
                          if (!mounted) return;
                          setState(() => busy = false);

                          if (ok) _startTracking(bdtId, agendaId, trechoId);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(ok ? "Trecho iniciado." : "Falha ao iniciar trecho.")),
                          );

                          await _load(bdtId);
                        },
                        child: const Text("Iniciar"),
                      );
                    } else {
                      trailing = const Icon(Icons.check_circle_outline);
                    }

                    return ListTile(
                      title: Text("${tt['origem'] ?? ''} → ${tt['destino'] ?? ''}"),
                      subtitle: Text(
                        isTrackingThis
                            ? "Status: $status • GPS: enviando..."
                            : "Status: $status",
                      ),
                      trailing: trailing,
                    );
                  }).toList(),
                );
              },
            ),
    );
  }
}
