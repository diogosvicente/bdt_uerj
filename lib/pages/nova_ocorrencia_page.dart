import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  int? _tipoId;

  bool _busy = false;
  String? _formError;
  String? _tituloError;
  String? _tipoError;

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

    if (res['success'] == true) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Ocorrência registrada.')),
        );
      return;
    }

    setState(() {
      _busy = false;
      _formError = (res['message']?.toString().trim().isNotEmpty ?? false)
          ? res['message'].toString()
          : 'Não foi possível registrar a ocorrência.';
    });
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
            const SizedBox(height: 16),
            const Text(
              'Fotos entram numa próxima versão do app — por enquanto, '
              'anexe pela web depois se precisar.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
