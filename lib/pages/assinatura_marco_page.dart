import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/bdt_service.dart';
import '../utils/logger.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/signature_pad.dart';

/// Argumentos passados ao empurrar a rota `/marco/assinatura`.
class AssinaturaMarcoArgs {
  final int bdtId;
  final String marco; // partida | apresentacao | embarque_passageiro | hora_saida
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
///
/// Sprint MUX (2026-07-24) — padrão de erro padronizado com os outros forms
/// do BDT (Abastecimento, Manutenção, Ocorrência): `formError` em banner
/// `errorContainer` no topo + `errorText` inline nos campos required. Fim
/// dos SnackBars invisíveis atrás do teclado / do menu do emulador.
class AssinaturaMarcoPage extends StatefulWidget {
  const AssinaturaMarcoPage({super.key});

  @override
  State<AssinaturaMarcoPage> createState() => _AssinaturaMarcoPageState();
}

class _AssinaturaMarcoPageState extends State<AssinaturaMarcoPage> {
  static const _log = Logger('SIG-PAGE');

  final _nomeCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  final _nomeFocus = FocusNode();
  final _signatureKey = GlobalKey<SignaturePadState>();

  String _tipo = 'condutor';

  /// Erro geral do form (backend recusou / falha de rede) — banner
  /// vermelho no topo, mesmo padrão das outras sheets.
  String? _formError;

  /// Erro específico do campo Nome (required inline).
  String? _nomeError;

  bool _busy = false;

  /// Nome do condutor logado, lido da sessão.
  ///
  /// Quem assina é o condutor na esmagadora maioria das vezes, e ele estava
  /// digitando o próprio nome inteiro a cada marco — no celular, muitas vezes
  /// em pé ao lado do veículo. O nome já está na sessão desde o login.
  String _nomeLogado = '';

  /// `true` quando quem assina NÃO é o condutor logado.
  ///
  /// Enquanto for `false` o campo fica travado com o nome da sessão, o que
  /// também evita erro de digitação no próprio nome — a assinatura é registro
  /// de quem esteve lá.
  bool _outroSignatario = false;

  @override
  void initState() {
    super.initState();
    _carregarNomeLogado();
  }

  Future<void> _carregarNomeLogado() async {
    final nome = await AuthService.getNomeLogado();

    if (!mounted) return;

    setState(() {
      _nomeLogado = nome;

      // Só preenche se o usuário ainda não digitou nada: `initState` dispara
      // uma vez, mas a leitura é assíncrona e não pode atropelar quem foi
      // mais rápido que o disco.
      if (!_outroSignatario && _nomeCtrl.text.trim().isEmpty) {
        _nomeCtrl.text = nome;
      }
    });
  }

  /// Alterna entre "sou eu" e "é outra pessoa".
  void _alternarSignatario(bool outro) {
    setState(() {
      _outroSignatario = outro;
      _nomeError = null;

      if (outro) {
        // Limpa para a pessoa digitar, em vez de deixar o nome do condutor
        // como rascunho a ser apagado.
        _nomeCtrl.clear();
        _tipo = 'passageiro';
      } else {
        _nomeCtrl.text = _nomeLogado;
        _tipo = 'condutor';
      }
    });

    if (outro) {
      FocusScope.of(context).requestFocus(_nomeFocus);
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _obsCtrl.dispose();
    _nomeFocus.dispose();
    super.dispose();
  }

  Future<void> _enviar(String svg, AssinaturaMarcoArgs args) async {
    if (_busy) return;

    // Limpa erros pra revalidar (padrão dos outros forms).
    setState(() {
      _formError = null;
      _nomeError = null;
    });

    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) {
      setState(() => _nomeError = 'Informe o nome do signatário.');
      FocusScope.of(context).requestFocus(_nomeFocus);
      return;
    }

    setState(() => _busy = true);
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
      _log.info(
        'marco ${args.marco} registrado assinaturaId=${res["assinatura_id"]}',
      );
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
      return;
    }

    // Mostra a MENSAGEM REAL do backend (não o genérico "Falha ao registrar
    // marco"). Ex.: "Ordem inválida", "BDT não pode receber marcos",
    // "Unknown column 'assinatura_svg'" (que indica migration pendente).
    final msg = (res['message']?.toString().trim() ?? '');
    setState(() {
      _busy = false;
      _formError = msg.isNotEmpty
          ? msg
          : 'Não foi possível registrar o marco. Verifique a conexão e tente de novo.';
    });
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
          if (_formError != null) ...[
            _bannerErro(_formError!),
            const SizedBox(height: 12),
          ],
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
                  const SizedBox(height: 4),

                  // Quem assina é o condutor quase sempre. O checkbox é a
                  // exceção, não o caminho comum — por isso vem marcado como
                  // "sou eu" e o campo nasce preenchido e travado.
                  CheckboxListTile(
                    value: _outroSignatario,
                    onChanged: _busy ? null : (v) => _alternarSignatario(v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Outra pessoa vai assinar'),
                    subtitle: _outroSignatario
                        ? null
                        : Text(
                            _nomeLogado.isEmpty ? 'Carregando…' : _nomeLogado,
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                  ),

                  const SizedBox(height: 8),
                  TextField(
                    controller: _nomeCtrl,
                    focusNode: _nomeFocus,
                    // Travado no nome da sessão enquanto for o condutor: a
                    // assinatura é registro de quem esteve lá, não campo livre.
                    //
                    // O `_nomeLogado.isEmpty` destrava o campo quando a sessão
                    // não trouxe o nome — o backend pode não ter devolvido
                    // `usuario.nome` no login. Sem esta condição o campo ficaria
                    // vazio E desabilitado, e ninguém conseguiria assinar.
                    enabled: !_busy && (_outroSignatario || _nomeLogado.isEmpty),
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) {
                      if (_nomeError != null) {
                        setState(() => _nomeError = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Nome completo *',
                      border: const OutlineInputBorder(),
                      errorText: _nomeError,
                      helperText: _outroSignatario
                          ? null
                          : (_nomeLogado.isEmpty
                              ? 'Não foi possível ler seu nome da sessão — digite'
                              : 'Você, pelo cadastro'),
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
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _tipo = v ?? 'condutor'),
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _obsCtrl,
                    enabled: !_busy,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Observações (opcional)',
                      border: OutlineInputBorder(),
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
}
