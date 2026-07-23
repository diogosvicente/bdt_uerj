import 'package:flutter/material.dart';

import '../models/ocorrencia.dart';
import '../services/ocorrencia_service.dart';
import '../utils/date_fmt.dart';
import '../widgets/app_scaffold.dart';

/// Sprint W+M (Sprint 17 web — W15 F3) — Detalhe de uma ocorrência
/// do histórico institucional. Route: `/ocorrencia/detalhe` com `int id`
/// como argument.
///
/// Backend: `POST transporte/api/bdt/ocorrencias/detalhes`.
/// Espelha a tela admin do web em `admin/ocorrencias/ver/{id}`.
class OcorrenciaDetalhePage extends StatefulWidget {
  const OcorrenciaDetalhePage({super.key});

  @override
  State<OcorrenciaDetalhePage> createState() => _OcorrenciaDetalhePageState();
}

class _OcorrenciaDetalhePageState extends State<OcorrenciaDetalhePage> {
  Future<Ocorrencia?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future != null) return;
    final id = ModalRoute.of(context)!.settings.arguments as int;
    _future = OcorrenciaService.detalhes(id);
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final id = ModalRoute.of(context)!.settings.arguments as int;
    setState(() {
      _future = OcorrenciaService.detalhes(id);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Ocorrência',
      subtitle: 'Detalhes',
      onRefresh: _reload,
      body: FutureBuilder<Ocorrencia?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final o = snap.data;
          if (o == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Ocorrência não encontrada ou sem acesso.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _corpo(o);
        },
      ),
    );
  }

  Widget _corpo(Ocorrencia o) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _cardCabecalho(o),
        const SizedBox(height: 12),
        if ((o.descricao ?? '').isNotEmpty) _cardDescricao(o.descricao!),
        const SizedBox(height: 12),
        _cardContexto(o),
      ],
    );
  }

  Widget _cardCabecalho(Ocorrencia o) {
    return Card(
      elevation: 0,
      color: const Color(0xFFFFF3CD),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.amber.shade700, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.amber.shade900,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    o.tipoNome,
                    style: TextStyle(
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
            if (o.titulo.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                o.titulo,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
            if ((o.dataHora ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 16, color: Colors.black54),
                  const SizedBox(width: 6),
                  Text(
                    DateFmt.dataHoraBr(o.dataHora),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cardDescricao(String descricao) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Descrição',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              descricao,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardContexto(Ocorrencia o) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Contexto',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 10),
            if (o.bdtLabel != null) _linha(Icons.description, o.bdtLabel!),
            if (o.placa != null)
              _linha(
                Icons.directions_car,
                o.modeloNome != null && o.modeloNome!.isNotEmpty
                    ? '${o.placa}  ·  ${o.modeloNome}'
                    : o.placa!,
              ),
            if (o.condutorNome != null)
              _linha(Icons.person, o.condutorNome!),
          ],
        ),
      ),
    );
  }

  Widget _linha(IconData ic, String txt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(ic, size: 18, color: Colors.black54),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              txt,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
