import 'package:flutter/material.dart';
import '../services/bdt_service.dart';
import '../services/gps_live_service.dart';
import '../widgets/app_scaffold.dart';
import 'package:flutter/services.dart';

class BdtPage extends StatefulWidget {
  const BdtPage({super.key});

  @override
  State<BdtPage> createState() => _BdtPageState();
}

class _BdtPageState extends State<BdtPage> {
  Map<String, dynamic>? payload;

  // busy só no trecho clicado
  int? busyTrechoId;

  int? trackingAgendaId;
  int? trackingTrechoId;

  bool _loadedOnce = false;

  bool get isTracking => trackingAgendaId != null && trackingTrechoId != null;

  // =========================
  // Load
  // =========================

  Future<void> _load(int bdtId) async {
    final res = await BdtService.detalhes(bdtId);
    if (!mounted) return;

    setState(() => payload = res);

    // se existir trecho em andamento, liga o tracking automaticamente
    _syncTrackingFromPayload(bdtId);
  }

  void _syncTrackingFromPayload(int bdtId) {
    final ok = payload != null && payload!['success'] == true;
    if (!ok) {
      _stopTracking();
      return;
    }

    // 1) se backend devolver trecho_em_andamento, usa direto
    final em = payload!['em_andamento'];
    if (em is Map) {
      final int aId = int.tryParse((em['agenda_id'] ?? 0).toString()) ?? 0;
      final int tId = int.tryParse((em['trecho_id'] ?? 0).toString()) ?? 0;

      if (tId > 0) {
        if (trackingAgendaId == aId && trackingTrechoId == tId) return;
        _startTracking(bdtId, aId, tId); // aId pode ser 0
        return;
      }
    }

    // 2) fallback: varre agendas/trechos
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
          if (trackingAgendaId == agendaId && trackingTrechoId == trechoId)
            return;
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
  // UI helpers
  // =========================

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return const {};
  }

  Map<String, dynamic> _execFromTrecho(Map<String, dynamic> trecho) {
    // Ajuste/adicione chaves conforme seu backend
    return _asMap(
      trecho['execucao'] ??
          trecho['trecho_execucao'] ??
          trecho['exec'] ??
          trecho['bdt_execucao'],
    );
  }

  String _fmtOdo(dynamic v) {
    if (v == null) return '';
    final s = v.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return '';

    final n = num.tryParse(s);
    if (n == null) return s;

    // remove ".0" (12.0 -> 12)
    if (n % 1 == 0) return n.toInt().toString();
    return n.toString();
  }

  String _odoSaidaFromTrecho(Map<String, dynamic> trecho) {
    final exec = _execFromTrecho(trecho);

    return _fmtOdo(
      trecho['odometro_saida'] ??
          trecho['saida_odometro'] ??
          trecho['odometro_saida_real'] ??
          exec['odometro_saida'] ??
          exec['odometro_saida_real'] ??
          exec['saida_odometro'],
    );
  }

  String _odoChegadaFromTrecho(Map<String, dynamic> trecho) {
    final exec = _execFromTrecho(trecho);

    return _fmtOdo(
      trecho['odometro_chegada'] ??
          trecho['chegada_odometro'] ??
          trecho['odometro_chegada_real'] ??
          exec['odometro_chegada'] ??
          exec['odometro_chegada_real'] ??
          exec['chegada_odometro'],
    );
  }

  Future<bool> _confirmDialog({
    required String title,
    required String message,
    String cancelText = "Cancelar",
    String confirmText = "Confirmar",
  }) async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(cancelText),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );

    return res ?? false;
  }

  Widget _fabActions(int bdtId) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.extended(
          heroTag: "fab_trecho_extra",
          onPressed: () => _openTrechoExtraSheet(bdtId),
          icon: const Icon(Icons.add_road),
          label: const Text("Trecho extra"),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: "fab_formulario",
          onPressed: () =>
              Navigator.pushNamed(context, "/bdt_form", arguments: bdtId),
          icon: const Icon(Icons.edit_note),
          label: const Text("Formulário"),
        ),
      ],
    );
  }

  Future<void> _openTrechoExtraSheet(int bdtId) async {
    final origemCtrl = TextEditingController();
    final destinoCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final pad = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "Adicionar trecho extra",
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: origemCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: "Origem",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: destinoCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: "Destino",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () async {
                  final origem = origemCtrl.text.trim();
                  final destino = destinoCtrl.text.trim();

                  if (origem.isEmpty || destino.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Informe origem e destino."),
                      ),
                    );
                    return;
                  }

                  final ok = await BdtService.criarTrechoExtra(
                    bdtId: bdtId,
                    origem: origem,
                    destino: destino,
                  );

                  if (!context.mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? "Trecho extra criado."
                            : "Falha ao criar trecho extra.",
                      ),
                    ),
                  );

                  if (ok) {
                    Navigator.pop(ctx);
                    await _load(bdtId);
                  }
                },
                icon: const Icon(Icons.add_road),
                label: const Text("Cadastrar trecho extra"),
              ),
            ],
          ),
        );
      },
    );
  }

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

  String _two(int v) => v.toString().padLeft(2, '0');

  DateTime _bdtBaseDate() {
    final ok = payload != null && payload!['success'] == true;
    final bdt = ok ? (payload!['bdt'] as Map<String, dynamic>?) : null;

    final raw = (bdt?['data_referencia'] ?? bdt?['data'] ?? '')
        .toString()
        .trim();
    final d = DateTime.tryParse(raw);
    return d ?? DateTime.now();
  }

  /// Mostra algo tipo "03/01 07:00"
  String _fmtDt(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';
    final dt = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (dt == null) return s;

    return '${_two(dt.day)}/${_two(dt.month)} ${_two(dt.hour)}:${_two(dt.minute)}';
  }

  /// Mostra só "HH:MM" (mesmo se vier com data)
  String _fmtTimeOnly(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';

    if (RegExp(r'^\d{2}:\d{2}$').hasMatch(s)) return s;

    final dt = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (dt != null) return '${_two(dt.hour)}:${_two(dt.minute)}';

    // fallback: tenta extrair HH:MM de "YYYY-MM-DD HH:MM:SS"
    final m = RegExp(r'(\d{2}):(\d{2})').firstMatch(s);
    if (m != null) return '${m.group(1)}:${m.group(2)}';

    return s;
  }

  /// Constrói "YYYY-MM-DD HH:MM:00" usando a data do BDT
  String _apiDateTimeFromHm(String hm) {
    final base = _bdtBaseDate();
    final parts = hm.split(':');
    if (parts.length != 2) return hm;

    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return '${base.year}-${_two(base.month)}-${_two(base.day)} ${_two(h)}:${_two(m)}:00';
  }

  Future<void> _pickHm(TextEditingController c) async {
    final now = TimeOfDay.now();

    TimeOfDay initial = now;
    final existing = c.text.trim();
    if (RegExp(r'^\d{2}:\d{2}$').hasMatch(existing)) {
      final p = existing.split(':');
      final hh = int.tryParse(p[0]) ?? now.hour;
      final mm = int.tryParse(p[1]) ?? now.minute;
      initial = TimeOfDay(hour: hh, minute: mm);
    }

    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;

    c.text = '${_two(picked.hour)}:${_two(picked.minute)}';
  }

  String _asStr(dynamic v) => (v ?? '').toString();
  String _asOdo(dynamic v) => _asStr(v).trim();

  // =========================
  // Core: salvar campos do trecho (origem/destino + execução)
  // =========================

  Future<bool> _saveTrechoCampos({
    required int bdtId,
    required int trechoId,
    required String origem,
    required String destino,
    required String horaSaidaHm,
    required String odoSaida,
    required String horaChegadaHm,
    required String odoChegada,
  }) async {
    bool okAll = true;

    // 1) origem/destino (trecho da agenda)
    // OBS: mantém compatível com seu service atual (origem/destino).
    // Se não quiser permitir edição de origem/destino, é só não chamar.
    if (origem.isNotEmpty && destino.isNotEmpty) {
      final okTrecho = await BdtService.atualizarTrecho(
        bdtId: bdtId,
        trechoId: trechoId,
        origem: origem,
        destino: destino,
      );
      okAll = okAll && okTrecho;
    }

    // 2) execução (hora/odômetro de saída/chegada)
    // ✅ Você vai precisar implementar esse endpoint no backend + no BdtService.
    final execData = <String, dynamic>{};

    if (horaSaidaHm.trim().isNotEmpty)
      execData['inicio_real'] = _apiDateTimeFromHm(horaSaidaHm.trim());
    if (odoSaida.trim().isNotEmpty)
      execData['odometro_saida'] = odoSaida.trim();

    if (horaChegadaHm.trim().isNotEmpty)
      execData['fim_real'] = _apiDateTimeFromHm(horaChegadaHm.trim());
    if (odoChegada.trim().isNotEmpty)
      execData['odometro_chegada'] = odoChegada.trim();

    if (execData.isNotEmpty) {
      final okExec = await BdtService.atualizarTrechoExecucao(
        bdtId: bdtId,
        trechoId: trechoId,
        data: execData,
      );
      okAll = okAll && okExec;
    }

    return okAll;
  }

  // =========================
  // Editor do trecho (no próprio local do 2º print)
  // =========================

  Future<void> _openIniciarTrechoSheet({
    required int bdtId,
    required int agendaId,
    required Map<String, dynamic> trecho,
  }) async {
    final int trechoId = int.tryParse(trecho['id'].toString()) ?? 0;

    final bool isTrackingThis =
        (trackingAgendaId == agendaId && trackingTrechoId == trechoId);

    if (isTracking && !isTrackingThis) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Já existe um trecho em andamento. Finalize-o antes de iniciar outro.',
          ),
        ),
      );
      return;
    }

    final horaCtrl = TextEditingController(
      text: _fmtTimeOnly(trecho['inicio_real'] ?? trecho['datahora_saida']),
    );

    if (horaCtrl.text.trim().isEmpty) {
      final now = DateTime.now();
      horaCtrl.text = '${_two(now.hour)}:${_two(now.minute)}';
    }

    final odoCtrl = TextEditingController(text: _odoSaidaFromTrecho(trecho));

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final pad = MediaQuery.of(ctx).viewInsets.bottom;
        final bool isBusyThis = (busyTrechoId == trechoId);

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Iniciar trecho',
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: horaCtrl,
                      readOnly: true,
                      onTap: () => _pickHm(horaCtrl),
                      decoration: const InputDecoration(
                        labelText: 'Hora saída (HH:MM)',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.schedule),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: odoCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Odômetro saída',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isBusyThis ? null : () => Navigator.pop(ctx),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isBusyThis
                          ? null
                          : () async {
                              if (odoCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Informe o odômetro de saída.',
                                    ),
                                  ),
                                );
                                return;
                              }

                              final confirmed = await _confirmDialog(
                                title: 'Iniciar trecho?',
                                message:
                                    'Tem certeza que deseja iniciar este trecho?\n\n'
                                    'Hora de saída: ${horaCtrl.text.trim()}\n'
                                    'Odômetro: ${odoCtrl.text.trim()}',
                                cancelText: 'Não',
                                confirmText: 'Sim, iniciar',
                              );

                              if (!confirmed) return;

                              setState(() => busyTrechoId = trechoId);
                              try {
                                final ok = await BdtService.iniciarTrecho(
                                  bdtId: bdtId,
                                  agendaId: (agendaId > 0) ? agendaId : null,
                                  trechoId: trechoId,
                                );

                                if (!mounted) return;

                                if (ok) {
                                  await BdtService.atualizarTrechoExecucao(
                                    bdtId: bdtId,
                                    trechoId: trechoId,
                                    data: {
                                      "datahora_saida": _apiDateTimeFromHm(
                                        horaCtrl.text.trim(),
                                      ),
                                      "odometro_saida": odoCtrl.text.trim(),
                                    },
                                  );

                                  _startTracking(bdtId, agendaId, trechoId);
                                }

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ok
                                          ? 'Trecho iniciado.'
                                          : 'Falha ao iniciar trecho.',
                                    ),
                                  ),
                                );

                                Navigator.pop(ctx);
                                await _load(bdtId);
                              } finally {
                                if (mounted)
                                  setState(() => busyTrechoId = null);
                              }
                            },
                      icon: isBusyThis
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: const Text('Iniciar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openFinalizarTrechoSheet({
    required int bdtId,
    required int agendaId,
    required Map<String, dynamic> trecho,
  }) async {
    final int trechoId = int.tryParse(trecho['id'].toString()) ?? 0;

    final bool isTrackingThis =
        (trackingAgendaId == agendaId && trackingTrechoId == trechoId);

    if (isTracking && !isTrackingThis) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Você está com outro trecho em andamento. Finalize o trecho em envio antes.',
          ),
        ),
      );
      return;
    }

    final horaCtrl = TextEditingController(
      text: _fmtTimeOnly(trecho['fim_real'] ?? trecho['datahora_chegada']),
    );

    if (horaCtrl.text.trim().isEmpty) {
      final now = DateTime.now();
      horaCtrl.text = '${_two(now.hour)}:${_two(now.minute)}';
    }

    final odoCtrl = TextEditingController(text: _odoChegadaFromTrecho(trecho));

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final pad = MediaQuery.of(ctx).viewInsets.bottom;
        final bool isBusyThis = (busyTrechoId == trechoId);

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Finalizar trecho',
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: horaCtrl,
                      readOnly: true,
                      onTap: () => _pickHm(horaCtrl),
                      decoration: const InputDecoration(
                        labelText: 'Hora chegada (HH:MM)',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.schedule),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: odoCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Odômetro chegada',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isBusyThis ? null : () => Navigator.pop(ctx),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isBusyThis
                          ? null
                          : () async {
                              if (odoCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Informe o odômetro de chegada.',
                                    ),
                                  ),
                                );
                                return;
                              }

                              final confirmed = await _confirmDialog(
                                title: 'Finalizar trecho?',
                                message:
                                    'Tem certeza que deseja finalizar este trecho?\n\n'
                                    'Hora de chegada: ${horaCtrl.text.trim()}\n'
                                    'Odômetro: ${odoCtrl.text.trim()}',
                                cancelText: 'Não',
                                confirmText: 'Sim, finalizar',
                              );

                              if (!confirmed) return;

                              setState(() => busyTrechoId = trechoId);
                              try {
                                final ok = await BdtService.finalizarTrecho(
                                  bdtId: bdtId,
                                  trechoId: trechoId,
                                );

                                if (!mounted) return;

                                if (ok) {
                                  await BdtService.atualizarTrechoExecucao(
                                    bdtId: bdtId,
                                    trechoId: trechoId,
                                    data: {
                                      "datahora_chegada": _apiDateTimeFromHm(
                                        horaCtrl.text.trim(),
                                      ),
                                      "odometro_chegada": odoCtrl.text.trim(),
                                    },
                                  );

                                  _stopTracking();
                                }

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ok
                                          ? 'Trecho finalizado.'
                                          : 'Falha ao finalizar trecho.',
                                    ),
                                  ),
                                );

                                Navigator.pop(ctx);
                                await _load(bdtId);
                              } finally {
                                if (mounted)
                                  setState(() => busyTrechoId = null);
                              }
                            },
                      icon: isBusyThis
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.flag),
                      label: const Text('Finalizar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openTrechoEditor({
    required int bdtId,
    required int agendaId,
    required Map<String, dynamic> trecho,
  }) async {
    final int trechoId = int.tryParse(trecho['id'].toString()) ?? 0;
    final String status = (trecho['exec_status'] ?? 'pendente').toString();

    final origemCtrl = TextEditingController(text: _asStr(trecho['origem']));
    final destinoCtrl = TextEditingController(text: _asStr(trecho['destino']));

    final horaSaidaCtrl = TextEditingController(
      text: _fmtTimeOnly(
        trecho['inicio_real'] ??
            trecho['datahora_saida'] ??
            trecho['hora_saida'] ??
            trecho['saida_hora'],
      ),
    );

    final odoSaidaCtrl = TextEditingController(
      text: _asOdo(trecho['odometro_saida'] ?? trecho['saida_odometro']),
    );

    final horaChegadaCtrl = TextEditingController(
      text: _fmtTimeOnly(
        trecho['fim_real'] ??
            trecho['datahora_chegada'] ??
            trecho['hora_chegada'] ??
            trecho['chegada_hora'],
      ),
    );

    final odoChegadaCtrl = TextEditingController(
      text: _asOdo(trecho['odometro_chegada'] ?? trecho['chegada_odometro']),
    );

    // defaults automáticos quando for iniciar/finalizar
    void fillNowIfEmpty(TextEditingController c) {
      if (c.text.trim().isNotEmpty) return;
      final now = DateTime.now();
      c.text = '${_two(now.hour)}:${_two(now.minute)}';
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final pad = MediaQuery.of(ctx).viewInsets.bottom;

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final bool hasAnyBusy = busyTrechoId != null;
            final bool isBusyThis = busyTrechoId == trechoId;
            final bool isTrackingThis =
                (trackingAgendaId == agendaId && trackingTrechoId == trechoId);

            final bool canStart =
                status == 'pendente' &&
                (!isTracking || isTrackingThis) &&
                !hasAnyBusy;
            final bool canFinish = status == 'em_andamento' && !hasAnyBusy;

            Future<void> doSaveOnly() async {
              setState(() => busyTrechoId = trechoId);
              try {
                final ok = await _saveTrechoCampos(
                  bdtId: bdtId,
                  trechoId: trechoId,
                  origem: origemCtrl.text.trim(),
                  destino: destinoCtrl.text.trim(),
                  horaSaidaHm: horaSaidaCtrl.text.trim(),
                  odoSaida: odoSaidaCtrl.text.trim(),
                  horaChegadaHm: horaChegadaCtrl.text.trim(),
                  odoChegada: odoChegadaCtrl.text.trim(),
                );

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok ? 'Trecho atualizado.' : 'Falha ao atualizar trecho.',
                    ),
                  ),
                );

                if (ok) {
                  Navigator.pop(ctx);
                  await _load(bdtId);
                }
              } finally {
                if (mounted) setState(() => busyTrechoId = null);
              }
            }

            Future<void> doStart() async {
              // regra: só 1 trecho em andamento
              if (isTracking && !isTrackingThis) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Já existe um trecho em andamento. Finalize-o antes de iniciar outro.',
                    ),
                  ),
                );
                return;
              }

              // hora automática (mas editável)
              fillNowIfEmpty(horaSaidaCtrl);

              if (odoSaidaCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Informe o odômetro de saída.')),
                );
                return;
              }

              setState(() => busyTrechoId = trechoId);
              try {
                final ok = await BdtService.iniciarTrecho(
                  bdtId: bdtId,
                  agendaId: agendaId,
                  trechoId: trechoId,
                );

                if (!mounted) return;

                if (ok) {
                  // salva execução + origem/destino se quiser
                  await _saveTrechoCampos(
                    bdtId: bdtId,
                    trechoId: trechoId,
                    origem: origemCtrl.text.trim(),
                    destino: destinoCtrl.text.trim(),
                    horaSaidaHm: horaSaidaCtrl.text.trim(),
                    odoSaida: odoSaidaCtrl.text.trim(),
                    horaChegadaHm: '',
                    odoChegada: '',
                  );

                  _startTracking(bdtId, agendaId, trechoId);
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok ? 'Trecho iniciado.' : 'Falha ao iniciar trecho.',
                    ),
                  ),
                );

                Navigator.pop(ctx);
                await _load(bdtId);
              } finally {
                if (mounted) setState(() => busyTrechoId = null);
              }
            }

            Future<void> doFinish() async {
              fillNowIfEmpty(horaChegadaCtrl);

              if (odoChegadaCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Informe o odômetro de chegada.'),
                  ),
                );
                return;
              }

              setState(() => busyTrechoId = trechoId);
              try {
                final ok = await BdtService.finalizarTrecho(
                  bdtId: bdtId,
                  trechoId: trechoId,
                );

                if (!mounted) return;

                if (ok) {
                  await _saveTrechoCampos(
                    bdtId: bdtId,
                    trechoId: trechoId,
                    origem: origemCtrl.text.trim(),
                    destino: destinoCtrl.text.trim(),
                    horaSaidaHm: horaSaidaCtrl.text.trim(),
                    odoSaida: odoSaidaCtrl.text.trim(),
                    horaChegadaHm: horaChegadaCtrl.text.trim(),
                    odoChegada: odoChegadaCtrl.text.trim(),
                  );

                  _stopTracking();
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok ? 'Trecho finalizado.' : 'Falha ao finalizar trecho.',
                    ),
                  ),
                );

                Navigator.pop(ctx);
                await _load(bdtId);
              } finally {
                if (mounted) setState(() => busyTrechoId = null);
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + pad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Editar trecho da agenda',
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Chip(
                        backgroundColor: _chipBg(ctx, status),
                        label: Text(
                          _statusLabel(status),
                          style: TextStyle(color: _chipFg(ctx, status)),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: origemCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Origem',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: destinoCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Destino',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),

                  Text(
                    'Saída',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: horaSaidaCtrl,
                          readOnly: true,
                          onTap: () => _pickHm(horaSaidaCtrl),
                          decoration: const InputDecoration(
                            labelText: 'Hora saída (HH:MM)',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.schedule),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: odoSaidaCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Odômetro saída',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  Text(
                    'Chegada',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: horaChegadaCtrl,
                          readOnly: true,
                          onTap: () => _pickHm(horaChegadaCtrl),
                          decoration: const InputDecoration(
                            labelText: 'Hora chegada (HH:MM)',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.schedule),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: odoChegadaCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Odômetro chegada',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  if (isTrackingThis)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.gps_fixed, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'GPS enviando neste trecho',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isBusyThis ? null : doSaveOnly,
                          icon: isBusyThis
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: const Text('Salvar alterações'),
                        ),
                      ),
                      const SizedBox(width: 10),

                      if (status == 'pendente') ...[
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: (isBusyThis || !canStart)
                                ? null
                                : doStart,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Iniciar'),
                          ),
                        ),
                      ] else if (status == 'em_andamento') ...[
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: (isBusyThis || !canFinish)
                                ? null
                                : doFinish,
                            icon: const Icon(Icons.flag),
                            label: const Text('Finalizar'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // =========================
  // Lifecycle
  // =========================

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedOnce) return;
    _loadedOnce = true;

    final int bdtId = ModalRoute.of(context)!.settings.arguments as int;
    _load(bdtId);
  }

  @override
  void dispose() {
    _stopTracking();
    super.dispose();
  }

  // =========================
  // UI
  // =========================

  @override
  Widget build(BuildContext context) {
    final int bdtId = ModalRoute.of(context)!.settings.arguments as int;

    final ok = payload != null && payload!['success'] == true;
    final bdt = ok ? (payload!['bdt'] as Map<String, dynamic>) : null;
    final agendas = ok ? (payload!['agendas'] as List<dynamic>) : const [];

    final titulo = bdt != null
        ? "BDT ${bdt['ano']}/${bdt['numero']}"
        : "BDT #$bdtId";
    final placa = (bdt != null && (bdt['placa'] ?? '').toString().isNotEmpty)
        ? (bdt['placa'] ?? '').toString()
        : null;
    final subtitle = placa != null ? "$titulo — $placa" : titulo;

    // erro do backend
    if (payload != null && payload!['success'] != true) {
      final msg = (payload!['message'] ?? 'Erro ao carregar BDT.').toString();
      return AppScaffold(
        title: "BDT",
        subtitle: subtitle,
        onRefresh: () => _load(bdtId),
        floatingActionButton: _fabActions(bdtId),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.pushNamed(context, "/bdt_form", arguments: bdtId),
        icon: const Icon(Icons.edit_note),
        label: const Text("Formulário"),
      ),
      body: (payload == null)
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
              children: [
                if (isTracking)
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
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
                  final int agendaId =
                      int.tryParse(a['fk_agenda'].toString()) ?? 0;
                  final trechos = (a['trechos'] as List<dynamic>? ?? []);

                  final saida = _fmtDt(a['datahora_saida']);
                  final retorno = _fmtDt(a['datahora_retorno_previsto']);

                  return Card(
                    margin: const EdgeInsets.only(top: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          12,
                          0,
                          12,
                          12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        collapsedShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
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
                          // dentro do map dos trechos, antes de ler odoSaida:
                          debugPrint('TRECHO KEYS: ${tt.keys}');
                          debugPrint(
                            'TRECHO EXEC: ${tt['execucao'] ?? tt['trecho_execucao']}',
                          );

                          final int trechoId =
                              int.tryParse(tt['id'].toString()) ?? 0;
                          final String status =
                              (tt['exec_status'] ?? 'pendente').toString();

                          final origem = (tt['origem'] ?? '').toString();
                          final destino = (tt['destino'] ?? '').toString();

                          final horaSaida = _fmtTimeOnly(
                            tt['inicio_real'] ?? tt['datahora_saida'],
                          );

                          final odoSaida = _odoSaidaFromTrecho(tt);

                          final horaChegada = _fmtTimeOnly(
                            tt['fim_real'] ?? tt['datahora_chegada'],
                          );

                          final odoChegada = _odoChegadaFromTrecho(tt);

                          final bool isBusyThis = (busyTrechoId == trechoId);
                          final bool hasAnyBusy = (busyTrechoId != null);

                          final bool isTrackingThis =
                              (trackingAgendaId == agendaId &&
                              trackingTrechoId == trechoId);

                          // regra: se tem um trecho em andamento, não pode iniciar outro
                          final bool podeIniciarEste =
                              !isTracking && !hasAnyBusy;

                          Widget mainButton;

                          if (isBusyThis) {
                            mainButton = const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            );
                          } else if (status == 'em_andamento') {
                            // ✅ FINALIZAR de verdade (não abre editor)
                            final bool canFinish =
                                !hasAnyBusy && (!isTracking || isTrackingThis);

                            mainButton = FilledButton(
                              onPressed: canFinish
                                  ? () => _openFinalizarTrechoSheet(
                                      bdtId: bdtId,
                                      agendaId: agendaId,
                                      trecho: tt,
                                    )
                                  : null,
                              child: const Text("Finalizar"),
                            );
                          } else if (status == 'pendente') {
                            // ✅ INICIAR de verdade (não abre editor)
                            final bool canStart =
                                !hasAnyBusy && (!isTracking || isTrackingThis);

                            mainButton = OutlinedButton(
                              onPressed: canStart
                                  ? () => _openIniciarTrechoSheet(
                                      bdtId: bdtId,
                                      agendaId: agendaId,
                                      trecho: tt,
                                    )
                                  : null,
                              child: const Text("Iniciar"),
                            );
                          } else {
                            mainButton = const Icon(Icons.check_circle_outline);
                          }

                          return Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "$origem → $destino",
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),

                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Chip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            backgroundColor: _chipBg(
                                              context,
                                              status,
                                            ),
                                            label: Text(
                                              _statusLabel(status),
                                              style: TextStyle(
                                                color: _chipFg(context, status),
                                              ),
                                            ),
                                          ),
                                          if (isTrackingThis)
                                            Chip(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              avatar: const Icon(
                                                Icons.gps_fixed,
                                                size: 16,
                                              ),
                                              label: const Text("GPS enviando"),
                                            ),
                                          if (isTracking &&
                                              !isTrackingThis &&
                                              status == 'pendente')
                                            const Chip(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              label: Text(
                                                "Aguardando finalizar",
                                              ),
                                            ),
                                        ],
                                      ),

                                      const SizedBox(height: 8),

                                      // Linha "Saída/Chegada" (hora/odo)
                                      if (horaSaida.isNotEmpty ||
                                          odoSaida.isNotEmpty ||
                                          horaChegada.isNotEmpty ||
                                          odoChegada.isNotEmpty)
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Saída: ${horaSaida.isEmpty ? '--:--' : horaSaida} • Odo: ${odoSaida.isEmpty ? '-' : odoSaida}",
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                            Text(
                                              "Chegada: ${horaChegada.isEmpty ? '--:--' : horaChegada} • Odo: ${odoChegada.isEmpty ? '-' : odoChegada}",
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 10),

                                Column(
                                  children: [
                                    mainButton,
                                    const SizedBox(height: 6),
                                    IconButton(
                                      tooltip: "Editar",
                                      onPressed: isBusyThis
                                          ? null
                                          : () => _openTrechoEditor(
                                              bdtId: bdtId,
                                              agendaId: agendaId,
                                              trecho: tt,
                                            ),
                                      icon: const Icon(Icons.edit),
                                    ),
                                  ],
                                ),
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
