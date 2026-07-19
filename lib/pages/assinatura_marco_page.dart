import 'package:flutter/material.dart';

import '../services/bdt_service.dart';
import '../utils/logger.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/signature_pad.dart';

/// Argumentos passados ao empurrar a rota `/marco/assinatura`.
class AssinaturaMarcoArgs {
  final int bdtId;
  final String marco; // partida | apresentacao | embarque_passageiro
  final String labelMarco;

  const AssinaturaMarcoArgs({
    required this.bdtId,
    required this.marco,
    required this.labelMarco,
  });
}

/// Página de registro de marco COM assinatura touch (Sprint M4).
///
/// Fluxo:
/// 1. Usuário digita o nome do signatário e escolhe o tipo (padrão condutor).
/// 2. Desenha a assinatura no painel.
/// 3. "Confirmar assinatura" envia POST bdt/jornada/marco com o SVG.
class AssinaturaMarcoPage extends StatefulWidget {
  const AssinaturaMarcoPage({super.key});

  @override
  State<AssinaturaMarcoPage> createState() => _AssinaturaMarcoPageState();
}

class _AssinaturaMarcoPageState extends State<AssinaturaMarcoPage> {
  static const _log = Logger('SIG-PAGE');

  final _nomeCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  final _signatureKey = GlobalKey<SignaturePadState>();

  String _tipo = 'condutor';

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar(String svg, AssinaturaMarcoArgs args) async {
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) {
      _snack('Informe o nome do signatário.');
      return;
    }

    final res = await BdtService.registrarMarcoComAssinatura(
      bdtId: args.bdtId,
      marco: args.marco,
      observacao: _obsCtrl.text.trim(),
      assinaturaSvg: svg,
      signatarioNome: nome,
      signatarioTipo: _tipo,
    );

    if (!mounted) return;
    if (res['success'] == true) {
      _log.info('marco ${args.marco} registrado assinaturaId=${res["assinatura_id"]}');
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Marco registrado'),
          content: Text(
            '"${args.labelMarco}" foi registrado com sua assinatura.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true); // devolve `true` = confirmado
    } else {
      _snack(res['message']?.toString() ?? 'Falha ao registrar marco.');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments
        as AssinaturaMarcoArgs;

    return AppScaffold(
      title: 'Assinatura',
      subtitle: args.labelMarco,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Signatário',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nomeCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome completo',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _tipo,
                    items: const [
                      DropdownMenuItem(value: 'condutor',   child: Text('Condutor')),
                      DropdownMenuItem(value: 'passageiro', child: Text('Passageiro')),
                      DropdownMenuItem(value: 'outro',      child: Text('Outro')),
                    ],
                    onChanged: (v) => setState(() => _tipo = v ?? 'condutor'),
                    decoration: const InputDecoration(labelText: 'Tipo'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _obsCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Observações (opcional)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Assinatura',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Assine no espaço abaixo. Use o dedo ou uma caneta touch.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  SignaturePad(
                    key: _signatureKey,
                    height: 240,
                    onConfirmed: (svg) => _enviar(svg, args),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
