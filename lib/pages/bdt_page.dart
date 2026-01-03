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
  Map<String, dynamic>? payload;

  // ✅ busy só no trecho clicado
  int? busyTrechoId;

  int? trackingAgendaId;
  int? trackingTrechoId;

  bool get isTracking => trackingAgendaId != null && trackingTrechoId != null;

  Future<void> _load(int bdtId) async {
    final res = await BdtService.detalhes(bdtId);

    if (!mounted) return;

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

    // ✅ se backend devolver trecho_em_andamento, usa direto
    final em = payload!['trecho_em_andamento'];
    if (em is Map) {
      final int aId = int.tryParse((em['agenda_id'] ?? 0).toString()) ?? 0;
      final int tId = int.tryParse((em['trecho_id'] ?? 0).toString()) ?? 0;

      if (aId > 0 && tId > 0) {
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

          if (trackingAgendaId == agendaId && trackingTrechoId == trechoId) return;
          _startTracking(bdtId, agendaId, trechoId);
          return;
        }
      }
    }

    _stopTracking();
  }

  void _startTracking(int bdtId, int agendaId, int trechoId) {
    if (trackingAgendaId == agendaId && trackingTrechoId == trechoId) return;

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

  // =========================
  // UI helpers (enterprise)
  // =========================

  String _statusLabel(String s) {
    switch (s) {
      case 'em_andamento':
        return 'Em andamento';
      case 'finalizado':
      case 'concluido':
        return 'Finalizado';
      default:
        return 'Pendente';
    }
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'em_andamento':
        return Icons.play_circle_outline;
      case 'finalizado':
      case 'concluido':
        return Icons.check_circle_outline;
      default:
        return Icons.timelapse;
    }
  }

  Color? _chipBg(BuildContext context, String s) {
    final cs = Theme.of(context).colorScheme;
    switch (s) {
      case 'em_andamento':
        return cs.primaryContainer;
      case 'finalizado':
      case 'concluido':
        return cs.secondaryContainer;
      default:
        return cs.surfaceContainerHighest;
    }
  }

  Color? _chipFg(BuildContext context, String s) {
    final cs = Theme.of(context).colorScheme;
    switch (s) {
      case 'em_andamento':
        return cs.onPrimaryContainer;
      case 'finalizado':
      case 'concluido':
        return cs.onSecondaryContainer;
      default:
        return cs.onSurfaceVariant;
    }
  }

  String _fmtDt(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;

    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  // =========================
  // Confirm dialogs
  // =========================

  Future<bool> _confirmStart({
    required String origem,
    required String destino,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar início do trecho'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Deseja iniciar este trecho agora?'),
            const SizedBox(height: 12),
            Text(
              '$origem → $destino',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ao iniciar, o app começará a enviar sua localização (GPS) periodicamente.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Iniciar'),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<bool> _confirmFinish({
    required String origem,
    required String destino,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar finalização do trecho'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Deseja finalizar este trecho agora?'),
            const SizedBox(height: 12),
            Text(
              '$origem → $destino',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ao finalizar, o envio de GPS deste trecho será interrompido.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    return res == true;
  }

  // =========================
  // Actions
  // =========================

  Future<void> _handleIniciar({
    required int bdtId,
    required int agendaId,
    required int trechoId,
    required String origem,
    required String destino,
  }) async {
    // se já existe trecho em andamento, não inicia outro
    if (isTracking && !(trackingAgendaId == agendaId && trackingTrechoId == trechoId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Já existe um trecho em andamento. Finalize-o antes de iniciar outro.")),
      );
      return;
    }

    final okConfirm = await _confirmStart(origem: origem, destino: destino);
    if (!okConfirm || !mounted) return;

    setState(() => busyTrechoId = trechoId);

    try {
      final ok = await BdtService.iniciarTrecho(
        bdtId: bdtId,
        agendaId: agendaId,
        trechoId: trechoId,
      );

      if (!mounted) return;

      if (ok) _startTracking(bdtId, agendaId, trechoId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? "Trecho iniciado." : "Falha ao iniciar trecho.")),
      );

      await _load(bdtId);
    } finally {
      if (mounted) setState(() => busyTrechoId = null);
    }
  }

  Future<void> _handleFinalizar({
    required int bdtId,
    required int agendaId,
    required int trechoId,
    required String origem,
    required String destino,
  }) async {
    final okConfirm = await _confirmFinish(origem: origem, destino: destino);
    if (!okConfirm || !mounted) return;

    setState(() => busyTrechoId = trechoId);

    try {
      final ok = await BdtService.finalizarTrecho(
        bdtId: bdtId,
        trechoId: trechoId,
      );

      if (!mounted) return;

      if (ok) _stopTracking();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? "Trecho finalizado." : "Falha ao finalizar trecho.")),
      );

      await _load(bdtId);
    } finally {
      if (mounted) setState(() => busyTrechoId = null);
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

    // ✅ erro do backend: mostra mensagem bonita
    if (payload != null && payload!['success'] != true) {
      final msg = (payload!['message'] ?? 'Erro ao carregar BDT.').toString();
      return AppScaffold(
        title: "BDT",
        subtitle: subtitle,
        onRefresh: () => _load(bdtId),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 34),
                    const SizedBox(height: 10),
                    Text(msg, textAlign: TextAlign.center),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: () => _load(bdtId),
                      icon: const Icon(Icons.refresh),
                      label: const Text("Tentar novamente"),
                    ),
                  ],
                ),
              ),
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
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
              children: [
                if (isTracking)
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const Icon(Icons.gps_fixed),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "GPS em envio",
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "Agenda #$trackingAgendaId • Trecho #$trackingTrechoId",
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Chip(
                            label: const Text("Ao vivo"),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  ),

                ...agendas.map((raw) {
                  final a = raw as Map<String, dynamic>;
                  final int agendaId = int.tryParse(a['fk_agenda'].toString()) ?? 0;
                  final trechos = (a['trechos'] as List<dynamic>? ?? []);

                  final saida = _fmtDt(a['datahora_saida']);
                  final retorno = _fmtDt(a['datahora_retorno_previsto']);

                  return Card(
                    margin: const EdgeInsets.only(top: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        title: Text(
                          "Agenda #$agendaId",
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: (saida.isNotEmpty || retorno.isNotEmpty)
                            ? Text(
                                "$saida → $retorno",
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            : null,
                        children: trechos.map((t) {
                          final tt = t as Map<String, dynamic>;
                          final int trechoId = int.tryParse(tt['id'].toString()) ?? 0;
                          final String status = (tt['exec_status'] ?? 'pendente').toString();

                          final origem = (tt['origem'] ?? '').toString();
                          final destino = (tt['destino'] ?? '').toString();

                          final bool isTrackingThis =
                              (trackingAgendaId == agendaId && trackingTrechoId == trechoId);

                          final bool isBusyThis = (busyTrechoId == trechoId);
                          final bool hasAnyBusy = (busyTrechoId != null);

                          // regra: se tem um trecho em andamento, não pode iniciar outro
                          final bool podeIniciarEste = !isTracking && !hasAnyBusy;

                          Widget action;
                          if (isBusyThis) {
                            action = const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            );
                          } else if (status == 'em_andamento') {
                            action = ElevatedButton(
                              onPressed: hasAnyBusy
                                  ? null
                                  : () => _handleFinalizar(
                                        bdtId: bdtId,
                                        agendaId: agendaId,
                                        trechoId: trechoId,
                                        origem: origem,
                                        destino: destino,
                                      ),
                              child: const Text("Finalizar"),
                            );
                          } else if (status == 'pendente') {
                            action = OutlinedButton(
                              onPressed: podeIniciarEste
                                  ? () => _handleIniciar(
                                        bdtId: bdtId,
                                        agendaId: agendaId,
                                        trechoId: trechoId,
                                        origem: origem,
                                        destino: destino,
                                      )
                                  : null,
                              child: const Text("Iniciar"),
                            );
                          } else {
                            action = const Icon(Icons.chevron_right);
                          }

                          return Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outlineVariant,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(_statusIcon(status)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "$origem → $destino",
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          Chip(
                                            visualDensity: VisualDensity.compact,
                                            backgroundColor: _chipBg(context, status),
                                            label: Text(
                                              _statusLabel(status),
                                              style: TextStyle(color: _chipFg(context, status)),
                                            ),
                                          ),
                                          if (isTrackingThis)
                                            Chip(
                                              visualDensity: VisualDensity.compact,
                                              avatar: const Icon(Icons.gps_fixed, size: 16),
                                              label: const Text("GPS enviando"),
                                            ),
                                          if (isTracking && !isTrackingThis && status == 'pendente')
                                            Chip(
                                              visualDensity: VisualDensity.compact,
                                              label: const Text("Aguardando finalizar"),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                action,
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
