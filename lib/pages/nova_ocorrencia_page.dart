import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/ocorrencia_filtros.dart';
import '../services/ocorrencia_service.dart';
import '../widgets/app_scaffold.dart';

/// Sprint W+M (Sprint 17 web — W15 F2) — Nova ocorrência no BDT.
///
/// Route: `/ocorrencia/nova` com argumento `int bdtId`.
///
/// Fase 1 (esta): form básico (tipo + título + descrição) → backend
/// grava linha em `trnsp_bdt_ocorrencias` com `fk_condutor = condutor
/// logado`. Fase 2 (futura): upload de fotos multipart + preview.
///
/// UX: dropdown de tipos vem do endpoint `bdt/ocorrencias/tipos`;
/// carregando em background enquanto o usuário digita título/descrição.
class NovaOcorrenciaPage extends StatefulWidget {
  const NovaOcorrenciaPage({super.key});

  @override
  State<NovaOcorrenciaPage> createState() => _NovaOcorrenciaPageState();
}

class _NovaOcorrenciaPageState extends State<NovaOcorrenciaPage> {
  Future<List<OcorrenciaFiltroItem>>? _futureTipos;

  final _tituloCtrl = TextEditingController();
  final _descricaoCtrl = TextEditingController();
  final _tituloFocus = FocusNode();
  final _picker = ImagePicker();
  int? _tipoId;

  bool _busy = false;
  String? _formError;
  String? _tituloError;
  String? _tipoError;

  /// Fotos escolhidas em memória (ainda não subidas). Ao clicar
  /// "Registrar", cria a ocorrência primeiro e depois faz upload
  /// de cada uma em sequência. Se um upload falhar, avisa mas mantém
  /// a ocorrência (podem ser tentadas de novo na tela de detalhe).
  final List<XFile> _fotosPending = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _futureTipos ??= OcorrenciaService.tipos();
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _descricaoCtrl.dispose();
    _tituloFocus.dispose();
    super.dispose();
  }

  int get _bdtId => ModalRoute.of(context)!.settings.arguments as int;

  Future<void> _adicionarFoto() async {
    // Bottom sheet perguntando câmera ou galeria — imagePicker do
    // package pede permissão nativa em runtime automaticamente.
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      final file = await _picker.pickImage(
        source: source,
        // Reduz consumo de banda no upload — o backend já converte pra WebP.
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (file == null || !mounted) return;
      setState(() => _fotosPending.add(file));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao acessar câmera/galeria: $e')),
      );
    }
  }

  Future<void> _salvar() async {
    if (_busy) return;

    // Limpa erros pra revalidação.
    setState(() {
      _formError = null;
      _tituloError = null;
      _tipoError = null;
    });

    final titulo = _tituloCtrl.text.trim();
    if (titulo.isEmpty) {
      setState(() => _tituloError = 'Informe um título curto do que aconteceu.');
      FocusScope.of(context).requestFocus(_tituloFocus);
      return;
    }
    if (_tipoId == null) {
      setState(() => _tipoError = 'Selecione o tipo da ocorrência.');
      return;
    }

    setState(() => _busy = true);
    final res = await OcorrenciaService.criar(
      bdtId: _bdtId,
      titulo: titulo,
      descricao: _descricaoCtrl.text,
      fkOcorrenciaTipo: _tipoId,
    );
    if (!mounted) return;

    if (res['success'] != true) {
      setState(() {
        _busy = false;
        _formError = (res['message']?.toString().trim().isNotEmpty ?? false)
            ? res['message'].toString()
            : 'Não foi possível registrar a ocorrência.';
      });
      return;
    }

    final ocId = ((res['data'] as Map?)?['id'] as int?) ?? 0;

    // Upload das fotos pendentes (sequencial pra manter ordem visual).
    int fotosOk = 0;
    int fotosFail = 0;
    if (ocId > 0 && _fotosPending.isNotEmpty) {
      for (final xfile in _fotosPending) {
        try {
          final bytes = await File(xfile.path).readAsBytes();
          final docId = await OcorrenciaService.uploadFoto(
            ocorrenciaId: ocId,
            bytes: bytes,
            filename: xfile.name,
          );
          if (docId > 0) {
            fotosOk++;
          } else {
            fotosFail++;
          }
        } catch (_) {
          fotosFail++;
        }
        if (!mounted) return;
      }
    }

    Navigator.pop(context, true);

    final msg = fotosFail > 0
        ? 'Ocorrência registrada — $fotosOk foto(s) OK, $fotosFail falhou(aram). '
            'Tente subir de novo pela tela de detalhe.'
        : (fotosOk > 0
            ? 'Ocorrência registrada com $fotosOk foto(s).'
            : 'Ocorrência registrada.');

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Nova ocorrência',
      subtitle: 'BDT #$_bdtId',
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Registre o que aconteceu — quanto mais claro, melhor. '
              'A ocorrência fica visível no histórico institucional depois.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            if (_formError != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Theme.of(context).colorScheme.errorContainer,
                ),
                child: Text(
                  _formError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _dropdownTipos(),
            const SizedBox(height: 12),
            TextField(
              controller: _tituloCtrl,
              focusNode: _tituloFocus,
              enabled: !_busy,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
              onChanged: (_) {
                if (_tituloError != null) {
                  setState(() => _tituloError = null);
                }
              },
              decoration: InputDecoration(
                labelText: 'Título *',
                helperText: 'Ex.: "Pneu furado na saída da UERJ"',
                border: const OutlineInputBorder(),
                errorText: _tituloError,
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descricaoCtrl,
              enabled: !_busy,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 5,
              maxLength: 1000,
              inputFormatters: [
                LengthLimitingTextInputFormatter(1000),
              ],
              decoration: const InputDecoration(
                labelText: 'Descrição',
                helperText: 'Opcional — contexto, causa, decisão tomada.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            _cardFotos(),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _salvar,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Registrar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardFotos() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Fotos (opcional)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _adicionarFoto,
                icon: const Icon(Icons.add_a_photo, size: 18),
                label: const Text('Adicionar'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_fotosPending.isEmpty)
            const Text(
              'Anexe se ajudar a documentar (avaria, marca no veículo, cena…).',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_fotosPending.length, (i) {
                final file = _fotosPending[i];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(file.path),
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: InkWell(
                        onTap: _busy
                            ? null
                            : () => setState(() => _fotosPending.removeAt(i)),
                        child: const CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget _dropdownTipos() {
    return FutureBuilder<List<OcorrenciaFiltroItem>>(
      future: _futureTipos,
      builder: (context, snap) {
        final items = snap.data ?? const <OcorrenciaFiltroItem>[];
        final carregando = snap.connectionState != ConnectionState.done;

        return DropdownButtonFormField<int?>(
          initialValue: _tipoId,
          isExpanded: true,
          onChanged: _busy || carregando
              ? null
              : (v) => setState(() {
                    _tipoId = v;
                    _tipoError = null;
                  }),
          decoration: InputDecoration(
            labelText: 'Tipo *',
            floatingLabelBehavior: FloatingLabelBehavior.always,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            errorText: _tipoError,
            helperText:
                carregando ? 'Carregando…' : 'Categoria (avaria, atraso, ...)',
          ),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('Selecione…'),
            ),
            ...items.map(
              (i) => DropdownMenuItem<int?>(
                value: i.id,
                child: Text(i.label, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        );
      },
    );
  }
}
