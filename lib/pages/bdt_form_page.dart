import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/bdt_service.dart';
import '../widgets/app_scaffold.dart';

class BdtFormPage extends StatefulWidget {
  const BdtFormPage({super.key});

  @override
  State<BdtFormPage> createState() => _BdtFormPageState();
}

class _BdtFormPageState extends State<BdtFormPage> {
  Map<String, dynamic>? payload;
  bool saving = false;

  bool _loadedOnce = false;

  // ====== campos do BDT (o que já existia) ======
  final garagemCtrl = TextEditingController();
  final localEmbarqueCtrl = TextEditingController();

  final recolhHoraCtrl = TextEditingController();
  final recolhOdoCtrl = TextEditingController();

  final partidaHoraCtrl = TextEditingController();
  final partidaOdoCtrl = TextEditingController();

  final usoHoraCtrl = TextEditingController();
  final usoOdoCtrl = TextEditingController();

  final outrasObsCtrl = TextEditingController();

  // ====== listas operacionais (sem trechos aqui) ======
  List<Map<String, dynamic>> abastecimentos = [];
  List<Map<String, dynamic>> manutencoes = [];

  // ====== input formatters ======
  final _decimal2 = FilteringTextInputFormatter.allow(
    RegExp(r'^\d*([.,]\d{0,2})?$'),
  );
  final _decimal1 = FilteringTextInputFormatter.allow(
    RegExp(r'^\d*([.,]\d{0,1})?$'),
  );

  @override
  void dispose() {
    garagemCtrl.dispose();
    localEmbarqueCtrl.dispose();
    recolhHoraCtrl.dispose();
    recolhOdoCtrl.dispose();
    partidaHoraCtrl.dispose();
    partidaOdoCtrl.dispose();
    usoHoraCtrl.dispose();
    usoOdoCtrl.dispose();
    outrasObsCtrl.dispose();
    super.dispose();
  }

  // =========================
  // helpers
  // =========================

  String _two(int v) => v.toString().padLeft(2, '0');

  String _fmtApiDateTime(DateTime dt) {
    // yyyy-mm-dd HH:MM:00
    return "${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}:00";
  }

  String _normDecimal(String s) => s.trim().replaceAll(',', '.');

  Future<String?> _pickDateTimeString({String? initial}) async {
    DateTime base = DateTime.now();
    if (initial != null && initial.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(initial.replaceFirst(' ', 'T'));
      if (parsed != null) base = parsed;
    }

    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null) return null;

    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (t == null) return null;

    final dt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    return _fmtApiDateTime(dt);
  }

  Future<void> _pickTime(TextEditingController c) async {
    final now = TimeOfDay.now();

    final picked = await showTimePicker(
      context: context,
      initialTime: now,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked == null) return;
    c.text = "${_two(picked.hour)}:${_two(picked.minute)}";
  }

  // =========================
  // Load
  // =========================

  Future<void> _load(int bdtId) async {
    final res = await BdtService.detalhes(bdtId);
    if (!mounted) return;

    setState(() => payload = res);

    final ok = res != null && res['success'] == true;
    if (!ok) return;

    final bdt = (res['bdt'] as Map<String, dynamic>? ?? {});

    // campos do BDT
    garagemCtrl.text = (bdt['garagem'] ?? '').toString();
    localEmbarqueCtrl.text = (bdt['local_embarque'] ?? '').toString();

    recolhHoraCtrl.text = (bdt['recolhimento_hora'] ?? '').toString();
    recolhOdoCtrl.text = (bdt['recolhimento_odometro'] ?? '').toString();

    partidaHoraCtrl.text = (bdt['partida_hora'] ?? '').toString();
    partidaOdoCtrl.text = (bdt['partida_odometro'] ?? '').toString();

    usoHoraCtrl.text = (bdt['uso_hora'] ?? '').toString();
    usoOdoCtrl.text = (bdt['uso_odometro'] ?? '').toString();

    outrasObsCtrl.text = (bdt['outras_observacoes'] ?? '').toString();

    // listas (se vierem no detalhes, usa; senão busca via endpoints específicos)
    final ab = (res['abastecimentos'] as List<dynamic>?)
        ?.whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final man = (res['manutencoes'] as List<dynamic>?)
        ?.whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final abResolved =
        ab ?? await BdtService.listarAbastecimentos(bdtId: bdtId);
    final manResolved = man ?? await BdtService.listarManutencoes(bdtId: bdtId);

    if (!mounted) return;
    setState(() {
      abastecimentos = abResolved;
      manutencoes = manResolved;
    });
  }

  // =========================
  // Save BDT campos principais
  // =========================

  Future<void> _saveBdtCampos(int bdtId) async {
    setState(() => saving = true);
    try {
      final ok = await BdtService.salvarCamposBdt(
        bdtId: bdtId,
        campos: {
          "garagem": garagemCtrl.text.trim(),
          "local_embarque": localEmbarqueCtrl.text.trim(),
          "recolhimento_hora": recolhHoraCtrl.text.trim(),
          "recolhimento_odometro": recolhOdoCtrl.text.trim(),
          "partida_hora": partidaHoraCtrl.text.trim(),
          "partida_odometro": partidaOdoCtrl.text.trim(),
          "uso_hora": usoHoraCtrl.text.trim(),
          "uso_odometro": usoOdoCtrl.text.trim(),
          "outras_observacoes": outrasObsCtrl.text.trim(),
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? "BDT salvo com sucesso." : "Falha ao salvar BDT."),
        ),
      );

      if (ok) Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  // =========================
  // CRUD Abastecimentos
  // =========================

  Future<void> _openAbastecimentoSheet({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final id = isEdit ? (int.tryParse(existing!['id'].toString()) ?? 0) : 0;

    final dataHoraCtrl = TextEditingController(
      text: (existing?['data_hora'] ?? '').toString(),
    );
    final odoCtrl = TextEditingController(
      text: (existing?['odometro_km'] ?? '').toString(),
    );
    final litrosCtrl = TextEditingController(
      text: (existing?['litros'] ?? '').toString(),
    );
    final valorCtrl = TextEditingController(
      text: (existing?['valor_total'] ?? '').toString(),
    );
    final notaCtrl = TextEditingController(
      text: (existing?['nota_fiscal'] ?? '').toString(),
    );
    final obsCtrl = TextEditingController(
      text: (existing?['observacoes'] ?? '').toString(),
    );

    String? tipo = (existing?['tipo_combustivel'] ?? '').toString();
    if (tipo != null && tipo.trim().isEmpty) tipo = null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        final pad = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isEdit
                          ? "Editar abastecimento"
                          : "Adicionar abastecimento",
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (isEdit && id > 0)
                    IconButton(
                      tooltip: "Excluir",
                      onPressed: () async {
                        final ok = await _confirmDelete(
                          "Excluir este abastecimento?",
                        );
                        if (!ok) return;

                        final bdtId =
                            ModalRoute.of(context)!.settings.arguments as int;

                        final delOk = await BdtService.excluirAbastecimento(
                          bdtId: bdtId,
                          abastecimentoId: id,
                        );

                        if (!context.mounted) return;

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              delOk
                                  ? "Abastecimento excluído."
                                  : "Falha ao excluir.",
                            ),
                          ),
                        );

                        Navigator.pop(context);
                        await _load(bdtId);
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: dataHoraCtrl,
                readOnly: true,
                onTap: () async {
                  final picked = await _pickDateTimeString(
                    initial: dataHoraCtrl.text,
                  );
                  if (picked != null) dataHoraCtrl.text = picked;
                },
                decoration: const InputDecoration(
                  labelText: "Data/Hora",
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.schedule),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: tipo,
                items: const [
                  DropdownMenuItem(value: "gasolina", child: Text("Gasolina")),
                  DropdownMenuItem(value: "etanol", child: Text("Etanol")),
                  DropdownMenuItem(value: "diesel", child: Text("Diesel")),
                  DropdownMenuItem(value: "gnv", child: Text("GNV")),
                  DropdownMenuItem(value: "outro", child: Text("Outro")),
                ],
                onChanged: (v) => tipo = v,
                decoration: const InputDecoration(
                  labelText: "Tipo combustível",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: odoCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_decimal1],
                      decoration: const InputDecoration(
                        labelText: "Odômetro (km)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: litrosCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_decimal2],
                      decoration: const InputDecoration(
                        labelText: "Litros",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valorCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [_decimal2],
                decoration: const InputDecoration(
                  labelText: "Valor total",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notaCtrl,
                decoration: const InputDecoration(
                  labelText: "Nota fiscal",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: obsCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: "Observações",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () async {
                  final bdtId =
                      ModalRoute.of(context)!.settings.arguments as int;

                  final data = <String, dynamic>{
                    "data_hora": dataHoraCtrl.text.trim(),
                    "tipo_combustivel": tipo,
                    "odometro_km": _normDecimal(odoCtrl.text),
                    "litros": _normDecimal(litrosCtrl.text),
                    "valor_total": _normDecimal(valorCtrl.text),
                    "nota_fiscal": notaCtrl.text.trim(),
                    "observacoes": obsCtrl.text.trim(),
                  };

                  data.removeWhere(
                    (k, v) => v == null || (v is String && v.trim().isEmpty),
                  );

                  final ok = isEdit
                      ? await BdtService.atualizarAbastecimento(
                          bdtId: bdtId,
                          abastecimentoId: id,
                          data: data,
                        )
                      : await BdtService.criarAbastecimento(
                          bdtId: bdtId,
                          data: data,
                        );

                  if (!context.mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? "Abastecimento salvo."
                            : "Falha ao salvar abastecimento.",
                      ),
                    ),
                  );

                  if (ok) {
                    Navigator.pop(context);
                    await _load(bdtId);
                  }
                },
                icon: const Icon(Icons.save),
                label: Text(
                  isEdit ? "Salvar alterações" : "Adicionar abastecimento",
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // =========================
  // CRUD Manutenções
  // =========================

  Future<void> _openManutencaoSheet({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final id = isEdit ? (int.tryParse(existing!['id'].toString()) ?? 0) : 0;

    final inicioCtrl = TextEditingController(
      text: (existing?['data_hora_inicio'] ?? '').toString(),
    );
    final fimCtrl = TextEditingController(
      text: (existing?['data_hora_fim'] ?? '').toString(),
    );
    final odoCtrl = TextEditingController(
      text: (existing?['odometro_km'] ?? '').toString(),
    );
    final descCtrl = TextEditingController(
      text: (existing?['descricao'] ?? '').toString(),
    );
    final obsCtrl = TextEditingController(
      text: (existing?['observacoes'] ?? '').toString(),
    );

    bool houveGasto =
        (existing?['houve_gasto'] == true || existing?['houve_gasto'] == 1);
    final valorCtrl = TextEditingController(
      text: (existing?['valor_gasto'] ?? '').toString(),
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final pad = MediaQuery.of(context).viewInsets.bottom;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + pad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isEdit ? "Editar manutenção" : "Adicionar manutenção",
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (isEdit && id > 0)
                        IconButton(
                          tooltip: "Excluir",
                          onPressed: () async {
                            final ok = await _confirmDelete(
                              "Excluir esta manutenção?",
                            );
                            if (!ok) return;

                            final bdtId =
                                ModalRoute.of(context)!.settings.arguments
                                    as int;

                            final delOk = await BdtService.excluirManutencao(
                              bdtId: bdtId,
                              manutencaoId: id,
                            );

                            if (!context.mounted) return;

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  delOk
                                      ? "Manutenção excluída."
                                      : "Falha ao excluir.",
                                ),
                              ),
                            );

                            Navigator.pop(context);
                            await _load(bdtId);
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: inicioCtrl,
                    readOnly: true,
                    onTap: () async {
                      final picked = await _pickDateTimeString(
                        initial: inicioCtrl.text,
                      );
                      if (picked != null) inicioCtrl.text = picked;
                    },
                    decoration: const InputDecoration(
                      labelText: "Início (data/hora)",
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.schedule),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: fimCtrl,
                    readOnly: true,
                    onTap: () async {
                      final picked = await _pickDateTimeString(
                        initial: fimCtrl.text,
                      );
                      if (picked != null) fimCtrl.text = picked;
                    },
                    decoration: const InputDecoration(
                      labelText: "Fim (data/hora) (opcional)",
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.schedule),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: odoCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_decimal1],
                    decoration: const InputDecoration(
                      labelText: "Odômetro (km)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: "Descrição",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: houveGasto,
                    onChanged: (v) => setLocal(() => houveGasto = v),
                    title: const Text("Houve gasto?"),
                  ),
                  if (houveGasto) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: valorCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_decimal2],
                      decoration: const InputDecoration(
                        labelText: "Valor gasto",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: obsCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: "Observações",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () async {
                      final bdtId =
                          ModalRoute.of(context)!.settings.arguments as int;

                      if (descCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Informe a descrição da manutenção."),
                          ),
                        );
                        return;
                      }

                      final data = <String, dynamic>{
                        "data_hora_inicio": inicioCtrl.text.trim(),
                        "data_hora_fim": fimCtrl.text.trim(),
                        "odometro_km": _normDecimal(odoCtrl.text),
                        "descricao": descCtrl.text.trim(),
                        "houve_gasto": houveGasto,
                        "valor_gasto": _normDecimal(valorCtrl.text),
                        "observacoes": obsCtrl.text.trim(),
                      };

                      data.removeWhere(
                        (k, v) =>
                            v == null || (v is String && v.trim().isEmpty),
                      );

                      final ok = isEdit
                          ? await BdtService.atualizarManutencao(
                              bdtId: bdtId,
                              manutencaoId: id,
                              data: data,
                            )
                          : await BdtService.criarManutencao(
                              bdtId: bdtId,
                              data: data,
                            );

                      if (!context.mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? "Manutenção salva."
                                : "Falha ao salvar manutenção.",
                          ),
                        ),
                      );

                      if (ok) {
                        Navigator.pop(context);
                        await _load(bdtId);
                      }
                    },
                    icon: const Icon(Icons.save),
                    label: Text(
                      isEdit ? "Salvar alterações" : "Adicionar manutenção",
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _confirmDelete(String msg) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Confirmar"),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Excluir"),
          ),
        ],
      ),
    );
    return res == true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedOnce) return;
    _loadedOnce = true;

    final int bdtId = ModalRoute.of(context)!.settings.arguments as int;
    _load(bdtId);
  }

  @override
  Widget build(BuildContext context) {
    final int bdtId = ModalRoute.of(context)!.settings.arguments as int;

    // erro do backend
    if (payload != null && payload!['success'] != true) {
      final msg = (payload!['message'] ?? 'Erro ao carregar formulário.')
          .toString();
      return AppScaffold(
        title: "Formulário do BDT",
        subtitle: "BDT #$bdtId",
        onRefresh: () => _load(bdtId),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(msg, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return AppScaffold(
      title: "Formulário do BDT",
      subtitle: "BDT #$bdtId",
      onRefresh: () => _load(bdtId),
      body: (payload == null)
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
              children: [
                _cardIdentificacao(),
                const SizedBox(height: 12),
                _cardHorariosOdo(),
                const SizedBox(height: 12),

                // ✅ sem trechos aqui
                _cardAbastecimentos(),
                const SizedBox(height: 12),

                _cardManutencoes(),
                const SizedBox(height: 12),

                _cardAcidentesPlaceholder(),
                const SizedBox(height: 12),

                _cardOutrasObs(),
                const SizedBox(height: 14),

                FilledButton.icon(
                  onPressed: saving ? null : () => _saveBdtCampos(bdtId),
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text("Salvar BDT"),
                ),
              ],
            ),
    );
  }

  // =========================
  // Cards
  // =========================

  Widget _cardIdentificacao() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Identificação",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: garagemCtrl,
              decoration: const InputDecoration(
                labelText: "Garagem",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: localEmbarqueCtrl,
              decoration: const InputDecoration(
                labelText: "Local de embarque",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardHorariosOdo() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Horários e odômetro",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _rowHoraOdo(
              title: "Recolhimento",
              horaCtrl: recolhHoraCtrl,
              odoCtrl: recolhOdoCtrl,
              onPickHora: () => _pickTime(recolhHoraCtrl),
            ),
            const SizedBox(height: 12),
            _rowHoraOdo(
              title: "Partida",
              horaCtrl: partidaHoraCtrl,
              odoCtrl: partidaOdoCtrl,
              onPickHora: () => _pickTime(partidaHoraCtrl),
            ),
            const SizedBox(height: 12),
            _rowHoraOdo(
              title: "Uso",
              horaCtrl: usoHoraCtrl,
              odoCtrl: usoOdoCtrl,
              onPickHora: () => _pickTime(usoHoraCtrl),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardAbastecimentos() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Abastecimentos",
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openAbastecimentoSheet(),
                  icon: const Icon(Icons.local_gas_station),
                  label: const Text("Adicionar"),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (abastecimentos.isEmpty)
              Text(
                "Nenhum abastecimento lançado.",
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: abastecimentos.length,
                separatorBuilder: (_, __) => const Divider(height: 0),
                itemBuilder: (_, i) {
                  final a = abastecimentos[i];
                  final tipo = (a['tipo_combustivel'] ?? '').toString();
                  final litros = (a['litros'] ?? '').toString();
                  final valor = (a['valor_total'] ?? '').toString();
                  final dh = (a['data_hora'] ?? '').toString();

                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      "${tipo.isEmpty ? 'Combustível' : tipo} • ${litros.isEmpty ? '-' : litros} L • ${valor.isEmpty ? '-' : valor}",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: dh.isEmpty ? null : Text(dh),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _openAbastecimentoSheet(existing: a),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _cardManutencoes() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Manutenções",
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openManutencaoSheet(),
                  icon: const Icon(Icons.build_circle_outlined),
                  label: const Text("Adicionar"),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (manutencoes.isEmpty)
              Text(
                "Nenhuma manutenção lançada.",
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: manutencoes.length,
                separatorBuilder: (_, __) => const Divider(height: 0),
                itemBuilder: (_, i) {
                  final m = manutencoes[i];
                  final desc = (m['descricao'] ?? '').toString();
                  final ini = (m['data_hora_inicio'] ?? '').toString();

                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      desc.isEmpty ? "Manutenção" : desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: ini.isEmpty ? null : Text(ini),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _openManutencaoSheet(existing: m),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _cardAcidentesPlaceholder() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Acidentes",
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.car_crash),
                  label: const Text("Em breve"),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "Ainda não existe tabela/endpoint para acidentes. Assim que você criar, eu completo o CRUD aqui.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardOutrasObs() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Outras observações",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: outrasObsCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: "Outras observações",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowHoraOdo({
    required String title,
    required TextEditingController horaCtrl,
    required TextEditingController odoCtrl,
    required VoidCallback onPickHora,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: horaCtrl,
                readOnly: true,
                onTap: onPickHora,
                decoration: const InputDecoration(
                  labelText: "Hora (HH:MM)",
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
                  labelText: "Odômetro",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
