import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../services/background_location_service.dart';
import '../services/bdt_service.dart';
import '../services/gps_live_service.dart';
import '../services/location_service.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/seguranca_bdt_dialog.dart';
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

  // Estado da fila de envio (M2): tela mostra quantos pontos ainda estão
  // pendentes localmente. Atualizado por _pontosTimer a cada 10s enquanto
  // o tracking está ativo.
  int _pontosNaFila = 0;
  Timer? _pontosTimer;

  // Estado de conexão (M2): chip online/offline no card de tracking.
  List<ConnectivityResult> _conn = const [ConnectivityResult.none];
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  bool get isTracking => trackingAgendaId != null && trackingTrechoId != null;
  bool get _isOnline => _conn.any((r) =>
      r == ConnectivityResult.wifi ||
      r == ConnectivityResult.mobile ||
      r == ConnectivityResult.ethernet ||
      r == ConnectivityResult.vpn);

  // =========================
  // Load
  // =========================

  Future<void> _openBdtActionsSheet(int bdtId) async {
    // Lê o status atual a partir do payload carregado (se disponível)
    int statusAtual = 0;
    if (payload != null && payload!['success'] == true && payload!['bdt'] is Map) {
      final bdtMap = payload!['bdt'] as Map;
      statusAtual = int.tryParse((bdtMap['id_status_atual'] ?? 0).toString()) ?? 0;
    }
    final bool podeReabrir = statusAtual == 3 || statusAtual == 4;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text("Formulário"),
                subtitle: const Text("Informações do BDT"),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.pushNamed(context, "/bdt_form", arguments: bdtId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_check),
                title: const Text("Validar início"),
                subtitle: const Text("Marcos + presença de passageiros"),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.pushNamed(context, "/validacao/inicio", arguments: bdtId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.stop_circle_outlined,
                    color: Colors.redAccent),
                title: const Text("Concluir viagem"),
                subtitle: const Text("Feedback + encerrar"),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.pushNamed(context, "/conclusao", arguments: bdtId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_road),
                title: const Text("Trecho extra"),
                subtitle: const Text("Cadastrar origem e destino"),
                onTap: () {
                  Navigator.pop(ctx);
                  Future.microtask(() => _openTrechoExtraSheet(bdtId));
                },
              ),
              // Sprint M6 (Web+Mobile / Sprint 1 web) — informações de
              // segurança. Reusa o mesmo conteúdo do modal web via
              // endpoint bdt/seguranca/textos.
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text("Informações de segurança"),
                subtitle: const Text("Telefones, conduta, procedimentos"),
                onTap: () {
                  Navigator.pop(ctx);
                  Future.microtask(() => SegurancaBdtDialog.show(context));
                },
              ),
              if (podeReabrir)
                ListTile(
                  leading: const Icon(
                    Icons.restart_alt,
                    color: Colors.orange,
                  ),
                  title: const Text(
                    "Reabrir BDT",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    statusAtual == 3
                        ? "BDT atualmente Encerrado"
                        : "BDT atualmente Cancelado",
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    Future.microtask(() => _openReabrirBdtSheet(bdtId));
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// Dialog de reabertura: coleta justificativa obrigatória (>=10 chars)
  /// e chama a API. Em caso de sucesso, recarrega a tela.
  Future<void> _openReabrirBdtSheet(int bdtId) async {
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool enviando = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) {
        return StatefulBuilder(
          builder: (dctx, setDialogState) {
            return AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.restart_alt, color: Colors.orange),
                  SizedBox(width: 8),
                  Text("Reabrir BDT"),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        "Informe o motivo da reabertura. A ação ficará registrada no histórico com seu usuário, data/hora e origem (mobile).",
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: ctrl,
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 500,
                        autofocus: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: "Justificativa *",
                          helperText: "Mínimo 10 caracteres",
                        ),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.length < 10) {
                            return "Justificativa obrigatória (mínimo 10 caracteres).";
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: enviando ? null : () => Navigator.pop(dctx),
                  child: const Text("Cancelar"),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: enviando
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }
                          setDialogState(() => enviando = true);

                          final res = await BdtService.reabrirBdt(
                            bdtId: bdtId,
                            justificativa: ctrl.text,
                          );

                          if (!mounted) return;

                          Navigator.pop(dctx);

                          final ok = res['success'] == true;
                          final msg = (res['message'] ??
                                  (ok
                                      ? 'BDT reaberto com sucesso.'
                                      : 'Falha ao reabrir BDT.'))
                              .toString();

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(msg),
                              backgroundColor: ok ? Colors.green : Colors.red,
                            ),
                          );

                          if (ok) {
                            await _load(bdtId);
                          }
                        },
                  icon: enviando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.restart_alt),
                  label: const Text("Confirmar reabertura"),
                ),
              ],
            );
          },
        );
      },
    );
  }

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

  /// Inicia o foreground service de GPS.
  ///
  /// Mantém-se **síncrono** de propósito: ele só atualiza o state local e
  /// dispara o serviço em background com `fire-and-forget`. O pedido de
  /// permissão "O tempo todo" é feito uma vez no carregamento da página
  /// (`_requestBackgroundPermissionOnce`), nunca no meio do fluxo de UI —
  /// caso contrário o picker do Android suspende a Activity enquanto há um
  /// bottom sheet aberto, e quando volta o widget tree já desmontou o sheet,
  /// gerando o assert `_dependents.isEmpty is not true`.
  void _startTracking(int bdtId, int agendaId, int trechoId) {
    if (trackingAgendaId == agendaId && trackingTrechoId == trechoId) return;

    _stopTracking();

    setState(() {
      trackingAgendaId = agendaId;
      trackingTrechoId = trechoId;
    });

    // ignore: discarded_futures
    GpsLiveService.start(
      bdtId: bdtId,
      agendaId: agendaId,
      trechoId: trechoId,
      interval: const Duration(seconds: 5),
    );

    _startPontosMonitor(bdtId, trechoId);
  }

  /// Sprint M4 (patch) — antes de iniciar um trecho, verifica no
  /// backend se o BDT ainda não tem KM inicial. Se precisar, mostra
  /// um dialog pedindo o valor. Retorna a decisão do usuário: **cancelar**
  /// (aborta o iniciar-trecho), **pular** (segue sem enviar KM) ou
  /// **valor** (envia KM pro backend gravar antes de iniciar o trecho).
  ///
  /// Falha de rede no /km/estado → trata como "não precisa perguntar"
  /// pra não bloquear o condutor por um GET secundário; a KM pode ser
  /// preenchida depois pela web.
  Future<_KmDecision> _askKmInicialSePreciso(int bdtId) async {
    final estado = await BdtService.obterEstadoKm(bdtId);
    if (!mounted) return const _KmDecision.cancel();
    if (estado == null || !estado.precisaPerguntarKmInicial) {
      return const _KmDecision.skip();
    }

    final ctrl = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('KM inicial'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Você ainda não informou a KM do odômetro no início do BDT. '
              'Pode preencher agora — ou pular e informar depois.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'KM inicial',
                border: OutlineInputBorder(),
                suffixText: 'km',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('Pular'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Salvar e iniciar'),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (result == null) return const _KmDecision.cancel();
    if (result.isEmpty) return const _KmDecision.skip();
    final km = double.tryParse(result.replaceAll(',', '.'));
    if (km == null || km <= 0) return const _KmDecision.skip();
    return _KmDecision.value(km);
  }

  /// Liga o polling do contador de pontos pendentes na fila SQLite +
  /// a subscription de conectividade. Chamado em [_startTracking].
  void _startPontosMonitor(int bdtId, int trechoId) {
    _pontosTimer?.cancel();
    _connSub?.cancel();

    // Primeira leitura imediata.
    // ignore: discarded_futures
    _atualizarPontosNaFila(bdtId, trechoId);

    _pontosTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      // ignore: discarded_futures
      _atualizarPontosNaFila(bdtId, trechoId);
    });

    // Estado inicial + escuta de mudanças.
    Connectivity().checkConnectivity().then((r) {
      if (mounted) setState(() => _conn = r);
    });
    _connSub = Connectivity().onConnectivityChanged.listen((r) {
      if (mounted) setState(() => _conn = r);
    });
  }

  Future<void> _atualizarPontosNaFila(int bdtId, int trechoId) async {
    try {
      final n = await BackgroundLocationService.countPendingFor(
        bdtId: bdtId,
        trechoId: trechoId,
      );
      if (mounted && _pontosNaFila != n) {
        setState(() => _pontosNaFila = n);
      }
    } catch (_) {
      // não bloqueia UI se a fila estiver indisponível
    }
  }

  /// Pede a permissão de localização "O tempo todo" e a isenção de
  /// otimização de bateria (M2) UMA vez por sessão de página, fora de
  /// qualquer fluxo de bottom sheet/dialog para não conflitar com
  /// widgets em remoção.
  bool _bgPermissionAsked = false;
  Future<void> _requestBackgroundPermissionOnce() async {
    if (_bgPermissionAsked) return;
    _bgPermissionAsked = true;

    final okLoc = await LocationService.ensureBackgroundPermission();
    if (!mounted) return;
    if (!okLoc) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sem a permissão "O tempo todo" o GPS pode parar quando você sair do app.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }

    // Isenção de bateria — sem isso o foreground service morre após
    // ~30 min de tela bloqueada em vários fabricantes.
    final okBat = await LocationService.ensureBatteryOptimizationDisabled();
    if (!mounted) return;
    if (!okBat) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Autorize "Sem otimização de bateria" para que o GPS não pare com o celular bloqueado.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<bool> _deleteTrechoExtra({
    required int bdtId,
    required int trechoId,
    required String origem,
    required String destino,
  }) async {
    // não deixa excluir se estiver enviando GPS nesse trecho extra
    final bool isTrackingThis =
        (trackingAgendaId == 0 && trackingTrechoId == trechoId);

    if (isTrackingThis) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Finalize o trecho (pare o GPS) antes de excluir."),
        ),
      );
      return false;
    }

    final confirmed = await _confirmDialog(
      title: "Excluir trecho extra?",
      message: "$origem → $destino\n\nEssa ação não pode ser desfeita.",
      cancelText: "Cancelar",
      confirmText: "Sim, excluir",
    );

    if (!confirmed) return false;

    setState(() => busyTrechoId = trechoId);
    try {
      final ok = await BdtService.excluirTrechoExtra(
        bdtId: bdtId,
        trechoId: trechoId,
      );

      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? "Trecho extra excluído." : "Falha ao excluir trecho extra.",
          ),
        ),
      );

      if (ok) await _load(bdtId);
      return ok;
    } finally {
      if (mounted) setState(() => busyTrechoId = null);
    }
  }

  void _stopTracking() {
    // ignore: discarded_futures
    GpsLiveService.stop();

    _pontosTimer?.cancel();
    _pontosTimer = null;
    _connSub?.cancel();
    _connSub = null;

    if (trackingAgendaId != null || trackingTrechoId != null || _pontosNaFila != 0) {
      setState(() {
        trackingAgendaId = null;
        trackingTrechoId = null;
        _pontosNaFila = 0;
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

  /*Widget _fabActions(int bdtId) {
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
  }*/

  Future<void> _openTrechoExtraSheet(int bdtId) async {
    final origemCtrl = TextEditingController();
    final destinoCtrl = TextEditingController();
    final obsCtrl = TextEditingController();
    final horaSaidaCtrl = TextEditingController();
    final horaChegadaCtrl = TextEditingController();

    Future<void> pickHora(
      TextEditingController c,
      StateSetter setLocal,
    ) async {
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );
      if (t == null) return;
      String two(int v) => v.toString().padLeft(2, '0');
      setLocal(() {
        c.text = '${two(t.hour)}:${two(t.minute)}';
      });
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final pad = MediaQuery.of(ctx).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + pad),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    const SizedBox(height: 4),
                    const Text(
                      "Um trecho que não veio de nenhuma solicitação — "
                      "ex.: um deslocamento extra que surgiu na viagem.",
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: origemCtrl,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: "Origem *",
                        hintText: "Ex.: UERJ Maracanã",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: destinoCtrl,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: "Destino *",
                        hintText: "Ex.: Hospital Pedro Ernesto",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: horaSaidaCtrl,
                            readOnly: true,
                            onTap: () => pickHora(horaSaidaCtrl, setLocal),
                            decoration: const InputDecoration(
                              labelText: "Saída (HH:MM)",
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.schedule),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: horaChegadaCtrl,
                            readOnly: true,
                            onTap: () => pickHora(horaChegadaCtrl, setLocal),
                            decoration: const InputDecoration(
                              labelText: "Chegada (HH:MM)",
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.schedule),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: obsCtrl,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: "Observação (opcional)",
                        hintText: "Ex.: desvio pela Vermelha por obra",
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

                        final hs = horaSaidaCtrl.text.trim();
                        final hc = horaChegadaCtrl.text.trim();
                        // Se preencheu um dos horários, exige o outro
                        // (senão saída sem chegada, ou vice-versa, fica
                        // meia-boca no relatório).
                        if ((hs.isNotEmpty) != (hc.isNotEmpty)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Preencha os DOIS horários (saída e chegada) ou nenhum.",
                              ),
                            ),
                          );
                          return;
                        }

                        final ok = await BdtService.criarTrechoExtra(
                          bdtId: bdtId,
                          origem: origem,
                          destino: destino,
                          horaSaida: hs.isEmpty ? null : hs,
                          horaChegada: hc.isEmpty ? null : hc,
                          obs: obsCtrl.text,
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
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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

  /// Procura o Map do trecho em execução (para extrair origem/destino
  /// individualmente na UI). Retorna null se não achar.
  Map<String, dynamic>? _findTrechoAtivo() {
    final tId = trackingTrechoId;
    if (tId == null || tId <= 0) return null;

    final ok = payload != null && payload!['success'] == true;
    if (!ok) return null;

    final extras = (payload!['trechos_extras'] as List<dynamic>? ?? const []);
    for (final t in extras) {
      final tt = (t as Map<String, dynamic>);
      final id = int.tryParse(tt['id'].toString()) ?? 0;
      if (id == tId) return tt;
    }

    final agendas = (payload!['agendas'] as List<dynamic>? ?? const []);
    for (final a in agendas) {
      final trechos = ((a as Map<String, dynamic>)['trechos']
              as List<dynamic>? ??
          const []);
      for (final t in trechos) {
        final tt = (t as Map<String, dynamic>);
        final id = int.tryParse(tt['id'].toString()) ?? 0;
        if (id == tId) return tt;
      }
    }

    return null;
  }

  String _fmtOrigemDestino(Map<String, dynamic> trecho) {
    final origem = (trecho['origem'] ?? '').toString().trim();
    final destino = (trecho['destino'] ?? '').toString().trim();
    if (origem.isEmpty && destino.isEmpty) return 'Trecho em execução';
    if (origem.isEmpty) return '→ $destino';
    if (destino.isEmpty) return '$origem →';
    return '$origem → $destino';
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

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

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

    final odoFocus = FocusNode();
    String? odoError;
    String? formError;

    // ✅ NOVO: banner de progresso destacado
    bool showProgress = false;
    String progressMsg = 'Enviando...';

    // ✅ controla se o sheet ainda está aberto
    bool sheetOpen = true;

    final sheetFuture = showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final pad = MediaQuery.of(ctx).viewInsets.bottom;
        final bool isBusyThis = (busyTrechoId == trechoId) || showProgress;

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void clearErrors() {
              if (odoError != null || formError != null) {
                setLocal(() {
                  odoError = null;
                  formError = null;
                });
              }
            }

            Widget progressBanner() {
              final cs = Theme.of(ctx).colorScheme;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: cs.primaryContainer,
                  border: Border.all(color: cs.primary.withOpacity(.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Aguarde…',
                            style: TextStyle(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            progressMsg,
                            style: TextStyle(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'O GPS será ativado automaticamente em seguida.',
                            style: TextStyle(
                              color: cs.onPrimaryContainer.withOpacity(.85),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + pad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Iniciar trecho',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ✅ NOVO: banner visível mesmo com o botão fora da tela
                  if (showProgress) ...[
                    progressBanner(),
                    const SizedBox(height: 12),
                  ],

                  if (formError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Theme.of(ctx).colorScheme.errorContainer,
                      ),
                      child: Text(
                        formError!,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: horaCtrl,
                          readOnly: true,
                          onTap: isBusyThis ? null : () => _pickHm(horaCtrl),
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
                          focusNode: odoFocus,
                          enabled: !isBusyThis,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) {
                            if (odoError != null || formError != null) {
                              setLocal(() {
                                odoError = null;
                                formError = null;
                              });
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'Odômetro saída',
                            border: const OutlineInputBorder(),
                            errorText: odoError,
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
                          onPressed: isBusyThis
                              ? null
                              : () => Navigator.pop(ctx),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: isBusyThis
                              ? null
                              : () async {
                                  clearErrors();

                                  if (odoCtrl.text.trim().isEmpty) {
                                    setLocal(() {
                                      odoError = 'Informe o odômetro de saída.';
                                    });
                                    FocusScope.of(ctx).requestFocus(odoFocus);
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

                                  if (!mounted || !sheetOpen) return;

                                  // Sprint M4 (patch) — se o BDT ainda não tem
                                  // KM inicial, pergunta antes. Cancelar =
                                  // aborta o iniciar-trecho (respeita o clique
                                  // em "Cancelar" do dialog).
                                  final kmDecision =
                                      await _askKmInicialSePreciso(bdtId);
                                  if (!mounted || !sheetOpen) return;
                                  if (kmDecision.cancelled) return;

                                  // ✅ NOVO: mostra banner de progresso IMEDIATAMENTE
                                  setLocal(() {
                                    showProgress = true;
                                    progressMsg =
                                        'Iniciando trecho no servidor…';
                                  });

                                  setState(() => busyTrechoId = trechoId);
                                  try {
                                    final ok = await BdtService.iniciarTrecho(
                                      bdtId: bdtId,
                                      agendaId: (agendaId > 0)
                                          ? agendaId
                                          : null,
                                      trechoId: trechoId,
                                      kmInicial: kmDecision.value,
                                    );

                                    if (!mounted || !sheetOpen) return;

                                    if (ok) {
                                      setLocal(() {
                                        progressMsg =
                                            'Salvando dados do trecho…';
                                      });

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

                                      if (!mounted || !sheetOpen) return;

                                      setLocal(() {
                                        progressMsg = 'Ativando GPS…';
                                      });

                                      _startTracking(bdtId, agendaId, trechoId);

                                      if (!mounted) return;
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context)
                                        ..clearSnackBars()
                                        ..showSnackBar(
                                          const SnackBar(
                                            content: Text('Trecho iniciado.'),
                                          ),
                                        );
                                      await _load(bdtId);
                                    } else {
                                      setLocal(() {
                                        showProgress = false; // ✅ para o banner
                                        formError = 'Falha ao iniciar trecho.';
                                      });
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => busyTrechoId = null);
                                    }
                                  }
                                },
                          icon: isBusyThis
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
      },
    );

    sheetFuture.whenComplete(() => sheetOpen = false);
    await sheetFuture;

    await Future.delayed(const Duration(milliseconds: 350));
    horaCtrl.dispose();
    odoCtrl.dispose();
    odoFocus.dispose();
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

    final odoFocus = FocusNode();
    String? odoError;
    String? formError;

    bool sheetOpen = true;

    final sheetFuture = showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final pad = MediaQuery.of(ctx).viewInsets.bottom;
        final bool isBusyThis = (busyTrechoId == trechoId);

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void clearErrors() {
              if (odoError != null || formError != null) {
                setLocal(() {
                  odoError = null;
                  formError = null;
                });
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + pad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Finalizar trecho',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (formError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Theme.of(ctx).colorScheme.errorContainer,
                      ),
                      child: Text(
                        formError!,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

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
                          focusNode: odoFocus,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) {
                            if (odoError != null || formError != null) {
                              setLocal(() {
                                odoError = null;
                                formError = null;
                              });
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'Odômetro chegada',
                            border: const OutlineInputBorder(),
                            errorText: odoError,
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
                          onPressed: isBusyThis
                              ? null
                              : () => Navigator.pop(ctx),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: isBusyThis
                              ? null
                              : () async {
                                  clearErrors();

                                  if (odoCtrl.text.trim().isEmpty) {
                                    setLocal(() {
                                      odoError =
                                          'Informe o odômetro de chegada.';
                                    });
                                    FocusScope.of(ctx).requestFocus(odoFocus);
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

                                  if (!mounted || !sheetOpen) return;

                                  setState(() => busyTrechoId = trechoId);
                                  try {
                                    final ok = await BdtService.finalizarTrecho(
                                      bdtId: bdtId,
                                      trechoId: trechoId,
                                    );

                                    if (!mounted || !sheetOpen) return;

                                    if (ok) {
                                      await BdtService.atualizarTrechoExecucao(
                                        bdtId: bdtId,
                                        trechoId: trechoId,
                                        data: {
                                          "datahora_chegada":
                                              _apiDateTimeFromHm(
                                                horaCtrl.text.trim(),
                                              ),
                                          "odometro_chegada": odoCtrl.text
                                              .trim(),
                                        },
                                      );

                                      if (!mounted || !sheetOpen) return;

                                      _stopTracking();

                                      Navigator.pop(ctx); // fecha primeiro
                                      ScaffoldMessenger.of(context)
                                        ..clearSnackBars()
                                        ..showSnackBar(
                                          const SnackBar(
                                            content: Text('Trecho finalizado.'),
                                          ),
                                        );
                                      await _load(bdtId);
                                    } else {
                                      setLocal(() {
                                        formError =
                                            'Falha ao finalizar trecho.';
                                      });
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => busyTrechoId = null);
                                    }
                                  }
                                },
                          icon: isBusyThis
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
      },
    );

    sheetFuture.whenComplete(() => sheetOpen = false);
    await sheetFuture;

    await Future.delayed(const Duration(milliseconds: 350));
    horaCtrl.dispose();
    odoCtrl.dispose();
    odoFocus.dispose();
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

              // Sprint M4 (patch) — pergunta KM inicial se ainda não foi
              // informada. Se cancelar, aborta.
              final kmDecision = await _askKmInicialSePreciso(bdtId);
              if (!mounted) return;
              if (kmDecision.cancelled) return;

              setState(() => busyTrechoId = trechoId);
              try {
                final ok = await BdtService.iniciarTrecho(
                  bdtId: bdtId,
                  agendaId: agendaId,
                  trechoId: trechoId,
                  kmInicial: kmDecision.value,
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
                          agendaId > 0
                              ? 'Editar trecho da agenda'
                              : 'Editar trecho extra',
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

    // Adia o pedido de permissão para o próximo frame: evita disparar o
    // picker do Android no mesmo tick em que a página está sendo construída.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // ignore: discarded_futures
      _requestBackgroundPermissionOnce();
    });
  }

  /// Card grande no topo da página do BDT quando há trecho em execução.
  /// Mostra origem/destino em destaque + chips com estado da rede e da
  /// fila de envio (M2).
  Widget _cardTrechoAtivo() {
    final trecho = _findTrechoAtivo();
    final origem = (trecho?['origem'] ?? '').toString().trim();
    final destino = (trecho?['destino'] ?? '').toString().trim();
    final semOrigem = origem.isEmpty;
    final semDestino = destino.isEmpty;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: scheme.primaryContainer.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.gps_fixed, color: scheme.primary, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Trecho em execução',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                _chipStatusFila(),
                const SizedBox(width: 6),
                _chipStatusConexao(),
              ],
            ),
            const SizedBox(height: 12),
            _linhaOrigemDestino(
              icone: Icons.trip_origin,
              label: 'Origem',
              texto: semOrigem ? '—' : origem,
              vazio: semOrigem,
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(9, 2, 0, 2),
              child: SizedBox(
                height: 14,
                child: VerticalDivider(width: 2, thickness: 1.4),
              ),
            ),
            _linhaOrigemDestino(
              icone: Icons.location_on,
              label: 'Destino',
              texto: semDestino ? '—' : destino,
              vazio: semDestino,
            ),
          ],
        ),
      ),
    );
  }

  Widget _linhaOrigemDestino({
    required IconData icone,
    required String label,
    required String texto,
    required bool vazio,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                texto,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: vazio ? FontWeight.w400 : FontWeight.w700,
                  fontStyle: vazio ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chipStatusConexao() {
    final online = _isOnline;
    return Chip(
      visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar: Icon(
        online ? Icons.wifi : Icons.wifi_off,
        size: 14,
        color: online ? Colors.green : Colors.red,
      ),
      label: Text(online ? 'Online' : 'Offline',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _chipStatusFila() {
    final n = _pontosNaFila;
    final cor = n == 0
        ? Colors.green
        : (n < 20 ? Colors.orange : Colors.red);
    return Chip(
      visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar: Icon(Icons.cloud_upload_outlined, size: 14, color: cor),
      label: Text(
        n == 0 ? 'Enviado' : '$n na fila',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
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
    final trechosExtras = ok
        ? (payload!['trechos_extras'] as List<dynamic>? ?? const [])
        : const [];

    // Sempre mostra Protocolo (ano/numero), nunca o ID interno.
    // Se ainda não carregou, mostra só "BDT" — o carregamento é curto.
    final titulo = bdt != null
        ? "BDT ${bdt['ano']}/${bdt['numero']}"
        : "BDT";
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
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () =>
              Navigator.pushNamed(context, "/bdt_form", arguments: bdtId),
          icon: const Icon(Icons.edit_note),
          label: const Text("Formulário"),
        ),
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
        onPressed: () => _openBdtActionsSheet(bdtId),
        icon: const Icon(Icons.edit_note),
        label: const Text("Ações"),
      ),
      body: (payload == null)
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
              children: [
                if (isTracking) _cardTrechoAtivo(),
                if (trechosExtras.isNotEmpty)
                  Card(
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
                        title: const Text(
                          "Trechos extras",
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          "${trechosExtras.length} trecho(s)",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        children: trechosExtras.map((t) {
                          final tt = (t is Map<String, dynamic>)
                              ? t
                              : Map<String, dynamic>.from(t as Map);

                          const int agendaId = 0; // ✅ extra
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
                          final bool canDelete =
                              !hasAnyBusy &&
                              status != 'em_andamento' &&
                              !isTrackingThis;

                          Widget mainButton;

                          if (isBusyThis) {
                            mainButton = const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            );
                          } else if (status == 'em_andamento') {
                            final bool canFinish =
                                !hasAnyBusy && (!isTracking || isTrackingThis);

                            mainButton = FilledButton(
                              onPressed: canFinish
                                  ? () => _openFinalizarTrechoSheet(
                                      bdtId: bdtId,
                                      agendaId: agendaId, // ✅ 0
                                      trecho: tt,
                                    )
                                  : null,
                              child: const Text("Finalizar"),
                            );
                          } else if (status == 'pendente') {
                            final bool canStart =
                                !hasAnyBusy && (!isTracking || isTrackingThis);

                            mainButton = OutlinedButton(
                              onPressed: canStart
                                  ? () => _openIniciarTrechoSheet(
                                      bdtId: bdtId,
                                      agendaId: agendaId, // ✅ 0
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
                                              agendaId: agendaId, // ✅ 0
                                              trecho: tt,
                                            ),
                                      icon: const Icon(Icons.edit),
                                    ),
                                    IconButton(
                                      tooltip: "Excluir",
                                      onPressed: (isBusyThis || !canDelete)
                                          ? null
                                          : () => _deleteTrechoExtra(
                                              bdtId: bdtId,
                                              trechoId: trechoId,
                                              origem: origem,
                                              destino: destino,
                                            ),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                ...agendas.asMap().entries.map((entry) {
                  final int idxAgenda = entry.key;
                  final raw = entry.value;
                  final a = raw as Map<String, dynamic>;
                  final int agendaId =
                      int.tryParse(a['fk_agenda'].toString()) ?? 0;
                  final trechos = (a['trechos'] as List<dynamic>? ?? []);

                  final saida = _fmtDt(a['datahora_saida']);
                  final retorno = _fmtDt(a['datahora_retorno_previsto']);

                  // Título da agenda sem expor o ID interno:
                  // preferência: horário de saída (se houver) → "Agenda das HH:MM".
                  // fallback: numeração sequencial → "Agenda 1", "Agenda 2".
                  final horaSaidaAgenda = _fmtTimeOnly(a['datahora_saida']);
                  final tituloAgenda = horaSaidaAgenda.isNotEmpty
                      ? "Agenda das $horaSaidaAgenda"
                      : "Agenda ${idxAgenda + 1}";

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
                          tituloAgenda,
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

/// Resultado do dialog "informe a KM inicial". Três estados possíveis:
/// - [_KmDecision.cancel] — usuário fechou o dialog; o iniciar-trecho
///   deve ser abortado.
/// - [_KmDecision.skip] — usuário optou por não informar agora (ou
///   nem chegou a ver o dialog porque o BDT já tinha KM). Segue com
///   o iniciar-trecho sem enviar KM.
/// - [_KmDecision.value] — usuário digitou um valor; envia junto.
class _KmDecision {
  final bool cancelled;
  final double? value;
  const _KmDecision.cancel() : cancelled = true, value = null;
  const _KmDecision.skip()   : cancelled = false, value = null;
  const _KmDecision.value(double v) : cancelled = false, value = v;
}
