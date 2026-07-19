import 'package:flutter/material.dart';

import '../models/feedback_condutor.dart';
import '../services/bdt_service.dart';
import '../utils/logger.dart';
import '../widgets/app_scaffold.dart';

/// Página de validação de CONCLUSÃO do atendimento + feedback do condutor
/// (Sprint M4.3).
///
/// Fluxo:
/// 1. Se já houver feedback registrado, mostra ele em modo readonly no topo.
/// 2. Nota (1–5 estrelas) + campo de comentário.
/// 3. Botão "Salvar feedback" → POST bdt/feedback-condutor/registrar.
/// 4. Botão "Encerrar BDT" → POST bdt/encerrar (só habilita depois do
///    feedback estar salvo).
class ConclusaoPage extends StatefulWidget {
  const ConclusaoPage({super.key});

  @override
  State<ConclusaoPage> createState() => _ConclusaoPageState();
}

class _ConclusaoPageState extends State<ConclusaoPage> {
  static const _log = Logger('CONCLUSAO');

  final _comCtrl = TextEditingController();
  int _nota = 0; // 0 = ainda não escolhido
  bool _loading = true;
  bool _salvandoFeedback = false;
  bool _encerrando = false;
  FeedbackCondutor? _existing;
  bool _bootstrapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;
    // ignore: discarded_futures
    _load();
  }

  @override
  void dispose() {
    _comCtrl.dispose();
    super.dispose();
  }

  int _bdtIdFromRoute() =>
      ModalRoute.of(context)!.settings.arguments as int;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final fb = await BdtService.obterFeedbackCondutor(_bdtIdFromRoute());
      if (!mounted) return;
      setState(() {
        _existing = fb;
        if (fb != null) {
          _nota = fb.nota;
          _comCtrl.text = fb.comentario ?? '';
        }
        _loading = false;
      });
    } catch (e) {
      _log.error('load falhou', e);
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _salvarFeedback() async {
    if (_nota < 1 || _nota > 5) {
      _snack('Escolha uma nota de 1 a 5 estrelas.');
      return;
    }
    setState(() => _salvandoFeedback = true);
    try {
      final ok = await BdtService.registrarFeedbackCondutor(
        bdtId: _bdtIdFromRoute(),
        nota: _nota,
        comentario: _comCtrl.text,
      );
      if (!mounted) return;
      if (ok) {
        _snack('Feedback salvo.');
        // ignore: discarded_futures
        _load();
      } else {
        _snack('Falha ao salvar feedback.');
      }
    } finally {
      if (mounted) setState(() => _salvandoFeedback = false);
    }
  }

  Future<void> _encerrar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Encerrar BDT?'),
        content: const Text(
          'Após encerrar, o BDT deixa de aceitar novos marcos, trechos e pontos de GPS. Essa ação pode ser desfeita apenas via reabertura pelo admin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _encerrando = true);
    try {
      final res = await BdtService.encerrarBdt(bdtId: _bdtIdFromRoute());
      if (!mounted) return;
      if (res['success'] == true) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('BDT encerrado'),
            content: const Text(
              'Este BDT foi marcado como Encerrado. Obrigado pelo atendimento.',
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
        Navigator.pop(context, true);
      } else {
        _snack(res['message']?.toString() ?? 'Falha ao encerrar BDT.');
      }
    } finally {
      if (mounted) setState(() => _encerrando = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final feedbackSalvo = _existing != null;

    return AppScaffold(
      title: 'Concluir viagem',
      subtitle: 'Feedback + encerramento',
      onRefresh: _load,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
              children: [
                _cardFeedback(feedbackSalvo),
                const SizedBox(height: 12),
                _cardEncerrar(feedbackSalvo),
              ],
            ),
    );
  }

  Widget _cardFeedback(bool salvo) {
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
                  child: Text('Feedback do condutor',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                if (salvo)
                  const Chip(
                    label: Text('Salvo'),
                    visualDensity: VisualDensity(horizontal: -3, vertical: -3),
                    avatar: Icon(Icons.check, size: 14, color: Colors.green),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Como foi a viagem do seu ponto de vista? (Nota + comentário — visível para a gestão do transporte.)',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            _estrelas(),
            const SizedBox(height: 12),
            TextField(
              controller: _comCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Comentário (opcional)',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _salvandoFeedback ? null : _salvarFeedback,
              icon: _salvandoFeedback
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(salvo ? 'Atualizar feedback' : 'Salvar feedback'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _estrelas() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final idx = i + 1;
        final active = _nota >= idx;
        return IconButton(
          iconSize: 36,
          onPressed: () => setState(() => _nota = idx),
          icon: Icon(
            active ? Icons.star : Icons.star_border,
            color: active ? Colors.amber : Colors.grey,
          ),
        );
      }),
    );
  }

  Widget _cardEncerrar(bool feedbackSalvo) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Encerrar BDT',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
              'Após encerrar, o BDT passa para o status "Encerrado". Só o admin pode reabrir.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: (!feedbackSalvo || _encerrando) ? null : _encerrar,
              icon: _encerrando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.stop_circle_outlined),
              label: const Text('Encerrar BDT'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: Colors.red.shade700,
              ),
            ),
            if (!feedbackSalvo)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Salve o feedback antes de encerrar.',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
