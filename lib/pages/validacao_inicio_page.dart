import 'package:flutter/material.dart';

import '../models/passageiro.dart';
import '../services/bdt_service.dart';
import '../utils/date_fmt.dart';
import '../utils/logger.dart';
import '../widgets/app_scaffold.dart';
import 'assinatura_marco_page.dart';

/// Página de validação de INÍCIO do atendimento (Sprint M4.1).
///
/// Reúne o fluxo do condutor no momento em que ele encontra os
/// passageiros:
///
/// 1. **Marcos da jornada** (partida → apresentacao → embarque_passageiro).
///    Cada marco abre a `AssinaturaMarcoPage` com painel de assinatura
///    touch. Depois de registrado, mostra data/hora + autor.
///
/// 2. **Lista de passageiros previstos** com switch de "presente" para
///    cada. Um botão "Salvar presenças" faz bulk update.
class ValidacaoInicioPage extends StatefulWidget {
  const ValidacaoInicioPage({super.key});

  @override
  State<ValidacaoInicioPage> createState() => _ValidacaoInicioPageState();
}

class _ValidacaoInicioPageState extends State<ValidacaoInicioPage> {
  static const _log = Logger('VALIDACAO-INICIO');

  bool _loading = true;
  Map<String, dynamic>? _estadoMarcos;
  List<Passageiro> _passageiros = const [];
  bool _dirty = false; // marca se houve mudança nos switches
  bool _salvandoPresencas = false;
  bool _bootstrapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;
    // ignore: discarded_futures
    _load();
  }

  int _bdtIdFromRoute() =>
      ModalRoute.of(context)!.settings.arguments as int;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final bdtId = _bdtIdFromRoute();
      final futs = await Future.wait([
        BdtService.estadoJornada(bdtId),
        BdtService.listarPassageiros(bdtId),
      ]);
      if (!mounted) return;
      setState(() {
        _estadoMarcos = futs[0] as Map<String, dynamic>?;
        _passageiros = futs[1] as List<Passageiro>;
        _loading = false;
        _dirty = false;
      });
    } catch (e) {
      _log.error('load falhou', e);
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _abrirAssinatura(String marco, String label) async {
    final ok = await Navigator.pushNamed(
      context,
      '/marco/assinatura',
      arguments: AssinaturaMarcoArgs(
        bdtId: _bdtIdFromRoute(),
        marco: marco,
        labelMarco: label,
      ),
    );
    if (ok == true) {
      // ignore: discarded_futures
      _load();
    }
  }

  void _togglePresenca(int idx, bool v) {
    setState(() {
      _passageiros = List.of(_passageiros)
        ..[idx] = _passageiros[idx].copyWith(presente: v);
      _dirty = true;
    });
  }

  Future<void> _salvarPresencas() async {
    if (_salvandoPresencas) return;
    setState(() => _salvandoPresencas = true);
    try {
      final updates = _passageiros
          .map((p) => {
                'passageiro_id': p.id,
                'presente': p.presente ? 1 : 0,
              })
          .toList();

      final ok = await BdtService.marcarPresencaPassageiros(
        bdtId: _bdtIdFromRoute(),
        updates: updates,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Presenças salvas.'
              : 'Falha ao salvar presenças. Tente novamente.'),
        ),
      );
      if (ok) setState(() => _dirty = false);
    } finally {
      if (mounted) setState(() => _salvandoPresencas = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Validar início',
      subtitle: 'Marcos + passageiros',
      onRefresh: _load,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
              children: [
                _cardMarcos(),
                const SizedBox(height: 12),
                _cardPassageiros(),
              ],
            ),
    );
  }

  Widget _cardMarcos() {
    const rows = [
      ('partida',             'Partida'),
      ('apresentacao',        'Apresentação'),
      ('embarque_passageiro', 'Embarque do passageiro'),
    ];
    final marcos = (_estadoMarcos?['marcos'] as Map?) ?? const {};

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Marcos da jornada',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final r in rows) _rowMarco(r.$1, r.$2, marcos[r.$1]),
          ],
        ),
      ),
    );
  }

  Widget _rowMarco(String marco, String label, dynamic entry) {
    final dh = (entry is Map) ? entry['datahora']?.toString() : null;
    final assinatura = (entry is Map) ? entry['assinatura'] : null;
    final assinaturaMap = (assinatura is Map)
        ? Map<String, dynamic>.from(assinatura)
        : null;

    final registrado = dh != null && dh.isNotEmpty;

    final autor = assinaturaMap != null
        ? (assinaturaMap['signatario_nome'] ?? assinaturaMap['criado_por_nome'] ?? '').toString()
        : '';
    final tipo = assinaturaMap != null
        ? (assinaturaMap['signatario_tipo'] ?? '').toString()
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            registrado ? Icons.check_circle : Icons.radio_button_unchecked,
            color: registrado ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (registrado) ...[
                  Text(DateFmt.dataHoraBr(dh),
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  if (autor.isNotEmpty)
                    Text(
                      tipo.isNotEmpty ? '$autor • $tipo' : autor,
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                ] else
                  const Text('Não registrado',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: () => _abrirAssinatura(marco, label),
            icon: const Icon(Icons.edit_note),
            label: Text(registrado ? 'Refazer' : 'Registrar'),
          ),
        ],
      ),
    );
  }

  Widget _cardPassageiros() {
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
                  child: Text('Passageiros previstos',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                Text('${_passageiros.where((p) => p.presente).length}/${_passageiros.length}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            if (_passageiros.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Nenhum passageiro previsto para este BDT.',
                    style: TextStyle(fontSize: 13, color: Colors.black54)),
              )
            else
              for (int i = 0; i < _passageiros.length; i++)
                _rowPassageiro(i, _passageiros[i]),
            if (_passageiros.isNotEmpty) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: (_dirty && !_salvandoPresencas)
                    ? _salvarPresencas
                    : null,
                icon: _salvandoPresencas
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Salvar presenças'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rowPassageiro(int idx, Passageiro p) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: p.presente,
      onChanged: (v) => _togglePresenca(idx, v),
      title: Text(p.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          if (p.matricula != null) 'Mat: ${p.matricula}',
          if (p.cpf != null) 'CPF: ${p.cpf}',
          if (p.telefone != null) p.telefone,
        ].join(' • '),
        style: const TextStyle(fontSize: 12),
      ),
      dense: true,
    );
  }
}
