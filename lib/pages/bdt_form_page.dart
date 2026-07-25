import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/abastecimento_foto_service.dart';
import '../services/bdt_service.dart';
import '../services/foto_documento_client.dart' show FotoDocumentoRef;
import '../services/manutencao_foto_service.dart';
import '../services/ocorrencia_service.dart';
import '../utils/date_fmt.dart';
import 'foto_galeria_page.dart';
import 'nova_ocorrencia_page.dart' show OcorrenciaFormArgs;
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

  // Sprint 18.2 — fotos por registro (populadas em paralelo no _load).
  // Chave = id do registro; valor = lista de refs (id + mime + descricao).
  // Usadas pras tiras de miniaturas nos cards + galeria full-screen.
  Map<int, List<FotoDocumentoRef>> _fotosAbastecimento = {};
  Map<int, List<FotoDocumentoRef>> _fotosManutencao   = {};
  Map<int, List<FotoDocumentoRef>> _fotosOcorrencia   = {};

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

    if (!mounted) return;
    setState(() {
      abastecimentos = abResolved;
      manutencoes = manResolved;
      ocorrencias = ocResolved;
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
    );
  }

  Future<void> _carregarFotosDosRegistros({
    required List<int> abIds,
    required List<int> mnIds,
    required List<int> ocIds,
  }) async {
    // Zera antes de recarregar (evita mostrar refs de registros deletados).
    if (mounted) {
      setState(() {
        _fotosAbastecimento = {};
        _fotosManutencao   = {};
        _fotosOcorrencia   = {};
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

  /// Sprint 18.2 — tira de miniaturas clicáveis. Tap abre a galeria
  /// full-screen com swipe entre as fotos, contador N/M e legenda.
  ///
  /// `fetcher` é o mesmo passado pro FotoDocumentoThumb (ex.:
  /// `AbastecimentoFotoService.obter`).
  /// `namespace` deve ser único por fluxo (`abastecimento_ID`,
  /// `manutencao_ID`, `ocorrencia_ID`) pra evitar colisão no cache.
  Widget _stripFotos({
    required List<FotoDocumentoRef> fotos,
    required Future<List<int>?> Function(int) fetcher,
    required String namespace,
    required String tituloGaleria,
  }) {
    if (fotos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: 64,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: fotos.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final f = fotos[i];
            return FotoDocumentoThumb(
              docId: f.id,
              fetcher: fetcher,
              cacheNamespace: namespace,
              size: 64,
              onTap: () => _abrirGaleria(
                fotos: fotos,
                fetcher: fetcher,
                indice: i,
                titulo: tituloGaleria,
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _abrirGaleria({
    required List<FotoDocumentoRef> fotos,
    required Future<List<int>?> Function(int) fetcher,
    required int indice,
    required String titulo,
  }) {
    final items = fotos
        .map((f) => FotoGaleriaItem(
              docId: f.id,
              fetcher: fetcher,
              label: (f.descricao?.trim().isNotEmpty ?? false)
                  ? f.descricao!
                  : '',
            ))
        .toList();
    return Navigator.pushNamed(
      context,
      '/foto/galeria',
      arguments: FotoGaleriaArgs(
        fotos: items,
        indiceInicial: indice,
        titulo: titulo,
      ),
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
                // Sprint MUX (2026-07-24) — Marcos da Jornada removidos
                // daqui. Estão em ValidacaoInicioPage (canônica, com
                // assinatura M4), acessível pelo sheet "Ações" do BdtPage.
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
                  final fotos = _fotosAbastecimento[absId] ?? const [];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          "${tipo.isEmpty ? 'Combustível' : tipo} • ${litros.isEmpty ? '-' : litros} L • ${valor.isEmpty ? '-' : valor}",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: dhFmt.isEmpty ? null : Text(dhFmt),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _openAbastecimentoSheet(existing: a),
                        ),
                      ),
                      _stripFotos(
                        fotos: fotos,
                        fetcher: (docId) => AbastecimentoFotoService.obter(
                          docId,
                          abastecimentoId: absId,
                        ),
                        namespace: 'abastecimento_$absId',
                        tituloGaleria: 'Abastecimento',
                      ),
                    ],
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
                  final fotos = _fotosManutencao[mntId] ?? const [];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          desc.isEmpty ? "Manutenção" : desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: iniFmt.isEmpty ? null : Text(iniFmt),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _openManutencaoSheet(existing: m),
                        ),
                      ),
                      _stripFotos(
                        fotos: fotos,
                        fetcher: (docId) => ManutencaoFotoService.obter(
                          docId,
                          manutencaoId: mntId,
                        ),
                        namespace: 'manutencao_$mntId',
                        tituloGaleria: 'Manutenção',
                      ),
                    ],
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

    final fotos = _fotosOcorrencia[o.id] ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (o.qtdFotos > 0) ...[
                const Icon(Icons.photo_library_outlined, size: 16),
                const SizedBox(width: 3),
                Text('${o.qtdFotos}', style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
              ],
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () => _abrirFormOcorrencia(bdtId: bdtId, existente: o),
              ),
              IconButton(
                tooltip: 'Excluir',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _excluirOcorrencia(bdtId, o),
              ),
            ],
          ),
          onTap: () => _abrirFormOcorrencia(bdtId: bdtId, existente: o),
        ),
        _stripFotos(
          fotos: fotos,
          fetcher: OcorrenciaService.obterFoto,
          namespace: 'ocorrencia',
          tituloGaleria: (o.titulo?.trim().isNotEmpty ?? false)
              ? o.titulo!
              : 'Ocorrência',
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
}
