import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Sprint 18.2 — visualizador full-screen com swipe entre fotos.
///
/// Substitui [FotoViewerPage] pro caso comum (galeria de mais de 1 foto).
/// [FotoViewerPage] segue registrado por retrocompat de callers antigos
/// que passavam só `int docId`, mas novos entrypoints devem usar esta.
///
/// Route: `/foto/galeria` — argumento: [FotoGaleriaArgs].
///
/// UX:
/// - PageView horizontal (arrasta pros lados).
/// - Header: contador "N/M" + label do tipo (Odômetro / Antes / etc.)
///   da foto atual.
/// - Pinch-to-zoom via [InteractiveViewer] em cada página.
/// - Fecha com back / X.
///
/// Cada foto é baixada via `fetcher(docId)` sob demanda — a lib
/// preserva o cache por `cacheNamespace` (mesma convenção do
/// [FotoDocumentoThumb]). Aqui esse cache não é usado (chamamos direto
/// o fetcher), mas o backend serve o mesmo binário via ETag → o cliente
/// HTTP pode revalidar rapidinho.
class FotoGaleriaArgs {
  final List<FotoGaleriaItem> fotos;

  /// Índice da foto a exibir primeiro. Fora do range → 0.
  final int indiceInicial;

  /// Título do header (ex: "Fotos do Abastecimento #12", "Ocorrência 3").
  final String titulo;

  const FotoGaleriaArgs({
    required this.fotos,
    this.indiceInicial = 0,
    this.titulo = 'Fotos',
  });
}

class FotoGaleriaItem {
  final int docId;
  final Future<List<int>?> Function(int docId) fetcher;

  /// Legenda exibida no footer (ex.: "Odômetro", "Antes", "Nota Fiscal").
  /// Pode ser vazia — o footer se auto-esconde.
  final String label;

  const FotoGaleriaItem({
    required this.docId,
    required this.fetcher,
    this.label = '',
  });
}

class FotoGaleriaPage extends StatefulWidget {
  const FotoGaleriaPage({super.key});

  @override
  State<FotoGaleriaPage> createState() => _FotoGaleriaPageState();
}

class _FotoGaleriaPageState extends State<FotoGaleriaPage> {
  late final PageController _pageCtrl;
  late FotoGaleriaArgs _args;
  int _idx = 0;
  bool _inicializado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inicializado) return;
    final raw = ModalRoute.of(context)!.settings.arguments;
    if (raw is FotoGaleriaArgs && raw.fotos.isNotEmpty) {
      _args = raw;
      _idx = raw.indiceInicial >= 0 && raw.indiceInicial < raw.fotos.length
          ? raw.indiceInicial
          : 0;
    } else {
      _args = const FotoGaleriaArgs(fotos: []);
      _idx = 0;
    }
    _pageCtrl = PageController(initialPage: _idx);
    _inicializado = true;
  }

  @override
  void dispose() {
    if (_inicializado) _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fotos = _args.fotos;
    final total = fotos.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        // Contador N/M grande e legível — o condutor precisa saber
        // "estou onde" antes de arrastar.
        title: Text(
          total <= 1
              ? _args.titulo
              : '${_idx + 1}/$total · ${_args.titulo}',
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: total == 0
          ? const Center(
              child: Text(
                'Nenhuma foto.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _pageCtrl,
                    itemCount: total,
                    onPageChanged: (i) => setState(() => _idx = i),
                    itemBuilder: (_, i) => _FotoPage(item: fotos[i]),
                  ),
                ),
                _footer(fotos),
              ],
            ),
    );
  }

  Widget _footer(List<FotoGaleriaItem> fotos) {
    final label = fotos[_idx].label.trim();
    if (label.isEmpty && fotos.length <= 1) return const SizedBox.shrink();
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label.isEmpty ? 'Sem legenda' : label,
                style: TextStyle(
                  color: label.isEmpty ? Colors.white54 : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontStyle: label.isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
            if (fotos.length > 1) ...[
              _NavButton(
                icone: Icons.chevron_left,
                onTap: _idx > 0
                    ? () => _pageCtrl.previousPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        )
                    : null,
              ),
              const SizedBox(width: 6),
              _NavButton(
                icone: Icons.chevron_right,
                onTap: _idx < fotos.length - 1
                    ? () => _pageCtrl.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        )
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icone;
  final VoidCallback? onTap;

  const _NavButton({required this.icone, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkResponse(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? Colors.white24 : Colors.white10,
        ),
        child: Icon(
          icone,
          color: enabled ? Colors.white : Colors.white38,
        ),
      ),
    );
  }
}

/// Carrega e mostra UMA foto — reusada dentro do PageView. Cache local
/// por estado pra não rebaixar ao voltar; se sair da árvore por scroll
/// distante, PageView descarta e refaz na volta.
class _FotoPage extends StatefulWidget {
  final FotoGaleriaItem item;
  const _FotoPage({required this.item});

  @override
  State<_FotoPage> createState() => _FotoPageState();
}

class _FotoPageState extends State<_FotoPage> {
  Uint8List? _bytes;
  bool _erro = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await widget.item.fetcher(widget.item.docId);
    if (!mounted) return;
    if (b == null || b.isEmpty) {
      setState(() => _erro = true);
      return;
    }
    setState(() => _bytes = Uint8List.fromList(b));
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: Image.memory(_bytes!, fit: BoxFit.contain),
        ),
      );
    }
    if (_erro) {
      return const Center(
        child: Text(
          'Falha ao carregar esta foto.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return const Center(
      child: CircularProgressIndicator(color: Colors.white70),
    );
  }
}
