import 'package:flutter/material.dart';

import '../models/veiculo.dart';
import '../services/bdt_service.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/veiculo_autocomplete.dart';

/// Sprint M3 — formulário de criação de Pré-BDT pelo condutor.
///
/// Preenche o mínimo para o admin conseguir aprovar/recusar:
/// - Veículo (autocomplete por placa/modelo/marca)
/// - Data de referência (default hoje)
/// - Trechos previstos (origem → destino, com horários opcionais)
/// - Observações gerais (opcional)
///
/// Ao enviar, chama `POST transporte/api/bdt/pre-bdt/criar`. Se OK, mostra
/// o protocolo e volta para a home.
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

  @override
  void dispose() {
    _obsCtrl.dispose();
    for (final t in _trechos) {
      t.dispose();
    }
    super.dispose();
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
    // valida veículo (o Autocomplete não tem FormField validator, checamos manual)
    if (_veiculo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolha um veículo.')),
      );
      return;
    }

    // valida trechos
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
      final res = await BdtService.criarPreBdt(
        fkVeiculo: _veiculo!.id,
        dataReferencia: _apiData(_dataRef),
        observacoesGerais: _obsCtrl.text,
        trechos: trechosPayload,
      );

      if (!mounted) return;

      if (res['success'] == true) {
        final protocolo = (res['protocolo'] ?? '').toString();
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Pré-BDT enviado'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Seu Pré-BDT foi enviado para aprovação. O admin será notificado.',
                ),
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
        // Pré-BDTs pendentes" — mostrando o recém-criado sem exigir 🔄.
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (res['message'] ?? 'Falha ao enviar Pré-BDT.').toString(),
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
      title: 'Novo Pré-BDT',
      subtitle: 'Saída urgente',
      body: Form(
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
                  : const Icon(Icons.send),
              label: const Text('Enviar para aprovação'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
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

  void dispose() {
    origemCtrl.dispose();
    destinoCtrl.dispose();
    horaSaidaCtrl.dispose();
    horaChegadaCtrl.dispose();
  }
}
