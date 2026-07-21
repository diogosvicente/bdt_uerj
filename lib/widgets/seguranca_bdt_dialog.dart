import 'package:flutter/material.dart';

import '../models/seguranca_texto.dart';
import '../services/bdt_service.dart';
import '../theme/app_theme.dart';

/// Dialog "Informações de Segurança" do BDT (Sprint M6 / Sprint 1 web).
///
/// Equivalente ao modal web `_modal_seguranca.php`: cada texto vira uma
/// seção com título + conteúdo (preservando quebras de linha). Textos
/// vêm do endpoint `bdt/seguranca/textos` (wrapper do serviço web) —
/// editáveis pelo admin sem redeploy.
///
/// Uso:
/// ```dart
/// await SegurancaBdtDialog.show(context);
/// ```
class SegurancaBdtDialog extends StatefulWidget {
  const SegurancaBdtDialog({super.key});

  /// Abre o dialog. Fetch dos textos acontece dentro — o caller não
  /// precisa carregar nada antes.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const SegurancaBdtDialog(),
    );
  }

  @override
  State<SegurancaBdtDialog> createState() => _SegurancaBdtDialogState();
}

class _SegurancaBdtDialogState extends State<SegurancaBdtDialog> {
  late Future<List<SegurancaTexto>> _future;

  @override
  void initState() {
    super.initState();
    _future = BdtService.listarSegurancaTextos();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            Flexible(child: _body()),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: Colors.white),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Informações de Segurança',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    return FutureBuilder<List<SegurancaTexto>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final itens = snap.data ?? const <SegurancaTexto>[];
        if (itens.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Nenhuma informação de segurança cadastrada.\n\n'
              'O administrador do Transporte pode cadastrar os textos '
              'em /transporte/admin/seguranca/textos.',
              style: TextStyle(color: Colors.black54),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          shrinkWrap: true,
          itemCount: itens.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _cardTexto(itens[i]),
        );
      },
    );
  }

  Widget _cardTexto(SegurancaTexto t) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
        color: const Color(0xFFFAFBFC),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.titulo,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          // `Text` já preserva '\n' automaticamente — mesmo comportamento
          // do `white-space: pre-wrap` no CSS do modal web.
          Text(
            t.conteudo,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Conteúdo institucional — editável pelo administrador.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}
