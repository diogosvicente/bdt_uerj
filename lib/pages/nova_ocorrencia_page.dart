import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/ocorrencia_filtros.dart';
import '../services/ocorrencia_service.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/foto_documento_thumb.dart';

/// Sprint W+M (Sprint 17 W+M — W15 F2) / Sprint 18.1 — Registrar OU editar
/// uma ocorrência do BDT.
///
/// Route: `/ocorrencia/nova`. Argumentos aceitos:
///  - `int bdtId` → modo CRIAÇÃO (Sprint 17).
///  - [OcorrenciaFormArgs] com `bdtId` + `ocorrenciaId` → modo EDIÇÃO
///    (Sprint 18.1). Pré-carrega os campos existentes + fotos já
///    persistidas. Salvar chama `atualizar` em vez de `criar`.
///
/// Fluxo de fotos:
///  - **Existentes** (só edição): vêm de `listarFotos(ocId)`. Miniatura
///    é [FotoDocumentoThumb] baixando via `OcorrenciaService.obterFoto`.
///    Botão X exclui direto no servidor.
///  - **Pendentes** (câmera/galeria): vivem em `_fotosPending` até salvar.
///    Uma vez que temos `ocorrenciaId` (após criar OU já em edit), os
///    uploads sobem em batch.
class OcorrenciaFormArgs {
  final int bdtId;
  final int? ocorrenciaId;
  final String? tituloInicial;
  final String? descricaoInicial;
  final int? tipoInicial;
  final String? dataHoraInicial;

  const OcorrenciaFormArgs({
    required this.bdtId,
    this.ocorrenciaId,
    this.tituloInicial,
    this.descricaoInicial,
    this.tipoInicial,
    this.dataHoraInicial,
  });
}

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

  /// Args parsed do route (bdtId sempre; ocorrenciaId só em edit).
  int _bdtId = 0;
  int? _ocorrenciaId;
  String? _dataHoraInicial;
  bool _argsAplicados = false;

  bool get _isEdit => _ocorrenciaId != null && _ocorrenciaId! > 0;

  final List<XFile> _fotosPending = [];
  List<OcorrenciaFotoRef> _fotosExistentes = [];
  bool _carregandoFotos = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _futureTipos ??= OcorrenciaService.tipos();
    if (!_argsAplicados) {
      _aplicarArgs();
      _argsAplicados = true;
    }
  }

  void _aplicarArgs() {
    final raw = ModalRoute.of(context)!.settings.arguments;
    if (raw is OcorrenciaFormArgs) {
      _bdtId = raw.bdtId;
      _ocorrenciaId = raw.ocorrenciaId;
      _tituloCtrl.text = raw.tituloInicial ?? '';
      _descricaoCtrl.text = raw.descricaoInicial ?? '';
      _tipoId = raw.tipoInicial;
      _dataHoraInicial = raw.dataHoraInicial;
    } else if (raw is int) {
      _bdtId = raw;
    }
    if (_isEdit) {
      // ignore: discarded_futures
      _carregarFotosExistentes();
    }
  }

  Future<void> _carregarFotosExistentes() async {
    if (!_isEdit) return;
    setState(() => _carregandoFotos = true);
    final refs = await OcorrenciaService.listarFotos(_ocorrenciaId!);
    if (!mounted) return;
    setState(() {
      _fotosExistentes = refs;
      _carregandoFotos = false;
    });
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _descricaoCtrl.dispose();
    _tituloFocus.dispose();
    super.dispose();
  }

  Future<void> _adicionarFoto() async {
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

  Future<void> _excluirFotoExistente(int docId) async {
    final ok = await OcorrenciaService.excluirFoto(docId);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falha ao excluir foto.')),
      );
      return;
    }
    FotoDocumentoThumb.invalidate(
      cacheNamespace: 'ocorrencia',
      docId: docId,
    );
    setState(() {
      _fotosExistentes = _fotosExistentes.where((f) => f.id != docId).toList();
    });
  }

  Future<void> _salvar() async {
    if (_busy) return;

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

    // Rota: criar vs atualizar.
    final Map<String, dynamic> res;
    int ocId;
    if (_isEdit) {
      ocId = _ocorrenciaId!;
      res = await OcorrenciaService.atualizar(
        id: ocId,
        titulo: titulo,
        descricao: _descricaoCtrl.text,
        fkOcorrenciaTipo: _tipoId,
        dataHora: _dataHoraInicial,
      );
    } else {
      res = await OcorrenciaService.criar(
        bdtId: _bdtId,
        titulo: titulo,
        descricao: _descricaoCtrl.text,
        fkOcorrenciaTipo: _tipoId,
      );
      ocId = ((res['data'] as Map?)?['id'] as int?) ?? 0;
    }

    if (!mounted) return;

    if (res['success'] != true) {
      setState(() {
        _busy = false;
        _formError = (res['message']?.toString().trim().isNotEmpty ?? false)
            ? res['message'].toString()
            : (_isEdit
                ? 'Não foi possível atualizar a ocorrência.'
                : 'Não foi possível registrar a ocorrência.');
      });
      return;
    }

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

    final verb = _isEdit ? 'atualizada' : 'registrada';
    final msg = fotosFail > 0
        ? 'Ocorrência $verb — $fotosOk foto(s) OK, $fotosFail falhou(aram). '
            'Tente subir de novo abrindo pra editar.'
        : (fotosOk > 0
            ? 'Ocorrência $verb com $fotosOk foto(s) nova(s).'
            : 'Ocorrência $verb.');

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _isEdit ? 'Editar ocorrência' : 'Nova ocorrência',
      subtitle: 'BDT #$_bdtId',
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEdit
                  ? 'Ajuste os campos abaixo. Fotos novas vão em cima das já anexadas.'
                  : 'Registre o que aconteceu — quanto mais claro, melhor. '
                      'A ocorrência fica visível no histórico institucional depois.',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
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
                    label: Text(_isEdit ? 'Salvar' : 'Registrar'),
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
          if (_isEdit && _carregandoFotos) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Carregando fotos existentes…',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
          ],
          if (_fotosExistentes.isEmpty && _fotosPending.isEmpty && !_carregandoFotos)
            const Text(
              'Anexe se ajudar a documentar (avaria, marca no veículo, cena…).',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in _fotosExistentes)
                  _tileExistente(f),
                for (int i = 0; i < _fotosPending.length; i++)
                  _tilePendente(i),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tileExistente(OcorrenciaFotoRef f) {
    return SizedBox(
      width: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FotoDocumentoThumb(
            docId: f.id,
            fetcher: OcorrenciaService.obterFoto,
            cacheNamespace: 'ocorrencia',
            size: 88,
          ),
          Positioned(
            top: -8,
            right: -8,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _busy ? null : () => _excluirFotoExistente(f.id),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tilePendente(int i) {
    final file = _fotosPending[i];
    return SizedBox(
      width: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(file.path),
              width: 88,
              height: 88,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: -8,
            right: -8,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _busy
                    ? null
                    : () => setState(() => _fotosPending.removeAt(i)),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 14),
                ),
              ),
            ),
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
