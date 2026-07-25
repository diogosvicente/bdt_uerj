import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/abastecimento_foto_service.dart';
import '../services/bdt_service.dart';
import '../services/carga_service.dart';
import '../services/divergencia_service.dart';
import '../services/foto_documento_client.dart' show FotoDocumentoRef;
import '../services/manutencao_foto_service.dart';
import '../services/ocorrencia_service.dart';
import '../utils/date_fmt.dart';
import 'nova_ocorrencia_page.dart' show OcorrenciaFormArgs;
import 'registro_bdt_detalhe_page.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/foto_documento_thumb.dart';
import '../widgets/fotos_bdt_section.dart';

class BdtFormPage extends StatefulWidget {
  const BdtFormPage({super.key});

  @override
  State<BdtFormPage> createState() => _BdtFormPageState();
}

class _BdtFormPageState extends State<BdtFormPage> {
  Map<String, dynamic>? payload;

  bool _loadedOnce = false;

  // ====== listas operacionais (sem trechos aqui) ======
  //
  // Sprint MUX (2026-07-24): o card "Marcos da Jornada" que vivia aqui
  // foi REMOVIDO — era duplicata incompleta (só 3/4 marcos, sem
  // assinatura M4). A versão canônica está em ValidacaoInicioPage
  // (`/validacao/inicio`, acessível pelo sheet "Ações" do BdtPage).
  List<Map<String, dynamic>> abastecimentos = [];
  List<Map<String, dynamic>> manutencoes = [];
  // Sprint 18.1 — ocorrencias deste BDT (não é o histórico institucional).
  List<OcorrenciaDoBdt> ocorrencias = [];
  // Sprint 6 W+M — divergências de carga registradas pelo condutor.
  List<DivergenciaResumo> divergencias = [];
  // Sprint 6 W+M — carga DECLARADA pela(s) solicitação(ões) vinculadas
  // ao BDT (leitura). Pode ter mais de uma se o BDT atende múltiplas
  // solicitações. Serve de referência quando condutor chega no destino.
  List<CargaDoBdt> cargas = [];

  // Sprint 18.2 — fotos por registro (populadas em paralelo no _load).
  // Chave = id do registro; valor = lista de refs (id + mime + descricao).
  // Usadas pras tiras de miniaturas nos cards + galeria full-screen.
  Map<int, List<FotoDocumentoRef>> _fotosAbastecimento = {};
  Map<int, List<FotoDocumentoRef>> _fotosManutencao   = {};
  Map<int, List<FotoDocumentoRef>> _fotosOcorrencia   = {};
  Map<int, List<FotoDocumentoRef>> _fotosDivergencia  = {};

  // ====== input formatters ======
  final _decimal2 = FilteringTextInputFormatter.allow(
    RegExp(r'^\d*([.,]\d{0,2})?$'),
  );
  final _decimal1 = FilteringTextInputFormatter.allow(
    RegExp(r'^\d*([.,]\d{0,1})?$'),
  );

  @override
  void dispose() {
    super.dispose();
  }

  // =========================
  // helpers
  // =========================

  /// Sprint 18 W+M — image_picker compartilhado entre as sheets
  /// (abastecimento e manutenção). Instância única evita reabrir plugin
  /// nativo a cada toque de chip.
  final ImagePicker _picker = ImagePicker();

  /// Bottom-sheet Câmera vs Galeria. Retorna a fonte escolhida ou null
  /// se o usuário cancelou. Padrão idêntico à nova_ocorrencia_page.
  Future<ImageSource?> _perguntarFonteFoto() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  /// Backend às vezes devolve o id como int, string ou dentro de `data`.
  /// Aceita as 3 formas — retorna 0 se nada bater.
  int _parseIntFlex(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    if (v is num) return v.toInt();
    return 0;
  }

  /// Icone visual pro chip de subtipo — melhora leitura da botoeira.
  /// Se o admin renomear/criar novos, cai no default (foto genérica).
  IconData _iconeSubtipoAbastecimento(String nome) {
    final n = nome.toLowerCase();
    if (n.contains('odô') || n.contains('odo')) return Icons.speed;
    if (n.contains('bomba')) return Icons.local_gas_station;
    if (n.contains('tanque')) return Icons.propane_tank_outlined;
    if (n.contains('cartão') || n.contains('cartao')) return Icons.credit_card;
    if (n.contains('nota')) return Icons.receipt_long;
    return Icons.photo_camera;
  }

  /// Pega foto (via camera/galeria) — retorna XFile ou null.
  Future<XFile?> _pickFoto() async {
    final source = await _perguntarFonteFoto();
    if (source == null) return null;
    try {
      return _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 82,
      );
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao acessar câmera/galeria: $e')),
      );
      return null;
    }
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  /// Sprint MSEC.TZ — envia sempre ISO UTC pro backend, que aceita via
  /// `api_parse_datetime_utc`. Antes: naive "yyyy-mm-dd HH:MM:00" era
  /// interpretado como BRT wall-clock; agora o "Z" no fim explicita UTC.
  String _fmtApiDateTime(DateTime dt) => DateFmt.apiIsoUtc(dt);

  String _normDecimal(String s) => s.trim().replaceAll(',', '.');

  Future<String?> _pickDateTimeString({String? initial}) async {
    DateTime base = DateTime.now();
    if (initial != null && initial.trim().isNotEmpty) {
      // Sprint MSEC.TZ — backend agora emite `Y-m-d H:i:s` em UTC. Se veio
      // sem "Z"/offset, tratar como UTC (novo padrao) antes de exibir em local.
      final raw = initial.trim();
      final hasTz = raw.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);
      final norm = hasTz
          ? raw.replaceFirst(' ', 'T')
          : '${raw.replaceFirst(' ', 'T')}Z';
      final parsed = DateTime.tryParse(norm);
      if (parsed != null) base = parsed.toLocal();
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

    // Sprint MUX (2026-07-24) — Marcos da Jornada (state + fetch de
    // /jornada/estado + estadoJornada) foram removidos daqui. Vivem em
    // ValidacaoInicioPage, que tem a versão canônica com assinatura M4.
    // Ver comentário na declaração do state.

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
    // Sprint 18.1 — ocorrências não vêm no `detalhes`, sempre chama.
    final ocResolved = await OcorrenciaService.listarDoBdt(bdtId);
    // Sprint 6 W+M — divergências (motor W10).
    final divResolved = await DivergenciaService.listarDoBdt(bdtId);
    // Sprint 6 W+M — carga declarada (leitura).
    final cargasResolved = await CargaService.listar(bdtId);

    if (!mounted) return;
    setState(() {
      abastecimentos = abResolved;
      manutencoes = manResolved;
      ocorrencias = ocResolved;
      divergencias = divResolved;
      cargas = cargasResolved;
    });

    // Sprint 18.2 — fotos por registro, em paralelo. Não bloqueia o
    // primeiro render — quando chega, faz setState e as tiras aparecem.
    // Cache é resetado a cada _load pra refletir exclusões/uploads
    // que aconteceram enquanto o usuário mexia no form.
    _carregarFotosDosRegistros(
      abIds: abResolved
          .map((a) => int.tryParse('${a['id'] ?? 0}') ?? 0)
          .where((i) => i > 0)
          .toList(),
      mnIds: manResolved
          .map((m) => int.tryParse('${m['id'] ?? 0}') ?? 0)
          .where((i) => i > 0)
          .toList(),
      ocIds: ocResolved
          .where((o) => o.qtdFotos > 0)
          .map((o) => o.id)
          .toList(),
      divIds: divResolved
          .where((d) => d.qtdFotos > 0)
          .map((d) => d.id)
          .toList(),
    );
  }

  Future<void> _carregarFotosDosRegistros({
    required List<int> abIds,
    required List<int> mnIds,
    required List<int> ocIds,
    required List<int> divIds,
  }) async {
    // Zera antes de recarregar (evita mostrar refs de registros deletados).
    if (mounted) {
      setState(() {
        _fotosAbastecimento = {};
        _fotosManutencao   = {};
        _fotosOcorrencia   = {};
        _fotosDivergencia  = {};
      });
    }

    final futures = <Future<void>>[
      for (final id in abIds)
        AbastecimentoFotoService.listar(id).then((refs) {
          if (!mounted) return;
          setState(() => _fotosAbastecimento[id] = refs);
        }),
      for (final id in mnIds)
        ManutencaoFotoService.listar(id).then((refs) {
          if (!mounted) return;
          setState(() => _fotosManutencao[id] = refs);
        }),
      for (final id in ocIds)
        OcorrenciaService.listarFotos(id).then((refs) {
          if (!mounted) return;
          setState(() => _fotosOcorrencia[id] = refs
              .map((r) => FotoDocumentoRef(
                    id: r.id,
                    mimeType: r.mimeType,
                    createdAt: r.createdAt,
                  ))
              .toList());
        }),
      for (final id in divIds)
        DivergenciaService.listarFotos(id).then((refs) {
          if (!mounted) return;
          setState(() => _fotosDivergencia[id] = refs);
        }),
    ];
    await Future.wait(futures);
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

    // Sprint 18 W+M — Fotos.
    // - `tiposFotoFuture`: catalogo do backend com fallback local (nunca vazio).
    // - `fotosPendentes`: escolhidas na sheet, ainda em memoria.
    //   Sobem em sequencia APOS criar/atualizar o abastecimento.
    // - `fotosExistentes`: so em edicao — vem do endpoint /listar.
    List<Map<String, dynamic>> tiposFoto = const [];
    final tiposFotoFuture = AbastecimentoFotoService.listarTiposFoto()
        .then((v) => tiposFoto = v);
    final List<FotoPendente> fotosPendentes = [];
    final List<FotoExistente> fotosExistentes = [];
    if (isEdit && id > 0) {
      // ignore: discarded_futures
      AbastecimentoFotoService.listar(id).then((refs) {
        fotosExistentes
          ..clear()
          ..addAll(refs.map((r) => FotoExistente(
                docId: r.id,
                label: (r.descricao?.trim().isNotEmpty ?? false)
                    ? r.descricao!
                    : 'Foto',
                fetcher: (docId) =>
                    AbastecimentoFotoService.obter(docId, abastecimentoId: id),
                cacheNamespace: 'abastecimento_$id',
              )));
      });
    }

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
                          // Key varia quando a lista chega (0 → N items). Sem
                          // essa reconstrução, DropdownButtonFormField mantém
                          // o estado interno criado no primeiro build (items
                          // vazios) e ignora o snap.data que aparece depois —
                          // por isso o menu abria vazio no emulador enquanto
                          // o backend já tinha respondido 200.
                          key: ValueKey('tipoCombustivel-${items.length}'),
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
                              labelText: "Hodômetro (km)",
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
                        labelText: "Nota fiscal (número/série)",
                        helperText: "Foto/PDF da NF vai na seção de fotos abaixo.",
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

                    // Sprint 18 W+M — Fotos do abastecimento.
                    // Botoeira por tipo (Odômetro/Bomba/Tanque/Cartão/Outros)
                    // + botão destacado "Nota Fiscal" (mesmo endpoint, com
                    // flag is_nota_fiscal — backend rota pra salvarNotaFiscal).
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: tiposFotoFuture,
                      builder: (context, snap) {
                        final catalogo = snap.data ?? tiposFoto;
                        final loading =
                            snap.connectionState != ConnectionState.done &&
                                catalogo.isEmpty;
                        if (loading) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                                SizedBox(width: 10),
                                Text('Carregando tipos de foto…'),
                              ],
                            ),
                          );
                        }
                        return FotosBdtSection(
                          titulo: 'Fotos do abastecimento',
                          busy: busy,
                          chips: [
                            for (final t in catalogo)
                              FotoTipoChip(
                                tipoId: t['id'] as int?,
                                label: (t['nome'] ?? '').toString(),
                                icone: _iconeSubtipoAbastecimento(
                                    (t['nome'] ?? '').toString()),
                              ),
                          ],
                          chipDestaque: const FotoTipoChip(
                            isNotaFiscal: true,
                            label: 'Nota Fiscal',
                            icone: Icons.receipt_long,
                          ),
                          pendentes: fotosPendentes,
                          existentes: fotosExistentes,
                          onAdicionar: (chip) async {
                            final f = await _pickFoto();
                            if (f == null) return;
                            setLocal(() =>
                                fotosPendentes.add(FotoPendente(file: f, tipo: chip)));
                          },
                          onRemoverPendente: (i) => setLocal(() {
                            if (i >= 0 && i < fotosPendentes.length) {
                              fotosPendentes.removeAt(i);
                            }
                          }),
                          onExcluirExistente: (foto) async {
                            if (!isEdit || id <= 0) return;
                            final ok = await AbastecimentoFotoService.excluir(
                              foto.docId,
                              abastecimentoId: id,
                            );
                            if (!ok) return;
                            FotoDocumentoThumb.invalidate(
                              cacheNamespace: foto.cacheNamespace,
                              docId: foto.docId,
                            );
                            setLocal(() => fotosExistentes
                                .removeWhere((e) => e.docId == foto.docId));
                          },
                        );
                      },
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

                              // Sprint 18 W+M — sobe as fotos pendentes DEPOIS
                              // de o registro existir. Em criação, o id vem do
                              // response. Sequencial pra manter ordem visual e
                              // simplificar tratamento de erro parcial.
                              //
                              // Backend BdtApiController::ok() faz array_merge
                              // no TOPO — a chave vem em res['abastecimento_id'],
                              // NÃO em res['data']['abastecimento_id'].
                              final absIdFinal = isEdit
                                  ? id
                                  : _parseIntFlex(res['abastecimento_id']);

                              int fotosOk = 0;
                              int fotosErr = 0;
                              if (absIdFinal > 0) {
                                for (final p in fotosPendentes) {
                                  final bytes = await p.file.readAsBytes();
                                  final docId = await AbastecimentoFotoService
                                      .upload(
                                    abastecimentoId: absIdFinal,
                                    bytes: bytes,
                                    filename: p.file.name.isNotEmpty
                                        ? p.file.name
                                        : 'foto_${DateTime.now().millisecondsSinceEpoch}.jpg',
                                    tipoFotoId: p.tipo.tipoId,
                                    isNotaFiscal: p.tipo.isNotaFiscal,
                                  );
                                  if (docId > 0) {
                                    fotosOk++;
                                  } else {
                                    fotosErr++;
                                  }
                                }
                              }

                              if (!context.mounted) return;
                              Navigator.pop(context);
                              final msgFotos = fotosPendentes.isEmpty
                                  ? ''
                                  : fotosErr == 0
                                      ? ' ($fotosOk foto(s) enviada(s))'
                                      : ' — $fotosOk foto(s) OK, $fotosErr falhou(aram)';
                              ScaffoldMessenger.of(context)
                                ..clearSnackBars()
                                ..showSnackBar(
                                  SnackBar(
                                    content: Text("Abastecimento salvo.$msgFotos"),
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

    // Sprint 18 W+M — Fotos (fase Antes / Depois).
    // NAO tem catalogo dinamico: as fases sao fixas no backend
    // (FOTO_VISTORIA_ANTES/DEPOIS). Se um dia o admin pedir subtipos
    // configuraveis, aqui muda pra fetch + FutureBuilder — igual ao
    // abastecimento.
    final List<FotoPendente> fotosPendentes = [];
    final List<FotoExistente> fotosExistentes = [];
    if (isEdit && id > 0) {
      // ignore: discarded_futures
      ManutencaoFotoService.listar(id).then((refs) {
        fotosExistentes
          ..clear()
          ..addAll(refs.map((r) {
            // Backend expõe fk_tipo (id de doc_tipos). Usamos ele pra
            // decidir "Antes" vs "Depois" — se por algum motivo faltar,
            // recorre à descricao (fallback). Nomes vindos de DocTiposModel
            // no web: FOTO_VISTORIA_ANTES / FOTO_VISTORIA_DEPOIS.
            final desc = (r.descricao ?? '').toLowerCase();
            final label = desc.contains('antes')
                ? 'Antes'
                : desc.contains('depois')
                    ? 'Depois'
                    : 'Foto';
            return FotoExistente(
              docId: r.id,
              label: label,
              fetcher: (docId) =>
                  ManutencaoFotoService.obter(docId, manutencaoId: id),
              cacheNamespace: 'manutencao_$id',
            );
          }));
      });
    }

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

                    // Sprint 18 W+M — Fotos de vistoria (Antes / Depois).
                    // 2 chips fixos — a discriminação vive no fk_tipo do
                    // backend (FOTO_VISTORIA_ANTES/DEPOIS), não em texto.
                    FotosBdtSection(
                      titulo: 'Fotos de vistoria',
                      busy: busy,
                      chips: const [
                        FotoTipoChip(
                          fase: 'antes',
                          label: 'Antes',
                          icone: Icons.build_circle_outlined,
                        ),
                        FotoTipoChip(
                          fase: 'depois',
                          label: 'Depois',
                          icone: Icons.check_circle_outline,
                        ),
                      ],
                      pendentes: fotosPendentes,
                      existentes: fotosExistentes,
                      onAdicionar: (chip) async {
                        final f = await _pickFoto();
                        if (f == null) return;
                        setLocal(() =>
                            fotosPendentes.add(FotoPendente(file: f, tipo: chip)));
                      },
                      onRemoverPendente: (i) => setLocal(() {
                        if (i >= 0 && i < fotosPendentes.length) {
                          fotosPendentes.removeAt(i);
                        }
                      }),
                      onExcluirExistente: (foto) async {
                        if (!isEdit || id <= 0) return;
                        final ok = await ManutencaoFotoService.excluir(
                          foto.docId,
                          manutencaoId: id,
                        );
                        if (!ok) return;
                        FotoDocumentoThumb.invalidate(
                          cacheNamespace: foto.cacheNamespace,
                          docId: foto.docId,
                        );
                        setLocal(() => fotosExistentes
                            .removeWhere((e) => e.docId == foto.docId));
                      },
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

                              final res = isEdit
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

                              if (res['success'] != true) {
                                final msg =
                                    (res['message']?.toString().trim() ?? '');
                                setLocal(() {
                                  busy = false;
                                  formError = msg.isNotEmpty
                                      ? msg
                                      : "Não foi possível salvar. Verifique os campos e tente de novo.";
                                });
                                return;
                              }

                              // Sprint 18 W+M — sobe fotos pendentes.
                              // Backend retorna o id no TOPO (ok() faz merge).
                              final mntIdFinal = isEdit
                                  ? id
                                  : _parseIntFlex(res['manutencao_id']);
                              int fotosOk = 0;
                              int fotosErr = 0;
                              if (mntIdFinal > 0) {
                                for (final p in fotosPendentes) {
                                  final bytes = await p.file.readAsBytes();
                                  final docId =
                                      await ManutencaoFotoService.upload(
                                    manutencaoId: mntIdFinal,
                                    bytes: bytes,
                                    filename: p.file.name.isNotEmpty
                                        ? p.file.name
                                        : 'foto_${DateTime.now().millisecondsSinceEpoch}.jpg',
                                    fase: p.tipo.fase ?? 'antes',
                                  );
                                  if (docId > 0) {
                                    fotosOk++;
                                  } else {
                                    fotosErr++;
                                  }
                                }
                              }

                              if (!context.mounted) return;
                              Navigator.pop(context);
                              final msgFotos = fotosPendentes.isEmpty
                                  ? ''
                                  : fotosErr == 0
                                      ? ' ($fotosOk foto(s) enviada(s))'
                                      : ' — $fotosOk foto(s) OK, $fotosErr falhou(aram)';
                              ScaffoldMessenger.of(context)
                                ..clearSnackBars()
                                ..showSnackBar(
                                  SnackBar(
                                    content: Text("Manutenção salva.$msgFotos"),
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

  /// Sprint MUX (2026-07-24) — abre a page compartilhada de detalhes.
  /// Substituiu a tira de miniaturas in-line que poluía os cards.
  /// Retorna true se a page detalhe fechou com edição/exclusão
  /// bem-sucedida — o caller usa pra recarregar a lista.
  Future<bool> _abrirDetalheRegistro(RegistroBdtDetalheArgs args) async {
    final r = await Navigator.pushNamed(
      context,
      '/registro/detalhe',
      arguments: args,
    );
    return r == true;
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
                // Sprint MUX (2026-07-24) — Marcos da Jornada removidos
                // daqui. Estão em ValidacaoInicioPage (canônica, com
                // assinatura M4), acessível pelo sheet "Ações" do BdtPage.

                // Sprint 6 W+M (2026-07-25) — Carga declarada (leitura).
                // Some se o BDT não tem carga em nenhuma solicitação —
                // maioria dos BDTs comuns de intercâmpi de pessoas.
                if (cargas.isNotEmpty) ...[
                  _cardCargaDeclarada(bdtId),
                  const SizedBox(height: 12),
                ],
                _cardAbastecimentos(),
                const SizedBox(height: 12),

                _cardManutencoes(),
                const SizedBox(height: 12),

                _cardOcorrencias(bdtId),
                const SizedBox(height: 12),

                _cardDivergencias(bdtId),
              ],
            ),
    );
  }

  // =========================
  // Cards
  // =========================

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

                  final dhFmt = DateFmt.dataHoraBr(dh);
                  final absId = int.tryParse('${a['id'] ?? 0}') ?? 0;
                  final fotosQtd = (_fotosAbastecimento[absId] ?? const []).length;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      "${tipo.isEmpty ? 'Combustível' : tipo} • ${litros.isEmpty ? '-' : litros} L • ${valor.isEmpty ? '-' : valor}",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: dhFmt.isEmpty ? null : Text(dhFmt),
                    trailing: _acoesDoRegistro(
                      qtdFotos: fotosQtd,
                      onVer: () => _verAbastecimento(a),
                      onEditar: () => _openAbastecimentoSheet(existing: a),
                      onExcluir: () => _excluirAbastecimento(a),
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

                  final iniFmt = DateFmt.dataHoraBr(ini);
                  final mntId = int.tryParse('${m['id'] ?? 0}') ?? 0;
                  final fotosQtd = (_fotosManutencao[mntId] ?? const []).length;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      desc.isEmpty ? "Manutenção" : desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: iniFmt.isEmpty ? null : Text(iniFmt),
                    trailing: _acoesDoRegistro(
                      qtdFotos: fotosQtd,
                      onVer: () => _verManutencao(m),
                      onEditar: () => _openManutencaoSheet(existing: m),
                      onExcluir: () => _excluirManutencao(m),
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
                  onPressed: () => _abrirFormOcorrencia(bdtId: bdtId),
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text("Adicionar"),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (ocorrencias.isEmpty)
              Text(
                "Nenhuma ocorrência registrada. "
                "Avaria, atraso, sinistro, desvio de itinerário…",
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: ocorrencias.length,
                separatorBuilder: (_, __) => const Divider(height: 0),
                itemBuilder: (_, i) => _tileOcorrencia(bdtId, ocorrencias[i]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tileOcorrencia(int bdtId, OcorrenciaDoBdt o) {
    final subtitle = <String>[];
    if ((o.tipoNome ?? '').isNotEmpty) subtitle.add(o.tipoNome!);
    final dhFmt = DateFmt.dataHoraBr(o.dataHora);
    if (dhFmt.isNotEmpty) subtitle.add(dhFmt);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.warning_amber_rounded,
          color: Color(0xFFB58900)),
      title: Text(
        (o.titulo?.trim().isNotEmpty ?? false) ? o.titulo! : 'Ocorrência',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle.join(' • '),
              maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: _acoesDoRegistro(
        qtdFotos: o.qtdFotos,
        onVer: () => _verOcorrencia(bdtId, o),
        onEditar: () => _abrirFormOcorrencia(bdtId: bdtId, existente: o),
        onExcluir: () => _excluirOcorrencia(bdtId, o),
      ),
    );
  }

  /// Sprint MUX (2026-07-24) — trailing padronizado com 3 botões
  /// (Ver / Editar / Excluir) + badge opcional de quantidade de fotos.
  /// Reusado por Abastecimento, Manutenção e Ocorrência pra evitar
  /// divergência visual entre os 3 cards do BDT.
  Widget _acoesDoRegistro({
    required int qtdFotos,
    required VoidCallback onVer,
    required VoidCallback onEditar,
    required VoidCallback onExcluir,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (qtdFotos > 0) ...[
          const Icon(Icons.photo_library_outlined,
              size: 14, color: Colors.black54),
          const SizedBox(width: 2),
          Text('$qtdFotos',
              style:
                  const TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(width: 4),
        ],
        IconButton(
          tooltip: 'Ver detalhes',
          icon: const Icon(Icons.visibility_outlined, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: onVer,
        ),
        IconButton(
          tooltip: 'Editar',
          icon: const Icon(Icons.edit, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: onEditar,
        ),
        IconButton(
          tooltip: 'Excluir',
          icon: const Icon(Icons.delete_outline, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: onExcluir,
        ),
      ],
    );
  }

  Future<void> _abrirFormOcorrencia({
    required int bdtId,
    OcorrenciaDoBdt? existente,
  }) async {
    final args = OcorrenciaFormArgs(
      bdtId: bdtId,
      ocorrenciaId: existente?.id,
      tituloInicial: existente?.titulo,
      descricaoInicial: existente?.descricao,
      tipoInicial: existente?.fkOcorrenciaTipo,
      dataHoraInicial: existente?.dataHora,
    );
    final ok = await Navigator.pushNamed(
      context,
      '/ocorrencia/nova',
      arguments: args,
    );
    if (ok == true && mounted) {
      // ignore: discarded_futures
      _load(bdtId);
    }
  }

  Future<void> _excluirOcorrencia(int bdtId, OcorrenciaDoBdt o) async {
    final ok = await _confirmDelete(
      "Excluir a ocorrência\n\"${o.titulo ?? "Sem título"}\"?",
    );
    if (!ok) return;
    final done = await OcorrenciaService.excluir(o.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(done ? "Ocorrência excluída." : "Falha ao excluir."),
      ));
    if (done) await _load(bdtId);
  }

  // =========================================================================
  // Sprint MUX (2026-07-24) — Ver detalhes / Excluir (Abast + Manut)
  // =========================================================================

  /// Monta [RegistroBdtDetalheArgs] pra Abastecimento e abre a page
  /// compartilhada. Callbacks de Editar/Excluir reusam os handlers
  /// da sheet existente.
  Future<void> _verAbastecimento(Map<String, dynamic> a) async {
    final bdtId = ModalRoute.of(context)!.settings.arguments as int;
    final absId = int.tryParse('${a['id'] ?? 0}') ?? 0;
    final fotos = _fotosAbastecimento[absId] ?? const [];

    final tipo = (a['tipo_combustivel'] ?? '').toString();
    final litros = (a['litros'] ?? '').toString();
    final valorTotal = (a['valor_total'] ?? '').toString();
    final precoUnit = (a['preco_unit'] ?? '').toString();
    final odo = (a['odometro_km'] ?? '').toString();
    final nf = (a['nota_fiscal'] ?? '').toString();
    final obs = (a['observacoes'] ?? '').toString();
    final dhFmt = DateFmt.dataHoraBr((a['data_hora'] ?? '').toString());

    final linhas = <RegistroBdtLinha>[
      if (tipo.isNotEmpty)
        RegistroBdtLinha(icone: Icons.local_gas_station, label: 'Combustível', valor: tipo),
      if (litros.isNotEmpty)
        RegistroBdtLinha(icone: Icons.opacity, label: 'Litros', valor: '$litros L'),
      if (valorTotal.isNotEmpty)
        RegistroBdtLinha(icone: Icons.attach_money, label: 'Valor total', valor: 'R\$ $valorTotal'),
      if (precoUnit.isNotEmpty)
        RegistroBdtLinha(icone: Icons.price_change, label: 'Preço/litro', valor: 'R\$ $precoUnit'),
      if (odo.isNotEmpty)
        RegistroBdtLinha(icone: Icons.speed, label: 'Hodômetro', valor: '$odo km'),
      if (nf.isNotEmpty)
        RegistroBdtLinha(icone: Icons.receipt_long, label: 'Nota fiscal', valor: nf),
    ];

    final args = RegistroBdtDetalheArgs(
      tituloAppBar: 'Abastecimento',
      subtituloAppBar: 'BDT #$bdtId',
      icone: Icons.local_gas_station,
      tituloRegistro: tipo.isEmpty ? 'Abastecimento' : tipo,
      dataHoraBr: dhFmt,
      linhas: linhas,
      observacoes: obs,
      fotos: fotos,
      fotoFetcher: (docId) =>
          AbastecimentoFotoService.obter(docId, abastecimentoId: absId),
      tituloGaleria: 'Abastecimento',
      onEditar: (_) async {
        await _openAbastecimentoSheet(existing: a);
        return true;
      },
      onExcluir: (_) => _excluirAbastecimento(a, confirmar: true),
    );

    final r = await _abrirDetalheRegistro(args);
    if (r && mounted) await _load(bdtId);
  }

  Future<bool> _excluirAbastecimento(
    Map<String, dynamic> a, {
    bool confirmar = true,
  }) async {
    if (confirmar) {
      final ok = await _confirmDelete("Excluir este abastecimento?");
      if (!ok) return false;
    }
    final bdtId = ModalRoute.of(context)!.settings.arguments as int;
    final absId = int.tryParse('${a['id'] ?? 0}') ?? 0;
    final done = await BdtService.excluirAbastecimento(
      bdtId: bdtId,
      abastecimentoId: absId,
    );
    if (!mounted) return false;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(done ? "Abastecimento excluído." : "Falha ao excluir."),
      ));
    if (done) await _load(bdtId);
    return done;
  }

  Future<void> _verManutencao(Map<String, dynamic> m) async {
    final bdtId = ModalRoute.of(context)!.settings.arguments as int;
    final mntId = int.tryParse('${m['id'] ?? 0}') ?? 0;
    final fotos = _fotosManutencao[mntId] ?? const [];

    final desc = (m['descricao'] ?? '').toString();
    final ini = DateFmt.dataHoraBr((m['data_hora_inicio'] ?? '').toString());
    final fim = DateFmt.dataHoraBr((m['data_hora_fim'] ?? '').toString());
    final odo = (m['odometro_km'] ?? '').toString();
    final houveGasto = m['houve_gasto'] == true || m['houve_gasto'] == 1;
    final valor = (m['valor_gasto'] ?? '').toString();
    final obs = (m['observacoes'] ?? '').toString();

    final linhas = <RegistroBdtLinha>[
      RegistroBdtLinha(
        icone: Icons.play_circle_outline,
        label: 'Início',
        valor: ini.isEmpty ? '—' : ini,
      ),
      RegistroBdtLinha(
        icone: Icons.stop_circle_outlined,
        label: 'Fim',
        valor: fim.isEmpty ? '—' : fim,
      ),
      if (odo.isNotEmpty)
        RegistroBdtLinha(icone: Icons.speed, label: 'Hodômetro', valor: '$odo km'),
      RegistroBdtLinha(
        icone: houveGasto ? Icons.attach_money : Icons.money_off,
        label: 'Gasto',
        valor: houveGasto
            ? (valor.isEmpty ? 'Sim (valor não informado)' : 'R\$ $valor')
            : 'Sem gasto',
      ),
    ];

    final args = RegistroBdtDetalheArgs(
      tituloAppBar: 'Manutenção',
      subtituloAppBar: 'BDT #$bdtId',
      icone: Icons.build,
      tituloRegistro: desc.isEmpty ? 'Manutenção' : desc,
      dataHoraBr: ini,
      linhas: linhas,
      observacoes: obs,
      fotos: fotos,
      fotoFetcher: (docId) =>
          ManutencaoFotoService.obter(docId, manutencaoId: mntId),
      tituloGaleria: 'Manutenção',
      onEditar: (_) async {
        await _openManutencaoSheet(existing: m);
        return true;
      },
      onExcluir: (_) => _excluirManutencao(m, confirmar: true),
    );

    final r = await _abrirDetalheRegistro(args);
    if (r && mounted) await _load(bdtId);
  }

  Future<bool> _excluirManutencao(
    Map<String, dynamic> m, {
    bool confirmar = true,
  }) async {
    if (confirmar) {
      final ok = await _confirmDelete("Excluir esta manutenção?");
      if (!ok) return false;
    }
    final bdtId = ModalRoute.of(context)!.settings.arguments as int;
    final mntId = int.tryParse('${m['id'] ?? 0}') ?? 0;
    final done = await BdtService.excluirManutencao(
      bdtId: bdtId,
      manutencaoId: mntId,
    );
    if (!mounted) return false;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(done ? "Manutenção excluída." : "Falha ao excluir."),
      ));
    if (done) await _load(bdtId);
    return done;
  }

  Future<void> _verOcorrencia(int bdtId, OcorrenciaDoBdt o) async {
    final fotos = _fotosOcorrencia[o.id] ?? const [];
    final dhFmt = DateFmt.dataHoraBr(o.dataHora);
    final linhas = <RegistroBdtLinha>[
      if ((o.tipoNome ?? '').isNotEmpty)
        RegistroBdtLinha(icone: Icons.category, label: 'Tipo', valor: o.tipoNome!),
    ];

    final args = RegistroBdtDetalheArgs(
      tituloAppBar: 'Ocorrência',
      subtituloAppBar: 'BDT #$bdtId',
      icone: Icons.warning_amber_rounded,
      corCabecalho: const Color(0xFFFFF3CD),
      tituloRegistro:
          (o.titulo?.trim().isNotEmpty ?? false) ? o.titulo! : 'Ocorrência',
      dataHoraBr: dhFmt,
      linhas: linhas,
      observacoes: o.descricao,
      fotos: fotos,
      fotoFetcher: OcorrenciaService.obterFoto,
      tituloGaleria: (o.titulo?.trim().isNotEmpty ?? false)
          ? o.titulo!
          : 'Ocorrência',
      onEditar: (_) async {
        await _abrirFormOcorrencia(bdtId: bdtId, existente: o);
        return true;
      },
      onExcluir: (_) async {
        await _excluirOcorrencia(bdtId, o);
        // _excluirOcorrencia já recarrega; assume que sim se chegou aqui.
        return true;
      },
    );

    final r = await _abrirDetalheRegistro(args);
    if (r && mounted) await _load(bdtId);
  }

  // =========================================================================
  // Sprint 6 W+M — Divergências (motor W10). Condutor REGISTRA; admin decide.
  // =========================================================================

  Widget _cardDivergencias(int bdtId) {
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
                    "Divergências de carga",
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _abrirRegistrarDivergencia(bdtId),
                  icon: const Icon(Icons.report_problem_outlined),
                  label: const Text("Registrar"),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (divergencias.isEmpty)
              Text(
                "Nenhuma divergência registrada. "
                "Registre se a carga real não bater com o declarado.",
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: divergencias.length,
                separatorBuilder: (_, __) => const Divider(height: 0),
                itemBuilder: (_, i) => _tileDivergencia(bdtId, divergencias[i]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tileDivergencia(int bdtId, DivergenciaResumo d) {
    final dhFmt = DateFmt.dataHoraBr(d.criadoEm);
    final subtitle = <String>[];
    if (dhFmt.isNotEmpty) subtitle.add(dhFmt);
    if ((d.criadoPorNome ?? '').isNotEmpty) subtitle.add(d.criadoPorNome!);

    // Cor do ícone reflete decisão: cinza=pendente, verde=prosseguido,
    // vermelho=cancelado pelo admin (aviso pro condutor).
    final Color corIcone;
    final IconData iconeDec;
    if (d.canceladoPeloAdmin) {
      corIcone = Colors.red.shade700;
      iconeDec = Icons.cancel_outlined;
    } else if (d.prosseguidoPeloAdmin) {
      corIcone = Colors.green.shade700;
      iconeDec = Icons.check_circle_outline;
    } else {
      corIcone = Colors.amber.shade800;
      iconeDec = Icons.hourglass_bottom_outlined;
    }

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(iconeDec, color: corIcone),
      title: Text(
        d.tipoLabel.isEmpty ? 'Divergência' : d.tipoLabel,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        [
          if (subtitle.isNotEmpty) subtitle.join(' • '),
          d.canceladoPeloAdmin
              ? 'BDT cancelado pelo admin'
              : d.prosseguidoPeloAdmin
                  ? 'Admin decidiu prosseguir'
                  : 'Aguardando decisão do admin',
          if ((d.descricao ?? '').isNotEmpty) d.descricao!,
        ].where((s) => s.isNotEmpty).join('\n'),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (d.qtdFotos > 0) ...[
            const Icon(Icons.photo_library_outlined,
                size: 14, color: Colors.black54),
            const SizedBox(width: 2),
            Text('${d.qtdFotos}',
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
            const SizedBox(width: 4),
          ],
          IconButton(
            tooltip: 'Ver detalhes',
            icon: const Icon(Icons.visibility_outlined, size: 20),
            visualDensity: VisualDensity.compact,
            onPressed: () => _verDivergencia(bdtId, d),
          ),
        ],
      ),
      onTap: () => _verDivergencia(bdtId, d),
    );
  }

  Future<void> _abrirRegistrarDivergencia(int bdtId) async {
    final ok = await Navigator.pushNamed(
      context,
      '/bdt/divergencia/nova',
      arguments: bdtId,
    );
    if (ok == true && mounted) {
      // ignore: discarded_futures
      _load(bdtId);
    }
  }

  Future<void> _verDivergencia(int bdtId, DivergenciaResumo d) async {
    final fotos = _fotosDivergencia[d.id] ?? const [];
    final dhFmt = DateFmt.dataHoraBr(d.criadoEm);
    final decisaoLabel = d.canceladoPeloAdmin
        ? 'Cancelou o BDT'
        : d.prosseguidoPeloAdmin
            ? 'Decidiu prosseguir'
            : 'Aguardando decisão';

    final linhas = <RegistroBdtLinha>[
      RegistroBdtLinha(
        icone: Icons.category,
        label: 'Tipo',
        valor: d.tipoLabel,
      ),
      RegistroBdtLinha(
        icone: Icons.gavel,
        label: 'Decisão',
        valor: decisaoLabel,
      ),
      if ((d.decisaoObs ?? '').isNotEmpty)
        RegistroBdtLinha(
          icone: Icons.speaker_notes,
          label: 'Obs. admin',
          valor: d.decisaoObs!,
        ),
      if ((d.criadoPorNome ?? '').isNotEmpty)
        RegistroBdtLinha(
          icone: Icons.person,
          label: 'Registrada por',
          valor: d.criadoPorNome!,
        ),
      if ((d.severidade ?? '').isNotEmpty)
        RegistroBdtLinha(
          icone: Icons.warning_amber,
          label: 'Severidade',
          valor: (d.severidade ?? '').toUpperCase(),
        ),
    ];

    final args = RegistroBdtDetalheArgs(
      tituloAppBar: 'Divergência',
      subtituloAppBar: 'BDT #$bdtId',
      icone: Icons.report_problem_outlined,
      corCabecalho: d.canceladoPeloAdmin
          ? const Color(0xFFF8D7DA)
          : d.prosseguidoPeloAdmin
              ? const Color(0xFFD4EDDA)
              : const Color(0xFFFFF3CD),
      tituloRegistro: d.tipoLabel,
      dataHoraBr: dhFmt,
      linhas: linhas,
      observacoes: d.descricao,
      fotos: fotos,
      fotoFetcher: (docId) =>
          DivergenciaService.obterFoto(docId, divergenciaId: d.id),
      tituloGaleria: 'Divergência',
      // Condutor não edita nem exclui divergência (admin decide).
      onEditar: null,
      onExcluir: null,
    );

    final r = await _abrirDetalheRegistro(args);
    if (r && mounted) await _load(bdtId);
  }

  // =========================================================================
  // Sprint 6 W+M — Carga declarada (leitura). Condutor CONSULTA o que foi
  // prometido antes de chegar no destino; se der divergência, registra no
  // card "Divergências de carga" ao lado.
  // =========================================================================

  Widget _cardCargaDeclarada(int bdtId) {
    return Card(
      elevation: 0,
      color: const Color(0xFFEAF3FF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFB8DAFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.inventory_2_outlined, size: 20),
                SizedBox(width: 8),
                Text(
                  'Carga declarada',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Confira o que foi declarado no pedido. Se a carga real '
              'não bater, registre em "Divergências de carga".',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            for (int i = 0; i < cargas.length; i++) ...[
              _tileCarga(bdtId, cargas[i]),
              if (i < cargas.length - 1) const Divider(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tileCarga(int bdtId, CargaDoBdt c) {
    // Monta subtítulo com peso e dimensões condensados.
    final medidas = <String>[];
    if (c.pesoKg != null) medidas.add('${c.pesoKg!.toStringAsFixed(1)} kg');
    final dims = [c.comprimentoM, c.larguraM, c.alturaM]
        .where((d) => d != null)
        .map((d) => d!.toStringAsFixed(2))
        .toList();
    if (dims.length == 3) {
      medidas.add('${dims[0]} × ${dims[1]} × ${dims[2]} m');
    } else {
      for (final d in dims) {
        medidas.add('$d m');
      }
    }

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        c.protocolo,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        [
          if ((c.descricao ?? '').trim().isNotEmpty) c.descricao!.trim(),
          if (medidas.isNotEmpty) medidas.join(' • '),
          if ((c.pessoalApoio ?? '').trim().isNotEmpty)
            'Apoio: ${c.pessoalApoio!.trim()}',
        ].join('\n'),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.fotos.isNotEmpty) ...[
            const Icon(Icons.photo_library_outlined,
                size: 14, color: Colors.black54),
            const SizedBox(width: 2),
            Text('${c.fotos.length}',
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
            const SizedBox(width: 4),
          ],
          IconButton(
            tooltip: 'Ver detalhes',
            icon: const Icon(Icons.visibility_outlined, size: 20),
            visualDensity: VisualDensity.compact,
            onPressed: () => _verCarga(bdtId, c),
          ),
        ],
      ),
      onTap: () => _verCarga(bdtId, c),
    );
  }

  Future<void> _verCarga(int bdtId, CargaDoBdt c) async {
    final linhas = <RegistroBdtLinha>[
      RegistroBdtLinha(
        icone: Icons.confirmation_number_outlined,
        label: 'Solicitação',
        valor: c.protocolo,
      ),
      if (c.pesoKg != null)
        RegistroBdtLinha(
          icone: Icons.scale,
          label: 'Peso',
          valor: '${c.pesoKg!.toStringAsFixed(1)} kg',
        ),
      if (c.comprimentoM != null)
        RegistroBdtLinha(
          icone: Icons.straighten,
          label: 'Comprimento',
          valor: '${c.comprimentoM!.toStringAsFixed(2)} m',
        ),
      if (c.larguraM != null)
        RegistroBdtLinha(
          icone: Icons.straighten,
          label: 'Largura',
          valor: '${c.larguraM!.toStringAsFixed(2)} m',
        ),
      if (c.alturaM != null)
        RegistroBdtLinha(
          icone: Icons.height,
          label: 'Altura',
          valor: '${c.alturaM!.toStringAsFixed(2)} m',
        ),
      if ((c.pessoalApoio ?? '').trim().isNotEmpty)
        RegistroBdtLinha(
          icone: Icons.groups_outlined,
          label: 'Pessoal apoio',
          valor: c.pessoalApoio!.trim(),
        ),
    ];

    // Adapta CargaFotoRef → FotoDocumentoRef pra reusar o layout
    // padronizado do RegistroBdtDetalhePage (que já sabe abrir a
    // FotoGaleriaPage swipeable com legenda).
    final fotosRefs = c.fotos
        .map((f) => FotoDocumentoRef(
              id: f.id,
              mimeType: f.mimeType,
              createdAt: f.createdAt,
              descricao: f.descricao,
            ))
        .toList();

    final args = RegistroBdtDetalheArgs(
      tituloAppBar: 'Carga declarada',
      subtituloAppBar: c.protocolo,
      icone: Icons.inventory_2_outlined,
      corCabecalho: const Color(0xFFEAF3FF),
      tituloRegistro: (c.descricao ?? '').trim().isNotEmpty
          ? c.descricao!.trim()
          : c.protocolo,
      linhas: linhas,
      fotos: fotosRefs,
      fotoFetcher: (docId) => CargaService.obterFoto(docId, bdtId: bdtId),
      tituloGaleria: 'Carga ${c.protocolo}',
      // Leitura pura — condutor não edita nem exclui carga declarada.
      onEditar: null,
      onExcluir: null,
    );

    await _abrirDetalheRegistro(args);
  }
}
