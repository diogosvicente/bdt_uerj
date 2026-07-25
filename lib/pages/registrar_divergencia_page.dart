import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/divergencia_service.dart';
import '../widgets/app_scaffold.dart';

/// Sprint 6 W+M — Registrar divergência de carga (mobile).
///
/// Route: `/bdt/divergencia/nova` com argumento `int bdtId`.
///
/// Fluxo:
///  1. Condutor descreve o que viu ("carga excedeu o peso declarado", etc.);
///  2. Opcionalmente informa peso/dimensões reais (medidos no destino);
///  3. Opcionalmente anexa fotos-prova (imagens);
///  4. "Registrar" grava no motor W10 (backend classifica se é `carga`
///     ou `carga_nao_prevista`). Admin decide no web (cancelar reabre
///     solicitação; prosseguir mantém tudo como está).
///
/// Regra [[bdt_uerj_sem_travas_so_alertas]]: se já existe divergência
/// pendente pra este BDT, o backend devolve `jaExistia=true` — a UI
/// mostra alerta amarelo mas prossegue (sobe fotos novas, se houver).
class RegistrarDivergenciaPage extends StatefulWidget {
  const RegistrarDivergenciaPage({super.key});

  @override
  State<RegistrarDivergenciaPage> createState() =>
      _RegistrarDivergenciaPageState();
}

class _RegistrarDivergenciaPageState extends State<RegistrarDivergenciaPage> {
  final _descCtrl = TextEditingController();
  final _pesoCtrl = TextEditingController();
  final _cmpCtrl = TextEditingController();
  final _lgrCtrl = TextEditingController();
  final _altCtrl = TextEditingController();
  final _descFocus = FocusNode();

  final _picker = ImagePicker();
  final List<XFile> _fotosPending = [];

  bool _busy = false;
  String? _formError;
  String? _formAlert; // banner amarelo (não bloqueia)
  String? _descError;

  final _decimal2 = FilteringTextInputFormatter.allow(
    RegExp(r'^\d*([.,]\d{0,2})?$'),
  );

  @override
  void dispose() {
    _descCtrl.dispose();
    _pesoCtrl.dispose();
    _cmpCtrl.dispose();
    _lgrCtrl.dispose();
    _altCtrl.dispose();
    _descFocus.dispose();
    super.dispose();
  }

  int get _bdtId => ModalRoute.of(context)!.settings.arguments as int;

  double? _parseDec(TextEditingController c) {
    final s = c.text.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    return double.tryParse(s);
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
      final f = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (f == null || !mounted) return;
      setState(() => _fotosPending.add(f));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao acessar câmera/galeria: $e')),
      );
    }
  }

  Future<void> _salvar() async {
    if (_busy) return;

    setState(() {
      _formError = null;
      _formAlert = null;
      _descError = null;
    });

    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      setState(() => _descError = 'Descreva o que aconteceu.');
      FocusScope.of(context).requestFocus(_descFocus);
      return;
    }

    setState(() => _busy = true);
    final res = await DivergenciaService.registrar(
      bdtId: _bdtId,
      descricao: desc,
      pesoKg: _parseDec(_pesoCtrl),
      comprimentoM: _parseDec(_cmpCtrl),
      larguraM: _parseDec(_lgrCtrl),
      alturaM: _parseDec(_altCtrl),
    );
    if (!mounted) return;

    if (!res.ok) {
      setState(() {
        _busy = false;
        _formError = res.mensagem;
      });
      return;
    }

    // Regra sem-travas: se já existia divergência, deixa prosseguir e só
    // avisa. Fotos novas serão anexadas à divergência existente.
    if (res.jaExistia) {
      setState(() => _formAlert = res.mensagem);
    }

    // Upload das fotos pendentes (sequencial, mesmo padrão dos outros
    // fluxos). Falha em uma não invalida o registro.
    int fotosOk = 0;
    int fotosFail = 0;
    if (res.id > 0 && _fotosPending.isNotEmpty) {
      for (final xfile in _fotosPending) {
        try {
          final bytes = await File(xfile.path).readAsBytes();
          final docId = await DivergenciaService.uploadFoto(
            divergenciaId: res.id,
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

    final base = res.jaExistia
        ? 'Divergência já existente atualizada'
        : 'Divergência registrada';
    final msgFotos = _fotosPending.isEmpty
        ? ''
        : fotosFail == 0
            ? ' — $fotosOk foto(s) enviada(s)'
            : ' — $fotosOk foto(s) OK, $fotosFail falhou(aram)';
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('$base.$msgFotos')));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Registrar divergência',
      subtitle: 'BDT #$_bdtId',
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Registre o que você observou no destino: a carga real bate '
              'com o que foi declarado? Se não, descreva a diferença. '
              'O admin decide depois — este registro é a sua prova.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            if (_formError != null) ...[
              _bannerErro(_formError!),
              const SizedBox(height: 12),
            ],
            if (_formAlert != null) ...[
              _bannerAviso(_formAlert!),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _descCtrl,
              focusNode: _descFocus,
              enabled: !_busy,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4,
              maxLength: 1000,
              onChanged: (_) {
                if (_descError != null) setState(() => _descError = null);
              },
              decoration: InputDecoration(
                labelText: 'O que aconteceu? *',
                helperText:
                    'Ex.: "Carga com 60kg em vez de 40kg declarados", '
                    '"Item extra fora do pedido"',
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
                errorText: _descError,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            _cardMedidas(),
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

  Widget _cardMedidas() {
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
          const Text(
            'Medidas reais (opcional)',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Se conseguir pesar/medir no destino, preencha — ajuda o admin '
            'a decidir com mais precisão.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pesoCtrl,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [_decimal2],
            decoration: const InputDecoration(
              labelText: 'Peso real (kg)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cmpCtrl,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_decimal2],
                  decoration: const InputDecoration(
                    labelText: 'Comprimento (m)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _lgrCtrl,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_decimal2],
                  decoration: const InputDecoration(
                    labelText: 'Largura (m)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _altCtrl,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_decimal2],
                  decoration: const InputDecoration(
                    labelText: 'Altura (m)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ],
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
                  'Fotos-prova (opcional)',
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
              'Anexe fotos da carga real (balança, medida, avaria…) '
              'pra fortalecer o registro.',
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

  Widget _bannerErro(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.errorContainer,
      ),
      child: Text(
        msg,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Banner amarelo — alerta que NÃO bloqueia (regra
  /// [[bdt_uerj_sem_travas_so_alertas]]).
  Widget _bannerAviso(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFFFFF3CD),
        border: Border.all(color: Colors.amber.shade700),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.amber.shade900, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
