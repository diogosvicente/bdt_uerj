import 'package:flutter/material.dart';

import '../models/pre_bdt_pendente.dart';
import '../models/veiculo.dart';
import '../services/bdt_service.dart';
import '../widgets/app_scaffold.dart';
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
    if (_veiculo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolha um veículo.')),
      );
      return;
    }

    final trechosPayload = <Map<String, dynamic>>[];
    for (var i = 0; i < _trechos.length; i++) {
      final t = _trechos[i];
      final origem = t.origemCtrl.text.trim();
      final destino = t.destinoCtrl.text.trim();
      if (origem.isEmpty || destino.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Trecho ${i + 1}: preencha origem e destino.')),
        );
        return;
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

    setState(() => _enviando = true);
    try {
      final res = _modoEdicao
          ? await BdtService.atualizarPreBdt(
              bdtId: _bdtId!,
              fkVeiculo: _veiculo!.id,
              dataReferencia: _apiData(_dataRef),
              observacoesGerais: _obsCtrl.text,
              trechos: trechosPayload,
            )
          : await BdtService.criarPreBdt(
              fkVeiculo: _veiculo!.id,
              dataReferencia: _apiData(_dataRef),
              observacoesGerais: _obsCtrl.text,
              trechos: trechosPayload,
            );

      if (!mounted) return;

      if (res['success'] == true) {
        final protocolo = (res['protocolo'] ?? '').toString();
        final mensagem = _modoEdicao
            ? 'Pré-BDT atualizado. Continua na fila de aprovação.'
            : 'Seu Pré-BDT foi enviado para aprovação. O admin será notificado.';
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

  /// Converte "HH:MM" no formato aceito pelo backend combinando com a data.
  String? _apiHora(String hm) {
    if (hm.isEmpty) return null;
    final parts = hm.split(':');
    if (parts.length != 2) return null;
    return '${_apiData(_dataRef)} ${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}:00';
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
              onChanged: (v) => setState(() => _veiculo = v),
            ),
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
            decoration: const InputDecoration(
              labelText: 'Origem',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: t.destinoCtrl,
            decoration: const InputDecoration(
              labelText: 'Destino',
              border: OutlineInputBorder(),
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
