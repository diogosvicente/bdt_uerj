import 'package:flutter/material.dart';

import '../services/foto_documento_client.dart';
import '../widgets/app_scaffold.dart';
import 'foto_galeria_page.dart';

/// Sprint MUX (2026-07-24) — page de "Ver detalhes" reusável pros
/// registros do BDT (Abastecimento / Manutenção / Ocorrência).
///
/// Route: `/registro/detalhe` com [RegistroBdtDetalheArgs] como argument.
///
/// # Por que uma page compartilhada
///
/// Os 3 fluxos precisam do MESMO layout:
///   - Header (título + subtítulo + ícone).
///   - N "linhas de contexto" (rótulo → valor).
///   - Card de descrição/observação (opcional).
///   - Botão "Ver fotos (N)" que abre [FotoGaleriaPage] (swipe + zoom).
///   - Botões Editar / Excluir no rodapé, ambos opcionais.
///
/// A ÚNICA diferença por fluxo é o CONTEÚDO (linhas + fetcher de fotos).
/// Duplicar 3 pages seria retrabalho — o caller monta o
/// [RegistroBdtDetalheArgs] e este widget renderiza tudo.
class RegistroBdtDetalheArgs {
  final String tituloAppBar;
  final String subtituloAppBar;

  /// Ícone grande do card de cabeçalho (ex.: local_gas_station, build).
  final IconData icone;

  /// Cor do card cabeçalho (fica no fundo). Ex.: âmbar pra ocorrência.
  final Color? corCabecalho;

  /// Título do cabeçalho (ex.: "Gasolina comum • 20 L • R$ 100,00").
  final String tituloRegistro;

  /// Data/hora formatada em BR (ex.: "24/07/2026 14:30"). Pode ser vazio.
  final String? dataHoraBr;

  /// Linhas rótulo → valor no card de contexto. Ordem preservada.
  final List<RegistroBdtLinha> linhas;

  /// Texto livre (observações). Se vazio, o card não é renderizado.
  final String? observacoes;

  /// Fotos anexadas — se vazia, o botão "Ver fotos" some.
  final List<FotoDocumentoRef> fotos;

  /// Callback pra baixar bytes de uma foto (passado pra galeria).
  final Future<List<int>?> Function(int docId) fotoFetcher;

  /// Título da galeria (ex.: "Fotos do Abastecimento #12").
  final String tituloGaleria;

  /// Callback do botão Editar. Se nulo, botão não aparece.
  /// Deve retornar `true` se algo foi editado (a page fecha e devolve
  /// esse valor pro caller — mesmo padrão das sheets).
  final Future<bool> Function(BuildContext ctx)? onEditar;

  /// Callback do botão Excluir. Se nulo, botão não aparece.
  /// Deve retornar `true` se apagou (page fecha devolvendo `true`).
  final Future<bool> Function(BuildContext ctx)? onExcluir;

  const RegistroBdtDetalheArgs({
    required this.tituloAppBar,
    required this.subtituloAppBar,
    required this.icone,
    this.corCabecalho,
    required this.tituloRegistro,
    this.dataHoraBr,
    this.linhas = const [],
    this.observacoes,
    this.fotos = const [],
    required this.fotoFetcher,
    required this.tituloGaleria,
    this.onEditar,
    this.onExcluir,
  });
}

class RegistroBdtLinha {
  final IconData icone;
  final String label;
  final String valor;
  const RegistroBdtLinha({
    required this.icone,
    required this.label,
    required this.valor,
  });
}

class RegistroBdtDetalhePage extends StatefulWidget {
  const RegistroBdtDetalhePage({super.key});

  @override
  State<RegistroBdtDetalhePage> createState() => _RegistroBdtDetalhePageState();
}

class _RegistroBdtDetalhePageState extends State<RegistroBdtDetalhePage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments
        as RegistroBdtDetalheArgs;

    return AppScaffold(
      title: args.tituloAppBar,
      subtitle: args.subtituloAppBar,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _cardCabecalho(args),
          if (args.linhas.isNotEmpty) ...[
            const SizedBox(height: 12),
            _cardContexto(args.linhas),
          ],
          if ((args.observacoes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _cardTexto('Observações', args.observacoes!),
          ],
          const SizedBox(height: 12),
          _cardFotos(args),
          const SizedBox(height: 20),
          _rodapeAcoes(args),
        ],
      ),
    );
  }

  Widget _cardCabecalho(RegistroBdtDetalheArgs a) {
    final cor = a.corCabecalho ?? Theme.of(context).colorScheme.primaryContainer;
    final onCor =
        ThemeData.estimateBrightnessForColor(cor) == Brightness.dark
            ? Colors.white
            : Colors.black87;

    return Card(
      elevation: 0,
      color: cor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(a.icone, color: onCor, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    a.tituloRegistro,
                    style: TextStyle(
                      color: onCor,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            if ((a.dataHoraBr ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: onCor.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Text(
                    a.dataHoraBr!,
                    style: TextStyle(fontSize: 13, color: onCor),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cardContexto(List<RegistroBdtLinha> linhas) {
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
              'Detalhes',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 10),
            for (final l in linhas) _linha(l),
          ],
        ),
      ),
    );
  }

  Widget _cardTexto(String titulo, String conteudo) {
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
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Text(conteudo, style: const TextStyle(fontSize: 14, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _cardFotos(RegistroBdtDetalheArgs a) {
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
            Row(
              children: [
                const Icon(Icons.photo_library,
                    size: 16, color: Colors.black54),
                const SizedBox(width: 6),
                const Text(
                  'Fotos',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(${a.fotos.length})',
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (a.fotos.isEmpty)
              const Text(
                'Sem fotos anexadas.',
                style: TextStyle(color: Colors.black45, fontSize: 13),
              )
            else
              FilledButton.tonalIcon(
                onPressed: () => _abrirGaleria(a),
                icon: const Icon(Icons.zoom_out_map, size: 18),
                label: Text(
                  a.fotos.length == 1
                      ? 'Ver foto em tela cheia'
                      : 'Ver ${a.fotos.length} fotos em tela cheia',
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _abrirGaleria(RegistroBdtDetalheArgs a) {
    final items = a.fotos
        .map((f) => FotoGaleriaItem(
              docId: f.id,
              fetcher: a.fotoFetcher,
              label: (f.descricao?.trim().isNotEmpty ?? false)
                  ? f.descricao!
                  : '',
            ))
        .toList();
    Navigator.pushNamed(
      context,
      '/foto/galeria',
      arguments: FotoGaleriaArgs(
        fotos: items,
        indiceInicial: 0,
        titulo: a.tituloGaleria,
      ),
    );
  }

  Widget _rodapeAcoes(RegistroBdtDetalheArgs a) {
    final hasEditar = a.onEditar != null;
    final hasExcluir = a.onExcluir != null;
    if (!hasEditar && !hasExcluir) return const SizedBox.shrink();

    return Row(
      children: [
        if (hasExcluir)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final excluiu = await a.onExcluir!(context);
                      if (!mounted) return;
                      if (excluiu) {
                        Navigator.pop(context, true);
                      } else {
                        setState(() => _busy = false);
                      }
                    },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Excluir'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
              ),
            ),
          ),
        if (hasEditar && hasExcluir) const SizedBox(width: 10),
        if (hasEditar)
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final ok = await a.onEditar!(context);
                      if (!mounted) return;
                      if (ok) {
                        // Fecha devolvendo true — o caller recarrega
                        // sua lista e o card reflete os dados novos.
                        Navigator.pop(context, true);
                      } else {
                        setState(() => _busy = false);
                      }
                    },
              icon: const Icon(Icons.edit),
              label: const Text('Editar'),
            ),
          ),
      ],
    );
  }

  Widget _linha(RegistroBdtLinha l) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(l.icone, size: 18, color: Colors.black54),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              l.label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              l.valor.isEmpty ? '—' : l.valor,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
