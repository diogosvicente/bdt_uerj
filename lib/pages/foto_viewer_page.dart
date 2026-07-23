import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/ocorrencia_service.dart';

/// Viewer fullscreen pra fotos de ocorrência já persistidas.
///
/// Route: `/foto/viewer` com argumento `int docId`. Baixa o binário
/// completo (o `FotoOcorrenciaThumb` do grid tinha só a thumb) e
/// mostra com pinch-to-zoom via [InteractiveViewer].
class FotoViewerPage extends StatefulWidget {
  const FotoViewerPage({super.key});

  @override
  State<FotoViewerPage> createState() => _FotoViewerPageState();
}

class _FotoViewerPageState extends State<FotoViewerPage> {
  Uint8List? _bytes;
  bool _erro = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bytes != null || _erro) return;
    _load();
  }

  Future<void> _load() async {
    final docId = ModalRoute.of(context)!.settings.arguments as int;
    final bytes = await OcorrenciaService.obterFoto(docId);
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
        title: const Text('Foto'),
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
