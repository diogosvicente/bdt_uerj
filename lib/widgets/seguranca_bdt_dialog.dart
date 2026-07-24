import 'package:flutter/material.dart';

import '../models/seguranca_texto.dart';
import '../services/bdt_service.dart';
import '../theme/app_theme.dart';
import 'contato_auto_link.dart';

/// Dialog "Informações de Segurança" do BDT (Sprint M6 / Sprint 1 web).
///
/// Equivalente ao modal web `_modal_seguranca.php`: cada texto vira uma
/// seção com título + conteúdo (preservando quebras de linha). Textos
/// vêm do endpoint `bdt/seguranca/textos` (wrapper do serviço web) —
/// editáveis pelo admin sem redeploy.
///
/// Sprint MUX — quando o caller passa [bdtId], o dialog também busca a
/// apólice + seguradora do veículo (`bdt/seguro`) e adiciona uma seção
/// no topo com telefone / WhatsApp / e-mail clicáveis. Assim, em caso
/// de sinistro, o condutor tem os contatos da seguradora à mão sem sair
/// deste modal.
///
/// Uso:
/// ```dart
/// await SegurancaBdtDialog.show(context, bdtId: 42);
/// ```
class SegurancaBdtDialog extends StatefulWidget {
  /// Se informado, o dialog carrega e mostra a seção "Seguradora / Apólice"
  /// do veículo deste BDT. Se null, mostra só os textos institucionais.
  final int? bdtId;

  const SegurancaBdtDialog({super.key, this.bdtId});

  /// Abre o dialog. Fetch dos textos (e da apólice, se `bdtId` != null)
  /// acontece dentro — o caller não precisa carregar nada antes.
  static Future<void> show(BuildContext context, {int? bdtId}) {
    return showDialog<void>(
      context: context,
      builder: (_) => SegurancaBdtDialog(bdtId: bdtId),
    );
  }

  @override
  State<SegurancaBdtDialog> createState() => _SegurancaBdtDialogState();
}

class _SegurancaBdtDialogState extends State<SegurancaBdtDialog> {
  late Future<List<SegurancaTexto>> _textos;
  Future<Map<String, dynamic>?>? _seguro;

  @override
  void initState() {
    super.initState();
    _textos = BdtService.listarSegurancaTextos();
    if (widget.bdtId != null && widget.bdtId! > 0) {
      _seguro = BdtService.getSeguroDoBdt(widget.bdtId!);
    }
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      shrinkWrap: true,
      children: [
        // Sprint MUX — Seguradora no TOPO: em sinistro, é o contato mais
        // urgente. Só aparece se `bdtId` foi passado E o veículo tem
        // apólice cadastrada; caso contrário, esconde silenciosamente.
        if (_seguro != null) _cardSeguradora(),
        _listaTextos(),
      ],
    );
  }

  Widget _cardSeguradora() {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _seguro,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text(
                  'Carregando dados da seguradora…',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          );
        }
        final data = snap.data;
        if (data == null) return const SizedBox.shrink();

        final seguradora = (data['seguradora'] as Map?) ?? const {};
        final apolice = (data['apolice'] as Map?) ?? const {};
        final nome = (seguradora['nome'] ?? '').toString();
        if (nome.isEmpty) return const SizedBox.shrink();

        // Monta um único blob de texto pra reusar o ContatoAutoLink,
        // que já parseia telefone / whatsapp / e-mail / URL e vira link.
        // Só entram os campos preenchidos — nada de "Telefone: null".
        final linhas = <String>[];
        void addSe(String label, dynamic v) {
          final s = (v ?? '').toString().trim();
          if (s.isNotEmpty) linhas.add('$label: $s');
        }
        addSe('WhatsApp', seguradora['whatsapp1']);
        addSe('WhatsApp', seguradora['whatsapp2']);
        addSe('Telefone', seguradora['telefone1']);
        addSe('Telefone', seguradora['telefone2']);
        addSe('Telefone', seguradora['telefone3']);
        addSe('E-mail', seguradora['email']);
        addSe('Site', seguradora['site']);
        final contatos = linhas.join('\n');

        // Metadados curtos da apólice (compacto — não é o foco).
        final numero = (apolice['numero_apolice'] ?? '').toString();
        final validade = (apolice['fim_vigencia'] ?? '').toString();

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFB8DAFF)),
              color: const Color(0xFFEAF3FF),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      size: 18,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Seguradora: $nome',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                if (numero.isNotEmpty || validade.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (numero.isNotEmpty) 'Apólice $numero',
                      if (validade.isNotEmpty) 'vigência até $validade',
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ],
                if (contatos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ContatoAutoLink(texto: contatos),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _listaTextos() {
    return FutureBuilder<List<SegurancaTexto>>(
      future: _textos,
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
        return Column(
          children: [
            for (int i = 0; i < itens.length; i++) ...[
              _cardTexto(itens[i]),
              if (i < itens.length - 1) const SizedBox(height: 12),
            ],
          ],
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
          // Sprint W+M — o `ContatoAutoLink` preserva '\n' (SelectableText.rich)
          // E parseia telefone / WhatsApp / email / URL virando link
          // clicável (tel:/wa.me/mailto:/https:). Antes o condutor
          // precisava copiar/discar manualmente.
          ContatoAutoLink(texto: t.conteudo),
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
