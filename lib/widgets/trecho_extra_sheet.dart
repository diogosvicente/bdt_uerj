import 'package:flutter/material.dart';

/// Draft de trecho extra — o formulário devolve ISTO (não persiste ainda).
/// Quem chama decide o que fazer:
///  - `bdt_page.dart` chama `BdtService.criarTrechoExtra(bdtId, ...)`
///    imediatamente (BDT já existe).
///  - `criar_bdt_page.dart` acumula na lista e cria em batch depois
///    que o BDT for criado (mostra a lista pro condutor confirmar antes).
class TrechoDraft {
  final String origem;
  final String destino;
  final String? horaSaida; // "HH:MM" ou null
  final String? horaChegada; // "HH:MM" ou null
  final String? obs;

  const TrechoDraft({
    required this.origem,
    required this.destino,
    this.horaSaida,
    this.horaChegada,
    this.obs,
  });
}

/// Sprint 15 W+M (2026-07-26) — Bottom sheet reusável pra capturar
/// um trecho extra (origem + destino + horários opcionais + obs).
///
/// Extraído do `_openTrechoExtraSheet` inline do `bdt_page.dart` pra
/// reusar na `CriarBdtPage` (onde acumula os trechos ANTES de existir
/// BDT — a persistência acontece depois em batch).
///
/// Validação inline igual aos outros forms (padrão errorText por
/// campo + banner de nível de form pra ambiguidade de horários).
class TrechoExtraSheet {
  /// Abre o sheet. Retorna o `TrechoDraft` quando o usuário confirma,
  /// ou `null` se cancelou (fechou por swipe/back sem confirmar).
  ///
  /// `titulo` e `botaoLabel` permitem customizar o texto — a
  /// `CriarBdtPage` usa "Adicionar trecho" enquanto o `bdt_page` usa
  /// "Cadastrar trecho extra" (linguagem histórica).
  static Future<TrechoDraft?> show(
    BuildContext context, {
    String titulo = 'Adicionar trecho extra',
    String botaoLabel = 'Cadastrar trecho extra',
  }) {
    return showModalBottomSheet<TrechoDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _TrechoExtraForm(
        titulo: titulo,
        botaoLabel: botaoLabel,
      ),
    );
  }
}

class _TrechoExtraForm extends StatefulWidget {
  final String titulo;
  final String botaoLabel;

  const _TrechoExtraForm({
    required this.titulo,
    required this.botaoLabel,
  });

  @override
  State<_TrechoExtraForm> createState() => _TrechoExtraFormState();
}

class _TrechoExtraFormState extends State<_TrechoExtraForm> {
  final _origemCtrl = TextEditingController();
  final _destinoCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  final _horaSaidaCtrl = TextEditingController();
  final _horaChegadaCtrl = TextEditingController();

  // Padrão errorText inline por campo required + banner top pra
  // erros de nível de form (mesmo dos outros forms do app).
  String? _formError;
  String? _errOrigem;
  String? _errDestino;

  @override
  void dispose() {
    _origemCtrl.dispose();
    _destinoCtrl.dispose();
    _obsCtrl.dispose();
    _horaSaidaCtrl.dispose();
    _horaChegadaCtrl.dispose();
    super.dispose();
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
    setState(() {
      c.text = '${two(t.hour)}:${two(t.minute)}';
    });
  }

  void _confirmar() {
    final origem = _origemCtrl.text.trim();
    final destino = _destinoCtrl.text.trim();
    final novoErrOrigem = origem.isEmpty ? 'Informe a origem.' : null;
    final novoErrDestino = destino.isEmpty ? 'Informe o destino.' : null;
    if (novoErrOrigem != null || novoErrDestino != null) {
      setState(() {
        _errOrigem = novoErrOrigem;
        _errDestino = novoErrDestino;
        _formError = null;
      });
      return;
    }

    final hs = _horaSaidaCtrl.text.trim();
    final hc = _horaChegadaCtrl.text.trim();
    // Se preencheu um dos horários, exige o outro (senão fica meia-boca
    // no relatório final da folha).
    if ((hs.isNotEmpty) != (hc.isNotEmpty)) {
      setState(() => _formError =
          'Preencha os DOIS horários (saída e chegada) ou deixe ambos vazios.');
      return;
    }

    final obs = _obsCtrl.text.trim();
    Navigator.pop(
      context,
      TrechoDraft(
        origem: origem,
        destino: destino,
        horaSaida: hs.isEmpty ? null : hs,
        horaChegada: hc.isEmpty ? null : hc,
        obs: obs.isEmpty ? null : obs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + pad),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.titulo,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Um trecho que não veio de nenhuma solicitação — '
              'ex.: um deslocamento extra que surgiu na viagem.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            if (_formError != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: theme.colorScheme.errorContainer,
                ),
                child: Text(
                  _formError!,
                  style: TextStyle(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _origemCtrl,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_errOrigem != null) setState(() => _errOrigem = null);
              },
              decoration: InputDecoration(
                labelText: 'Origem *',
                hintText: 'Ex.: UERJ Maracanã',
                border: const OutlineInputBorder(),
                errorText: _errOrigem,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _destinoCtrl,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_errDestino != null) setState(() => _errDestino = null);
              },
              decoration: InputDecoration(
                labelText: 'Destino *',
                hintText: 'Ex.: Hospital Pedro Ernesto',
                border: const OutlineInputBorder(),
                errorText: _errDestino,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _horaSaidaCtrl,
                    readOnly: true,
                    onTap: () => _pickHora(_horaSaidaCtrl),
                    decoration: const InputDecoration(
                      labelText: 'Saída (HH:MM)',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.schedule),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _horaChegadaCtrl,
                    readOnly: true,
                    onTap: () => _pickHora(_horaChegadaCtrl),
                    decoration: const InputDecoration(
                      labelText: 'Chegada (HH:MM)',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.schedule),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _obsCtrl,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Observação (opcional)',
                hintText: 'Ex.: desvio pela Vermelha por obra',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _confirmar,
              icon: const Icon(Icons.add_road),
              label: Text(widget.botaoLabel),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
