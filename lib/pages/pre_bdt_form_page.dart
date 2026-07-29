import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/pre_bdt_pendente.dart';
import '../models/veiculo.dart';
import '../services/bdt_service.dart';
import '../services/ocorrencia_service.dart' show OcorrenciaFotoRef;
import '../utils/date_fmt.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/carga_form_card.dart';
import '../widgets/veiculo_autocomplete.dart';

/// Sprint M3 — formulário de Pré-BDT: **cria** ou **edita**.
///
/// O modo é decidido pelo `arguments` da rota:
/// - `Navigator.pushNamed(context, '/pre_bdt/novo')` → cria
/// - `Navigator.pushNamed(context, '/pre_bdt/editar', arguments: bdtId)` → edita
///
/// Em modo edição, chama `BdtService.obterPreBdt(bdtId)` no primeiro
/// `didChangeDependencies` (precisa de `ModalRoute` → não dá pra ler
/// os arguments no `initState`) e pré-preenche todos os campos. Se o
/// backend responder null (já foi aprovado/recusado, ou é de outro
/// usuário), mostra estado de erro com botão "Voltar".
class PreBdtFormPage extends StatefulWidget {
  const PreBdtFormPage({super.key});

  @override
  State<PreBdtFormPage> createState() => _PreBdtFormPageState();
}

class _PreBdtFormPageState extends State<PreBdtFormPage> {
  final _formKey = GlobalKey<FormState>();

  Veiculo? _veiculo;
  final _obsCtrl = TextEditingController();
  DateTime _dataRef = DateTime.now();
  final List<_TrechoInput> _trechos = [_TrechoInput()];

  bool _enviando = false;

  /// Sprint 15 W+M (2026-07-26) — erro do card Identificação.
  /// Antes: SnackBar "Escolha um veículo." — invisível atrás do teclado.
  String? _veiculoError;

  // ── Sprint 11 W+M — Carga (opcional). Fotos ficam obrigatórias
  //     na UX quando `_temCarga=true` (paridade com folha.php do web).
  bool _temCarga = false;
  final _cargaDescCtrl = TextEditingController();
  final _cargaPesoCtrl = TextEditingController();
  final _cargaComprCtrl = TextEditingController();
  final _cargaLargCtrl = TextEditingController();
  final _cargaAltCtrl = TextEditingController();

  /// Fotos escolhidas offline (só em modo criação — na edição, ver `_fotosExistentes`).
  final List<XFile> _fotosPendingCarga = [];
  /// Fotos já persistidas (só em modo edição). Populado após carregar.
  List<OcorrenciaFotoRef> _fotosExistentesCarga = const [];

  final _picker = ImagePicker();
  String? _cargaError; // erro específico do card carga

  // ── Estado do modo edição ─────────────────────────────────────────
  /// bdtId lido do arguments da rota. Null = modo criação.
  int? _bdtId;
  /// Trava do bootstrap (didChangeDependencies roda mais de uma vez).
  bool _bootstrapped = false;
  /// Enquanto true, mostra loading no lugar do form (só em edição).
  bool _carregando = false;
  /// Se o obter retornou null (não pode editar), guarda a mensagem
  /// pra mostrar em vez do form.
  String? _erroCarregar;

  bool get _modoEdicao => _bdtId != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is int) {
      _bdtId = args;
      _carregando = true;
      // dispara o load fora do frame para não emitir setState em build.
      WidgetsBinding.instance.addPostFrameCallback((_) => _carregarParaEdicao());
    }
  }

  @override
  void dispose() {
    _obsCtrl.dispose();
    _cargaDescCtrl.dispose();
    _cargaPesoCtrl.dispose();
    _cargaComprCtrl.dispose();
    _cargaLargCtrl.dispose();
    _cargaAltCtrl.dispose();
    for (final t in _trechos) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _carregarParaEdicao() async {
    final id = _bdtId;
    if (id == null) return;
    try {
      final p = await BdtService.obterPreBdt(id);
      if (!mounted) return;
      if (p == null) {
        setState(() {
          _carregando = false;
          _erroCarregar =
              'Este Pré-BDT não pode ser editado. Provavelmente o admin '
              'já aprovou ou recusou. Volte para a home e recarregue.';
        });
        return;
      }
      // Preenche o form com os dados do backend.
      _veiculo = Veiculo(
        id: p.fkVeiculo,
        placa: p.veiculoPlaca ?? '',
        marca: p.veiculoMarca,
        modelo: p.veiculoModelo,
        label: p.veiculoLabel,
      );
      _obsCtrl.text = p.observacoesGerais ?? '';
      _dataRef = _parseData(p.dataReferencia) ?? DateTime.now();

      // Descarta os controllers vazios criados no init e monta um por trecho.
      for (final t in _trechos) {
        t.dispose();
      }
      _trechos
        ..clear()
        ..addAll(p.trechos.map(_TrechoInput.fromPrevisto));
      if (_trechos.isEmpty) _trechos.add(_TrechoInput());

      // Sprint 11 W+M — carga (opcional). Se veio marcada, popula os
      // controllers e dispara o loader das fotos ja persistidas.
      _temCarga = p.temCarga;
      _cargaDescCtrl.text = p.carga ?? '';
      _cargaPesoCtrl.text = _fmtDec(p.cargaPesoKg);
      _cargaComprCtrl.text = _fmtDec(p.cargaComprimentoM);
      _cargaLargCtrl.text = _fmtDec(p.cargaLarguraM);
      _cargaAltCtrl.text = _fmtDec(p.cargaAlturaM);
      if (_temCarga) {
        // Fire-and-forget — o setState atualiza o grid quando chegar.
        // ignore: discarded_futures
        BdtService.listarFotosCarga(id).then((list) {
          if (mounted) setState(() => _fotosExistentesCarga = list);
        });
      }

      setState(() {
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erroCarregar = 'Falha ao carregar Pré-BDT: $e';
      });
    }
  }

  DateTime? _parseData(String iso) {
    if (iso.isEmpty) return null;
    try {
      return DateTime.parse(iso.length >= 10 ? iso.substring(0, 10) : iso);
    } catch (_) {
      return null;
    }
  }

  String _fmtData(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  String _apiData(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  Future<void> _pickData() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dataRef,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (picked != null) setState(() => _dataRef = picked);
  }

  void _addTrecho() {
    setState(() => _trechos.add(_TrechoInput()));
  }

  void _removeTrecho(int i) {
    setState(() {
      _trechos[i].dispose();
      _trechos.removeAt(i);
      if (_trechos.isEmpty) _trechos.add(_TrechoInput());
    });
  }

  Future<void> _enviar() async {
    // Sprint 15 W+M (2026-07-26) — validação por campo com errorText
    // inline em vez de SnackBar (que fica atrás do teclado). Roda
    // TODA a validação antes de retornar pra o condutor ver todos os
    // erros de uma vez (não corrigir 1, apertar, corrigir o próximo).
    bool temErro = false;

    if (_veiculo == null) {
      setState(() => _veiculoError = 'Escolha um veículo.');
      temErro = true;
    }

    final trechosPayload = <Map<String, dynamic>>[];
    for (var i = 0; i < _trechos.length; i++) {
      final t = _trechos[i];
      final origem = t.origemCtrl.text.trim();
      final destino = t.destinoCtrl.text.trim();
      final novoErrOrigem = origem.isEmpty ? 'Informe a origem.' : null;
      final novoErrDestino = destino.isEmpty ? 'Informe o destino.' : null;
      if (novoErrOrigem != null || novoErrDestino != null) {
        setState(() {
          t.errOrigem = novoErrOrigem;
          t.errDestino = novoErrDestino;
        });
        temErro = true;
        continue;
      }
      trechosPayload.add({
        'origem': origem,
        'destino': destino,
        if (t.horaSaidaCtrl.text.isNotEmpty)
          'saida': _apiHora(t.horaSaidaCtrl.text),
        if (t.horaChegadaCtrl.text.isNotEmpty)
          'chegada': _apiHora(t.horaChegadaCtrl.text),
      });
    }

    if (temErro) return;

    // Sprint 11 W+M — validação de carga (paridade com folha.php do web).
    // Se `_temCarga=true`: descrição obrigatória + pelo menos 1 foto
    // (já persistida ou pending).
    if (_temCarga) {
      if (_cargaDescCtrl.text.trim().isEmpty) {
        setState(() => _cargaError = 'Descreva a carga (obrigatório).');
        return;
      }
      final totalFotos = _fotosPendingCarga.length + _fotosExistentesCarga.length;
      if (totalFotos == 0) {
        setState(() => _cargaError =
            'Anexe pelo menos 1 foto da carga — a foto documenta o que foi embarcado.');
        return;
      }
    }

    setState(() => _enviando = true);
    try {
      final res = _modoEdicao
          ? await BdtService.atualizarPreBdt(
              bdtId: _bdtId!,
              fkVeiculo: _veiculo!.id,
              dataReferencia: _apiData(_dataRef),
              observacoesGerais: _obsCtrl.text,
              trechos: trechosPayload,
              temCarga: _temCarga,
              carga: _cargaDescCtrl.text,
              cargaPesoKg: _parseDec(_cargaPesoCtrl.text),
              cargaComprimentoM: _parseDec(_cargaComprCtrl.text),
              cargaLarguraM: _parseDec(_cargaLargCtrl.text),
              cargaAlturaM: _parseDec(_cargaAltCtrl.text),
            )
          : await BdtService.criarPreBdt(
              fkVeiculo: _veiculo!.id,
              dataReferencia: _apiData(_dataRef),
              observacoesGerais: _obsCtrl.text,
              trechos: trechosPayload,
              temCarga: _temCarga,
              carga: _cargaDescCtrl.text,
              cargaPesoKg: _parseDec(_cargaPesoCtrl.text),
              cargaComprimentoM: _parseDec(_cargaComprCtrl.text),
              cargaLarguraM: _parseDec(_cargaLargCtrl.text),
              cargaAlturaM: _parseDec(_cargaAltCtrl.text),
            );

      if (!mounted) return;

      if (res['success'] == true) {
        final bdtId = _modoEdicao
            ? _bdtId!
            : (res['bdt_id'] is int
                ? res['bdt_id'] as int
                : int.tryParse(res['bdt_id']?.toString() ?? '') ?? 0);

        // Upload em batch das fotos pendentes de carga (só se ainda tem).
        int fotosOk = 0;
        int fotosFail = 0;
        if (_temCarga && bdtId > 0 && _fotosPendingCarga.isNotEmpty) {
          for (final xf in _fotosPendingCarga) {
            try {
              final bytes = await File(xf.path).readAsBytes();
              final docId = await BdtService.uploadFotoCarga(
                bdtId: bdtId,
                bytes: bytes,
                filename: xf.name,
              );
              if (docId > 0) {
                fotosOk++;
              } else {
                fotosFail++;
              }
            } catch (_) {
              fotosFail++;
            }
            if (!mounted) return;
          }
        }

        final protocolo = (res['protocolo'] ?? '').toString();
        var mensagem = _modoEdicao
            ? 'Pré-BDT atualizado. Continua na fila de aprovação.'
            : 'Seu Pré-BDT foi enviado para aprovação. O admin será notificado.';
        if (fotosFail > 0) {
          mensagem += '\n\n$fotosOk foto(s) OK, $fotosFail falhou(aram) — '
              'tente subir de novo editando o Pré-BDT.';
        } else if (fotosOk > 0) {
          mensagem += '\n\n$fotosOk foto(s) de carga anexada(s).';
        }
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(_modoEdicao ? 'Pré-BDT atualizado' : 'Pré-BDT enviado'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mensagem),
                const SizedBox(height: 10),
                if (protocolo.isNotEmpty) ...[
                  const Text('Protocolo:',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 2),
                  SelectableText(
                    protocolo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        // pop(true) sinaliza pra HomePage recarregar a lista de "Meus
        // Pré-BDTs pendentes" — mostrando a criação/edição sem precisar 🔄.
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (res['message'] ??
                      (_modoEdicao
                          ? 'Falha ao atualizar Pré-BDT.'
                          : 'Falha ao enviar Pré-BDT.'))
                  .toString(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// "12.50" -> "12,50" (padrão pt-BR pra pré-preenchimento). null/0 -> "".
  String _fmtDec(double? v) {
    if (v == null || v <= 0) return '';
    return v.toStringAsFixed(2).replaceAll('.', ',');
  }

  /// "12,5" -> 12.5. Vazio ou inválido -> null.
  double? _parseDec(String raw) {
    final s = raw.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  Future<void> _adicionarFotoCarga() async {
    final source = await showModalBottomSheet<ImageSource>(
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
    if (source == null || !mounted) return;
    try {
      final f = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (f == null || !mounted) return;
      setState(() {
        _fotosPendingCarga.add(f);
        _cargaError = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao acessar câmera/galeria: $e')),
      );
    }
  }

  Future<void> _removerFotoExistente(int docId) async {
    final ok = await BdtService.excluirFotoCarga(docId);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falha ao remover a foto.')),
      );
      return;
    }
    setState(() {
      _fotosExistentesCarga =
          _fotosExistentesCarga.where((f) => f.id != docId).toList();
    });
  }

  /// Sprint MSEC.TZ — Converte "HH:MM" (local) + data de referência (local)
  /// em ISO UTC ("YYYY-MM-DDTHH:MM:00Z"), aceito pelo backend via
  /// `api_parse_datetime_utc`. Antes: emitia naive "yyyy-mm-dd HH:MM:00"
  /// que o backend interpretava como BRT wall-clock (drift de 3h ao gravar).
  String? _apiHora(String hm) {
    if (hm.isEmpty) return null;
    final parts = hm.split(':');
    if (parts.length != 2) return null;

    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;

    final local = DateTime(_dataRef.year, _dataRef.month, _dataRef.day, h, m);
    return DateFmt.apiIsoUtc(local);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _modoEdicao ? 'Editar Pré-BDT' : 'Novo Pré-BDT',
      subtitle: _modoEdicao ? 'Aguardando aprovação' : 'Saída urgente',
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erroCarregar != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 48, color: Colors.black54),
            const SizedBox(height: 12),
            Text(
              _erroCarregar!,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Voltar para a home'),
            ),
          ],
        ),
      );
    }

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
        children: [
          _cardCabecalho(),
          const SizedBox(height: 12),
          _cardTrechos(),
          const SizedBox(height: 12),
          // Sprint 11 W+M — card de carga. Extraído para `CargaFormCard` em
          // 2026-07-29, quando o BDT direto passou a aceitar carga também:
          // as duas telas gravam nas mesmas colunas de `trnsp_bdt`, então
          // duplicar a UI abriria espaço pra elas divergirem.
          CargaFormCard(
            temCarga: _temCarga,
            onTemCargaChanged: (v) => setState(() {
              _temCarga = v;
              _cargaError = null;
            }),
            enabled: !_enviando,
            erro: _cargaError,
            descCtrl: _cargaDescCtrl,
            pesoCtrl: _cargaPesoCtrl,
            comprCtrl: _cargaComprCtrl,
            largCtrl: _cargaLargCtrl,
            altCtrl: _cargaAltCtrl,
            onDescricaoChanged: () {
              if (_cargaError != null) setState(() => _cargaError = null);
            },
            fotosPendentes: _fotosPendingCarga,
            fotosExistentes: _fotosExistentesCarga,
            onAdicionarFoto: _adicionarFotoCarga,
            onRemoverPendente: (i) =>
                setState(() => _fotosPendingCarga.removeAt(i)),
            // `_removerFotoExistente` é async; o callback é sync, então
            // disparamos e deixamos o próprio método fazer o setState.
            onRemoverExistente: (docId) {
              // ignore: discarded_futures
              _removerFotoExistente(docId);
            },
          ),
          const SizedBox(height: 12),
          _cardObs(),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _enviando ? null : _enviar,
            icon: _enviando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_modoEdicao ? Icons.save : Icons.send),
            label: Text(_modoEdicao ? 'Salvar alterações' : 'Enviar para aprovação'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardCabecalho() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Identificação',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            VeiculoAutocomplete(
              initialValue: _veiculo,
              onChanged: (v) => setState(() {
                _veiculo = v;
                if (v != null) _veiculoError = null;
              }),
            ),
            if (_veiculoError != null) ...[
              const SizedBox(height: 6),
              Text(
                _veiculoError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickData,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Data de referência',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_month),
                ),
                child: Text(_fmtData(_dataRef)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardTrechos() {
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
                  child: Text('Trechos previstos',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                OutlinedButton.icon(
                  onPressed: _addTrecho,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < _trechos.length; i++) ...[
              const Divider(),
              _trechoRow(i),
            ],
          ],
        ),
      ),
    );
  }

  Widget _trechoRow(int i) {
    final t = _trechos[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                child: Text('${i + 1}',
                    style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Trecho ${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              if (_trechos.length > 1)
                IconButton(
                  tooltip: 'Remover',
                  onPressed: () => _removeTrecho(i),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: t.origemCtrl,
            onChanged: (_) {
              if (t.errOrigem != null) setState(() => t.errOrigem = null);
            },
            decoration: InputDecoration(
              labelText: 'Origem',
              border: const OutlineInputBorder(),
              errorText: t.errOrigem,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: t.destinoCtrl,
            onChanged: (_) {
              if (t.errDestino != null) setState(() => t.errDestino = null);
            },
            decoration: InputDecoration(
              labelText: 'Destino',
              border: const OutlineInputBorder(),
              errorText: t.errDestino,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: t.horaSaidaCtrl,
                  readOnly: true,
                  onTap: () => _pickHora(t.horaSaidaCtrl),
                  decoration: const InputDecoration(
                    labelText: 'Saída (HH:MM)',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.schedule),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: t.horaChegadaCtrl,
                  readOnly: true,
                  onTap: () => _pickHora(t.horaChegadaCtrl),
                  decoration: const InputDecoration(
                    labelText: 'Chegada (HH:MM)',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.schedule),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickHora(TextEditingController c) async {
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
    c.text = '${two(t.hour)}:${two(t.minute)}';
  }


  Widget _cardObs() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Observações',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _obsCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Observações gerais (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrechoInput {
  final origemCtrl = TextEditingController();
  final destinoCtrl = TextEditingController();
  final horaSaidaCtrl = TextEditingController();
  final horaChegadaCtrl = TextEditingController();

  // Sprint 15 W+M (2026-07-26) — erros inline por trecho (mesmo padrão
  // dos outros forms: AbastecimentoSheet, TrechoExtraSheet, etc.).
  // Antes: SnackBar "Trecho N: preencha origem e destino." — invisível
  // atrás do teclado.
  String? errOrigem;
  String? errDestino;

  _TrechoInput();

  /// Constrói um `_TrechoInput` a partir de um `TrechoPrevisto` vindo do
  /// backend. Extrai só o "HH:MM" das strings de datetime (`saida` /
  /// `chegada` no formato "YYYY-MM-DD HH:MM:SS"), que é o que o
  /// `showTimePicker` espera no controller.
  factory _TrechoInput.fromPrevisto(TrechoPrevisto t) {
    final i = _TrechoInput();
    i.origemCtrl.text  = t.origem;
    i.destinoCtrl.text = t.destino;
    i.horaSaidaCtrl.text   = _hhmm(t.saida);
    i.horaChegadaCtrl.text = _hhmm(t.chegada);
    return i;
  }

  static String _hhmm(String? dtIso) {
    if (dtIso == null || dtIso.isEmpty) return '';
    // Aceita "YYYY-MM-DD HH:MM:SS", "YYYY-MM-DDTHH:MM:SS" ou já "HH:MM".
    final s = dtIso.replaceFirst('T', ' ');
    if (s.length >= 16 && s.contains(' ')) {
      return s.substring(11, 16); // "HH:MM"
    }
    if (s.length >= 5 && s.contains(':')) {
      return s.substring(0, 5);
    }
    return '';
  }

  void dispose() {
    origemCtrl.dispose();
    destinoCtrl.dispose();
    horaSaidaCtrl.dispose();
    horaChegadaCtrl.dispose();
  }
}
