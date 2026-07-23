import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/bdt_service.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/assinatura_preview.dart';
import 'assinatura_marco_page.dart';

class BdtFormPage extends StatefulWidget {
  const BdtFormPage({super.key});

  @override
  State<BdtFormPage> createState() => _BdtFormPageState();
}

class _BdtFormPageState extends State<BdtFormPage> {
  Map<String, dynamic>? payload;

  bool _loadedOnce = false;

  // ====== Marcos da Jornada (substitui os antigos campos do BDT) ======
  // Chaves esperadas pelo backend (BdtJornadaService::ORDEM):
  //   'partida' | 'apresentacao' | 'embarque_passageiro' | 'hora_saida'
  // (o 4º entrou na Sprint 5 W+M — datahora_hora_saida DATETIME NULL).
  // Cada entrada guarda o timestamp já registrado (vindo do BDT) e nome de quem
  // registrou (quando vier do endpoint /jornada/estado).
  final Map<String, String?> _marcoDatahora = {
    'partida': null,
    'apresentacao': null,
    'embarque_passageiro': null,
    'hora_saida': null,
  };
  final Map<String, String?> _marcoAutor = {
    'partida': null,
    'apresentacao': null,
    'embarque_passageiro': null,
    'hora_saida': null,
  };
  // Sprint W+M — metadados da assinatura ativa por marco. Populados a
  // partir de est['marcos'][slug]['assinatura'] no /jornada/estado.
  // Servem pro modal do AssinaturaViewButton mostrar quem/quando/obs.
  final Map<String, String?> _marcoAssinaturaSvg = {
    'partida': null,
    'apresentacao': null,
    'embarque_passageiro': null,
    'hora_saida': null,
  };
  final Map<String, String?> _marcoSignatarioTipo = {
    'partida': null,
    'apresentacao': null,
    'embarque_passageiro': null,
    'hora_saida': null,
  };
  final Map<String, String?> _marcoObservacao = {
    'partida': null,
    'apresentacao': null,
    'embarque_passageiro': null,
    'hora_saida': null,
  };
  String? _registrandoMarco; // chave do marco em progresso (lock visual)

  // status do BDT — só permite registrar marco em 2 (Em andamento) ou 5 (Reaberto)
  int? _bdtStatus;

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

  // labels visíveis dos marcos
  static const Map<String, String> _marcoLabel = {
    'partida': 'Partida',
    'apresentacao': 'Apresentação',
    'embarque_passageiro': 'Embarque do passageiro',
    'hora_saida': 'Hora de saída',
  };

  // ícones por marco
  static const Map<String, IconData> _marcoIcone = {
    'partida': Icons.flag_outlined,
    'apresentacao': Icons.front_hand_outlined,
    'embarque_passageiro': Icons.directions_walk,
    'hora_saida': Icons.play_arrow_outlined,
  };

  @override
  void dispose() {
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

  // =========================
  // Load
  // =========================

  Future<void> _load(int bdtId) async {
    final res = await BdtService.detalhes(bdtId);
    if (!mounted) return;

    setState(() => payload = res);

    final ok = res['success'] == true;
    if (!ok) return;

    final bdt = (res['bdt'] as Map<String, dynamic>? ?? {});

    // status atual do BDT (para liberar registro de marcos)
    final dynamic rawStatus = bdt['id_status_atual'] ?? bdt['status_atual'];
    _bdtStatus = rawStatus is int
        ? rawStatus
        : int.tryParse((rawStatus ?? '').toString());

    // marcos diretos a partir das colunas do BDT
    _marcoDatahora['partida'] =
        (bdt['datahora_partida'] ?? '').toString().isEmpty
        ? null
        : bdt['datahora_partida'].toString();
    _marcoDatahora['apresentacao'] =
        (bdt['datahora_apresentacao'] ?? '').toString().isEmpty
        ? null
        : bdt['datahora_apresentacao'].toString();
    _marcoDatahora['embarque_passageiro'] =
        (bdt['datahora_embarque_passageiro'] ?? '').toString().isEmpty
        ? null
        : bdt['datahora_embarque_passageiro'].toString();
    _marcoDatahora['hora_saida'] =
        (bdt['datahora_hora_saida'] ?? '').toString().isEmpty
        ? null
        : bdt['datahora_hora_saida'].toString();

    // Busca o estado canônico dos marcos (timestamps + assinaturas).
    // Falha aqui é silenciosa: já temos fallback nos timestamps acima.
    final est = await BdtService.estadoJornada(bdtId);
    if (est != null && est['marcos'] is Map) {
      final marcos = Map<String, dynamic>.from(est['marcos'] as Map);
      for (final k in _marcoDatahora.keys) {
        final entry = marcos[k];
        if (entry is Map) {
          final dh = entry['datahora'];
          if (dh != null && dh.toString().isNotEmpty) {
            _marcoDatahora[k] = dh.toString();
          }
          final ass = entry['assinatura'];
          if (ass is Map) {
            _marcoAutor[k] = (ass['signatario_nome'] ??
                    ass['criado_por_nome'] ??
                    '')
                .toString();
            final svg = ass['assinatura_svg'];
            if (svg != null && svg.toString().trim().isNotEmpty) {
              _marcoAssinaturaSvg[k] = svg.toString();
            }
            final tipo = ass['signatario_tipo']?.toString().trim();
            if (tipo != null && tipo.isNotEmpty) {
              _marcoSignatarioTipo[k] = tipo;
            }
            final obs = ass['observacao']?.toString().trim();
            if (obs != null && obs.isNotEmpty) {
              _marcoObservacao[k] = obs;
            }
          }
        }
      }
    }

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
  // Marcos da Jornada
  // =========================

  bool get _bdtPermiteMarcos {
    final s = _bdtStatus;
    // Backend só aceita marcos em status 2 (Em andamento) e 5 (Reaberto).
    return s == 2 || s == 5;
  }

  /// Permite registrar somente em ordem (partida → apresentacao → embarque_passageiro).
  /// A ordem também é validada no backend; aqui é só UX.
  bool _marcoLiberado(String marco) {
    switch (marco) {
      case 'partida':
        return true;
      case 'apresentacao':
        return _marcoDatahora['partida'] != null;
      case 'embarque_passageiro':
        return _marcoDatahora['apresentacao'] != null;
    }
    return false;
  }

  /// Sprint W+M — abre o form completo de assinatura pra RE-assinar
  /// um marco já registrado. Reusa `/marco/assinatura` (mesmo fluxo
  /// da `ValidacaoInicioPage`). Chamado pelo botão "Editar" do modal
  /// de visualização (AssinaturaViewButton).
  Future<void> _reassinarMarco(int bdtId, String marco) async {
    final ok = await Navigator.pushNamed(
      context,
      '/marco/assinatura',
      arguments: AssinaturaMarcoArgs(
        bdtId: bdtId,
        marco: marco,
        labelMarco: _marcoLabel[marco] ?? marco,
      ),
    );
    if (ok == true && mounted) {
      // ignore: discarded_futures
      _load(bdtId);
    }
  }

  Future<void> _registrarMarco(int bdtId, String marco) async {
    if (!_bdtPermiteMarcos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'O BDT precisa estar Em andamento ou Reaberto para registrar marcos.',
          ),
        ),
      );
      return;
    }
    if (!_marcoLiberado(marco)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Registre os marcos anteriores antes de "${_marcoLabel[marco]}".',
          ),
        ),
      );
      return;
    }

    // Pergunta observação opcional
    final obsCtrl = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Registrar marco: ${_marcoLabel[marco]}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Será gravado o horário atual e seu nome como assinante.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: obsCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observação (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
    if (go != true) return;

    setState(() => _registrandoMarco = marco);
    try {
      final res = await BdtService.registrarMarcoJornada(
        bdtId: bdtId,
        marco: marco,
        observacao: obsCtrl.text.trim(),
      );
      if (!mounted) return;

      final ok = res['success'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Marco "${_marcoLabel[marco]}" registrado.'
                : (res['message']?.toString() ?? 'Falha ao registrar marco.'),
          ),
        ),
      );

      if (ok) await _load(bdtId);
    } finally {
      if (mounted) setState(() => _registrandoMarco = null);
    }
  }

  // =========================
  // CRUD Abastecimentos
  // =========================

  Future<void> _openAbastecimentoSheet({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final id = isEdit ? (int.tryParse(existing['id'].toString()) ?? 0) : 0;

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
    // Sprint W+M — preço/litro (opcional). Paridade com o web (folha.php
    // L1610-1635): vazio → backend calcula automático (`valor_total/litros`
    // com 2 casas em `normalizeAbastecimentoData`); preenchido → o valor
    // digitado é gravado como manual. Hint mostra qual dos dois modos
    // está ativo (verde = calculado, azul = manual).
    final precoUnitCtrl = TextEditingController(
      text: (existing?['preco_unit'] ?? '').toString(),
    );
    final notaCtrl = TextEditingController(
      text: (existing?['nota_fiscal'] ?? '').toString(),
    );
    final obsCtrl = TextEditingController(
      text: (existing?['observacoes'] ?? '').toString(),
    );

    String? tipo = (existing?['tipo_combustivel'] ?? '').toString();
    if (tipo.trim().isEmpty) tipo = null;

    // Tipos vêm do endpoint /bdt/abastecimentos/tipos — fonte única
    // (`App\Constants\CombustivelTipo`) do web. Antes tinha lista
    // hardcoded ["gasolina","etanol",…] em minúsculo, que o backend
    // recusava silenciosamente ("Não é possível salvar").
    final futureTipos = BdtService.listarTiposCombustivel();

    // Sprint W+M — validação inline paridade com o web (folha.php
    // linhas 1847-1869): data_hora, tipo_combustivel, litros, valor_total
    // são REQUIRED. `fk_condutor` também é required no backend mas
    // é auto-preenchido como condutor logado (BdtApiService::criarAbastecimento
    // linha 441) — não vai como campo do form.
    String? errData;
    String? errTipo;
    String? errLitros;
    String? errValor;
    String? formError;
    bool busy = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final pad = MediaQuery.of(context).viewInsets.bottom;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void clearAllErrors() {
              if (errData != null ||
                  errTipo != null ||
                  errLitros != null ||
                  errValor != null ||
                  formError != null) {
                setLocal(() {
                  errData = null;
                  errTipo = null;
                  errLitros = null;
                  errValor = null;
                  formError = null;
                });
              }
            }

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
                            onPressed: busy
                                ? null
                                : () async {
                                    final ok = await _confirmDelete(
                                      "Excluir este abastecimento?",
                                    );
                                    if (!ok) return;

                                    final bdtId = ModalRoute.of(context)!
                                        .settings
                                        .arguments as int;

                                    final delOk =
                                        await BdtService.excluirAbastecimento(
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
                    if (formError != null) ...[
                      _bannerErro(formError!),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: dataHoraCtrl,
                      readOnly: true,
                      enabled: !busy,
                      onTap: () async {
                        final picked = await _pickDateTimeString(
                          initial: dataHoraCtrl.text,
                        );
                        if (picked != null) {
                          dataHoraCtrl.text = picked;
                          if (errData != null) setLocal(() => errData = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: "Data/Hora *",
                        border: const OutlineInputBorder(),
                        suffixIcon: const Icon(Icons.schedule),
                        errorText: errData,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<List<String>>(
                      future: futureTipos,
                      builder: (context, snap) {
                        final tipos = snap.data ?? const <String>[];
                        final loading =
                            snap.connectionState != ConnectionState.done;
                        // Se o tipo do registro edit não está mais na
                        // lista (raro: enum antigo), preserva no dropdown
                        // pra não perder o valor silenciosamente.
                        final items = <String>{...tipos, if (tipo != null) tipo!}
                            .where((s) => s.isNotEmpty)
                            .toList();

                        return DropdownButtonFormField<String>(
                          initialValue: tipo,
                          isExpanded: true,
                          items: items
                              .map((v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(v),
                                  ))
                              .toList(),
                          onChanged: (busy || loading)
                              ? null
                              : (v) => setLocal(() {
                                    tipo = v;
                                    errTipo = null;
                                  }),
                          decoration: InputDecoration(
                            labelText: "Tipo combustível *",
                            floatingLabelBehavior:
                                FloatingLabelBehavior.always,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                            errorText: errTipo,
                            helperText: loading ? 'Carregando…' : null,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: odoCtrl,
                            enabled: !busy,
                            keyboardType: TextInputType.number,
                            inputFormatters: [_decimal1],
                            decoration: const InputDecoration(
                              labelText: "Odômetro (km)",
                              border: OutlineInputBorder(),
                              helperText: "Opcional",
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: litrosCtrl,
                            enabled: !busy,
                            keyboardType: TextInputType.number,
                            inputFormatters: [_decimal2],
                            onChanged: (_) {
                              // Limpa erro do campo E reavalia o hint
                              // do preço/litro logo abaixo.
                              setLocal(() {
                                if (errLitros != null) errLitros = null;
                              });
                            },
                            decoration: InputDecoration(
                              labelText: "Litros *",
                              border: const OutlineInputBorder(),
                              errorText: errLitros,
                              // Reserva a mesma altura do "Opcional"
                              // do Odômetro ao lado — sem isso os dois
                              // ficam com bases desalinhadas na Row.
                              helperText: ' ',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: valorCtrl,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_decimal2],
                      onChanged: (_) {
                        if (errValor != null) setLocal(() => errValor = null);
                        setLocal(() {}); // reavalia hint do preço/litro
                      },
                      decoration: InputDecoration(
                        labelText: "Valor total *",
                        border: const OutlineInputBorder(),
                        errorText: errValor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Preço por litro — regra do web (folha.php L1610):
                    // - vazio + litros>0 + valor>0 => hint verde
                    //   "Calculado automaticamente: R$ X,XX"
                    // - preenchido => hint azul "Valor informado manualmente"
                    // - senão => hint neutro
                    Builder(
                      builder: (_) {
                        final l = double.tryParse(_normDecimal(litrosCtrl.text)) ?? 0;
                        final v = double.tryParse(_normDecimal(valorCtrl.text)) ?? 0;
                        final digitado =
                            precoUnitCtrl.text.trim().isNotEmpty;
                        String helper;
                        TextStyle? helperStyle;
                        if (digitado) {
                          helper = 'Valor informado manualmente';
                          helperStyle =
                              const TextStyle(color: Color(0xFF0D47A1));
                        } else if (l > 0 && v > 0) {
                          final calc = (v / l).toStringAsFixed(2).replaceAll('.', ',');
                          helper =
                              'Calculado automaticamente: R\$ $calc (valor total ÷ litros)';
                          helperStyle =
                              const TextStyle(color: Color(0xFF2E7D32));
                        } else {
                          helper =
                              'Deixe em branco pra o sistema calcular a partir de valor ÷ litros.';
                          helperStyle = null;
                        }
                        return TextField(
                          controller: precoUnitCtrl,
                          enabled: !busy,
                          keyboardType: TextInputType.number,
                          inputFormatters: [_decimal2],
                          onChanged: (_) => setLocal(() {}),
                          decoration: InputDecoration(
                            labelText: 'Preço por litro (R\$)',
                            border: const OutlineInputBorder(),
                            helperText: helper,
                            helperStyle: helperStyle,
                            helperMaxLines: 2,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notaCtrl,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: "Nota fiscal",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: obsCtrl,
                      enabled: !busy,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: "Observações",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              clearAllErrors();

                              // Valida os 4 required (paridade com web).
                              String? eData;
                              String? eTipo;
                              String? eLitros;
                              String? eValor;
                              if (dataHoraCtrl.text.trim().isEmpty) {
                                eData = "Informe a data/hora.";
                              }
                              if (tipo == null || tipo!.trim().isEmpty) {
                                eTipo = "Selecione o tipo de combustível.";
                              }
                              final litrosVal = double.tryParse(
                                _normDecimal(litrosCtrl.text),
                              );
                              if (litrosVal == null || litrosVal <= 0) {
                                eLitros = "Informe os litros (> 0).";
                              }
                              final valorVal = double.tryParse(
                                _normDecimal(valorCtrl.text),
                              );
                              if (valorVal == null || valorVal <= 0) {
                                eValor = "Informe o valor total (> 0).";
                              }
                              if (eData != null ||
                                  eTipo != null ||
                                  eLitros != null ||
                                  eValor != null) {
                                setLocal(() {
                                  errData = eData;
                                  errTipo = eTipo;
                                  errLitros = eLitros;
                                  errValor = eValor;
                                });
                                return;
                              }

                              setLocal(() => busy = true);
                              final bdtId = ModalRoute.of(context)!
                                  .settings
                                  .arguments as int;

                              final data = <String, dynamic>{
                                "data_hora": dataHoraCtrl.text.trim(),
                                "tipo_combustivel": tipo,
                                "odometro_km": _normDecimal(odoCtrl.text),
                                "litros": _normDecimal(litrosCtrl.text),
                                "valor_total": _normDecimal(valorCtrl.text),
                                // Preço/litro só vai se preenchido —
                                // vazio => backend calcula automático.
                                "preco_unit":
                                    _normDecimal(precoUnitCtrl.text),
                                "nota_fiscal": notaCtrl.text.trim(),
                                "observacoes": obsCtrl.text.trim(),
                              };
                              data.removeWhere(
                                (k, v) =>
                                    v == null ||
                                    (v is String && v.trim().isEmpty),
                              );

                              final res = isEdit
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

                              if (res['success'] != true) {
                                // Mostra a mensagem REAL do backend
                                // (ex: "Selecione um tipo de combustível
                                // válido.", "Este BDT não tem veículo
                                // vinculado…"). Antes era msg genérica.
                                final msg = (res['message']?.toString().trim() ?? '');
                                setLocal(() {
                                  busy = false;
                                  formError = msg.isNotEmpty
                                      ? msg
                                      : 'Não foi possível salvar. Verifique os campos e tente de novo.';
                                });
                                return;
                              }

                              Navigator.pop(context);
                              ScaffoldMessenger.of(context)
                                ..clearSnackBars()
                                ..showSnackBar(
                                  const SnackBar(
                                    content: Text("Abastecimento salvo."),
                                  ),
                                );
                              await _load(bdtId);
                            },
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(
                        isEdit
                            ? "Salvar alterações"
                            : "Adicionar abastecimento",
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

  // =========================
  // CRUD Manutenções
  // =========================

  /// Banner de erro genérico (backend recusou / falha de rede) —
  /// mesmo padrão dos sheets de trecho e da NovaOcorrenciaPage.
  Widget _bannerErro(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.errorContainer,
      ),
      child: Text(
        msg,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _openManutencaoSheet({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final id = isEdit ? (int.tryParse(existing['id'].toString()) ?? 0) : 0;

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

    // Sprint W+M — validação inline. Backend mobile
    // (BdtApiService::criarManutencao) exige `descricao`; o `fk_tipo`
    // do web fica de fora aqui de propósito (o service passa
    // exigirTipo=false — nasce como "Não classificada", admin classifica
    // depois). Data de início também é required no backend web e útil
    // no mobile (senão vira `now()` implícito, o que confunde o admin).
    String? errInicio;
    String? errDesc;
    String? formError;
    bool busy = false;

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
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isEdit
                                ? "Editar manutenção"
                                : "Adicionar manutenção",
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (isEdit && id > 0)
                          IconButton(
                            tooltip: "Excluir",
                            onPressed: busy
                                ? null
                                : () async {
                                    final ok = await _confirmDelete(
                                      "Excluir esta manutenção?",
                                    );
                                    if (!ok) return;

                                    final bdtId = ModalRoute.of(context)!
                                        .settings
                                        .arguments as int;

                                    final delOk =
                                        await BdtService.excluirManutencao(
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
                    if (formError != null) ...[
                      _bannerErro(formError!),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: inicioCtrl,
                      readOnly: true,
                      enabled: !busy,
                      onTap: () async {
                        final picked = await _pickDateTimeString(
                          initial: inicioCtrl.text,
                        );
                        if (picked != null) {
                          inicioCtrl.text = picked;
                          if (errInicio != null) {
                            setLocal(() => errInicio = null);
                          }
                        }
                      },
                      decoration: InputDecoration(
                        labelText: "Início (data/hora) *",
                        border: const OutlineInputBorder(),
                        suffixIcon: const Icon(Icons.schedule),
                        errorText: errInicio,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: fimCtrl,
                      readOnly: true,
                      enabled: !busy,
                      onTap: () async {
                        final picked = await _pickDateTimeString(
                          initial: fimCtrl.text,
                        );
                        if (picked != null) fimCtrl.text = picked;
                      },
                      decoration: const InputDecoration(
                        labelText: "Fim (data/hora)",
                        border: OutlineInputBorder(),
                        helperText: "Opcional",
                        suffixIcon: Icon(Icons.schedule),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: odoCtrl,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_decimal1],
                      decoration: const InputDecoration(
                        labelText: "Odômetro (km)",
                        border: OutlineInputBorder(),
                        helperText: "Opcional",
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      enabled: !busy,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) {
                        if (errDesc != null) setLocal(() => errDesc = null);
                      },
                      decoration: InputDecoration(
                        labelText: "Descrição *",
                        helperText:
                            "Ex.: \"Troca de pneu traseiro direito\"",
                        border: const OutlineInputBorder(),
                        errorText: errDesc,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: houveGasto,
                      onChanged: busy
                          ? null
                          : (v) => setLocal(() => houveGasto = v),
                      title: const Text("Houve gasto?"),
                    ),
                    if (houveGasto) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: valorCtrl,
                        enabled: !busy,
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
                      enabled: !busy,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: "Observações",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              String? eIni;
                              String? eDesc;
                              if (inicioCtrl.text.trim().isEmpty) {
                                eIni = "Informe o início da manutenção.";
                              }
                              if (descCtrl.text.trim().isEmpty) {
                                eDesc =
                                    "Descreva rapidamente o que foi feito.";
                              }
                              if (eIni != null || eDesc != null) {
                                setLocal(() {
                                  errInicio = eIni;
                                  errDesc = eDesc;
                                  formError = null;
                                });
                                return;
                              }

                              setLocal(() => busy = true);
                              final bdtId = ModalRoute.of(context)!
                                  .settings
                                  .arguments as int;

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
                                    v == null ||
                                    (v is String && v.trim().isEmpty),
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

                              if (!ok) {
                                setLocal(() {
                                  busy = false;
                                  formError =
                                      "Não foi possível salvar. Verifique os campos e tente de novo.";
                                });
                                return;
                              }

                              Navigator.pop(context);
                              ScaffoldMessenger.of(context)
                                ..clearSnackBars()
                                ..showSnackBar(
                                  const SnackBar(
                                    content: Text("Manutenção salva."),
                                  ),
                                );
                              await _load(bdtId);
                            },
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(
                        isEdit
                            ? "Salvar alterações"
                            : "Adicionar manutenção",
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

    // Protocolo (ano/numero) em vez de ID interno. Se ainda não carregou
    // o payload, mostra só "BDT" — o carregamento é curto.
    final ok = payload != null && payload!['success'] == true;
    final bdtMap = ok ? (payload!['bdt'] as Map<String, dynamic>?) : null;
    final subtitle = bdtMap != null
        ? "BDT ${bdtMap['ano']}/${bdtMap['numero']}"
        : "BDT";

    // erro do backend
    if (payload != null && payload!['success'] != true) {
      final msg = (payload!['message'] ?? 'Erro ao carregar formulário.')
          .toString();
      return AppScaffold(
        title: "Formulário do BDT",
        subtitle: subtitle,
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
      subtitle: subtitle,
      onRefresh: () => _load(bdtId),
      body: (payload == null)
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
              children: [
                _cardMarcosJornada(bdtId),
                const SizedBox(height: 12),

                // ✅ sem trechos aqui
                _cardAbastecimentos(),
                const SizedBox(height: 12),

                _cardManutencoes(),
                const SizedBox(height: 12),

                _cardOcorrencias(bdtId),
              ],
            ),
    );
  }

  // =========================
  // Cards
  // =========================

  Widget _cardMarcosJornada(int bdtId) {
    final marcos = <String>[
      'partida',
      'apresentacao',
      'embarque_passageiro',
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Marcos da Jornada",
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              _bdtPermiteMarcos
                  ? "Registre cada marco no momento em que ocorrer. A ordem é obrigatória."
                  : "O BDT precisa estar Em andamento ou Reaberto para registrar marcos.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < marcos.length; i++) ...[
              _rowMarco(bdtId, marcos[i]),
              if (i < marcos.length - 1) const Divider(height: 18),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rowMarco(int bdtId, String marco) {
    final dh = _marcoDatahora[marco];
    final autor = _marcoAutor[marco];
    final jaRegistrado = dh != null && dh.isNotEmpty;
    final emProgresso = _registrandoMarco == marco;
    final liberado = _marcoPodeRegistrar(marco);
    final svg = _marcoAssinaturaSvg[marco];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              _marcoIcone[marco],
              size: 28,
              color: jaRegistrado
                  ? Colors.green
                  : (liberado
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).disabledColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _marcoLabel[marco] ?? marco,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    jaRegistrado
                        ? "${_fmtDatahoraBr(dh)}${(autor != null && autor.isNotEmpty) ? ' • $autor' : ''}"
                        : (liberado ? "Aguardando registro" : "Bloqueado"),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (jaRegistrado)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.check_circle, color: Colors.green),
              )
            else
              FilledButton.tonalIcon(
                onPressed: (emProgresso || !liberado)
                    ? null
                    : () => _registrarMarco(bdtId, marco),
                icon: emProgresso
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow, size: 18),
                label: const Text("Registrar"),
              ),
          ],
        ),
        if (jaRegistrado && svg != null && svg.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            // Alinha com o texto (pula ícone 28 + gap 12).
            padding: const EdgeInsets.only(left: 40),
            child: AssinaturaViewButton(
              svg: svg,
              marcoLabel: _marcoLabel[marco] ?? marco,
              assinadoPor: autor,
              signatarioTipo: _marcoSignatarioTipo[marco],
              dataHora: dh,
              observacao: _marcoObservacao[marco],
              onEditar: _bdtPermiteMarcos
                  ? () => _reassinarMarco(bdtId, marco)
                  : null,
            ),
          ),
        ],
      ],
    );
  }

  bool _marcoPodeRegistrar(String marco) {
    return _bdtPermiteMarcos && _marcoLiberado(marco);
  }

  /// "2026-05-13 14:30:00" → "13/05/2026 14:30".
  /// Aceita também ISO "2026-05-13T14:30:00".
  String _fmtDatahoraBr(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final norm = raw.replaceFirst('T', ' ');
    final dt = DateTime.tryParse(norm);
    if (dt == null) return raw;
    return "${_two(dt.day)}/${_two(dt.month)}/${dt.year} "
        "${_two(dt.hour)}:${_two(dt.minute)}";
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

  /// Sprint W+M (Sprint 17 web F2) — card de ocorrências do BDT.
  /// Substitui o `_cardAcidentesPlaceholder` antigo, que era só um
  /// placeholder especulativo. Estrutura correta do Formulário do BDT
  /// é Abastecimentos + Manutenções + Ocorrências (não "Acidentes" —
  /// acidente/sinistro é apenas UM dos tipos de ocorrência).
  ///
  /// Sem lista aqui por ora — o painel institucional já mostra tudo
  /// em Menu → Ferramentas → Histórico de ocorrências. Ação primária
  /// é REGISTRAR (mesmo botão do sheet "Ações" da BdtPage — dois
  /// pontos de entrada é intencional pra reduzir cliques).
  Widget _cardOcorrencias(int bdtId) {
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
                    "Ocorrências",
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await Navigator.pushNamed(
                      context,
                      '/ocorrencia/nova',
                      arguments: bdtId,
                    );
                    if (ok == true && mounted) {
                      // ignore: discarded_futures
                      _load(bdtId);
                    }
                  },
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text("Registrar"),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "Avaria, atraso, sinistro, desvio de itinerário… "
              "O histórico completo fica em Menu → Ferramentas → "
              "Histórico de ocorrências.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

}
