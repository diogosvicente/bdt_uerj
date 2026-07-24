import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/ocorrencia_service.dart';

/// Argumentos do [FotoViewerPage] — carrega o `docId` + como baixar os
/// bytes. Sprint 18 W+M generalizou o viewer pra qualquer fluxo (foto de
/// abastecimento, manutenção, carga, ocorrência) — cada caller passa o
/// fetcher do seu service.
class FotoViewerArgs {
  final int docId;
  final Future<List<int>?> Function(int docId) fetcher;
  final String? titulo;

  const FotoViewerArgs({
    required this.docId,
    required this.fetcher,
    this.titulo,
  });
}

/// Viewer fullscreen pra fotos persistidas no servidor.
///
/// Route: `/foto/viewer`. Argumentos aceitos:
///  - `int docId` → shortcut retrocompat: baixa via
///    `OcorrenciaService.obterFoto` (comportamento pré-Sprint 18).
///  - [FotoViewerArgs] → genérico, o caller informa o fetcher.
///
/// Pinch-to-zoom via [InteractiveViewer].
class FotoViewerPage extends StatefulWidget {
  const FotoViewerPage({super.key});

  @override
  State<FotoViewerPage> createState() => _FotoViewerPageState();
}

class _FotoViewerPageState extends State<FotoViewerPage> {
  Uint8List? _bytes;
  bool _erro = false;
  String _titulo = 'Foto';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bytes != null || _erro) return;
    _load();
  }

  Future<void> _load() async {
    final raw = ModalRoute.of(context)!.settings.arguments;

    final int docId;
    final Future<List<int>?> Function(int) fetcher;
    if (raw is FotoViewerArgs) {
      docId = raw.docId;
      fetcher = raw.fetcher;
      if (raw.titulo != null) _titulo = raw.titulo!;
    } else if (raw is int) {
      // retrocompat Sprint 17 — só ocorrência passava aqui.
      docId = raw;
      fetcher = OcorrenciaService.obterFoto;
    } else {
      setState(() => _erro = true);
      return;
    }

    final bytes = await fetcher(docId);
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _erro = true);
      return;
    }
    setState(() => _bytes = Uint8List.fromList(bytes));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text(_titulo),
      ),
      body: Center(
        child: _bytes != null
            ? InteractiveViewer(
                maxScale: 5,
                child: Image.memory(_bytes!, fit: BoxFit.contain),
              )
            : _erro
                ? const Text(
                    'Falha ao carregar a foto.',
                    style: TextStyle(color: Colors.white70),
                  )
                : const CircularProgressIndicator(),
      ),
    );
  }
}
