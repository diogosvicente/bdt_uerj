import 'package:flutter/material.dart';

import '../models/checkup_bdt.dart';
import '../models/condutor_lite.dart';
import '../models/veiculo.dart';
import '../services/bdt_service.dart';
import '../utils/date_fmt.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/condutor_autocomplete.dart';
import '../widgets/veiculo_autocomplete.dart';

/// Sprint 15 W+M (2026-07-25/26) — Criar BDT sem solicitação (mobile).
///
/// Route: `/bdt/criar-direto`. Só chega aqui quem tem o gate
/// (admin do módulo Transporte OU papel `Criar BDT sem Solicitação`) —
/// a HomePage já esconde a opção do bottom sheet pra quem não tem.
///
/// Fluxo:
///  1. Escolhe VEÍCULO (autocomplete).
///  2. Escolhe CONDUTOR — "Para mim" (default, se o próprio usuário é
///     condutor) ou "Outro condutor" com autocomplete.
///  3. Escolhe DATA de referência (default: hoje).
///  4. Ao selecionar veículo/condutor, dispara `checkupVeiculo` em
///     background e mostra banner AMARELO se houver avisos (veículo em
///     manutenção, CNH vencida). Regra [[bdt_uerj_sem_travas_so_alertas]]:
///     NÃO bloqueia — só informa. Usuário confirma mesmo assim.
///  5. "Criar BDT" chama `criarBdtSemSolicitacao`. Backend cria o BDT
///     já em EM_ABERTO + solicitação sintética + designação, tudo em
///     uma transação (`BdtSemSolicitacaoService::criar` do web).
///  6. Sucesso → `pushReplacement` pra `/bdt` com o `bdt_id` novo.
///
/// Diferente da `PreBdtFormPage`, que cria em PENDENTE e depende de
/// aprovação admin. Este fluxo é pra emergência / tarefa pontual.
class CriarBdtPage extends StatefulWidget {
  const CriarBdtPage({super.key});

  @override
  State<CriarBdtPage> createState() => _CriarBdtPageState();
}

/// Modo do dropdown de condutor. `paraMim` = usa o próprio usuário
/// logado (backend resolve o condutor_id). `outro` = mostra seletor
/// de condutor específico e envia condutor_id explícito.
enum _ModoCondutor { paraMim, outro }

class _CriarBdtPageState extends State<CriarBdtPage> {
  Veiculo? _veiculo;
  DateTime _dataRef = DateTime.now();

  _ModoCondutor _modo = _ModoCondutor.paraMim;
  List<CondutorLite>? _condutores; // null = carregando, [] = falha/vazio
  CondutorLite? _souEu; // meu próprio condutor (se aplicável)
  CondutorLite? _condutorSelecionado; // usado no modo `outro`

  CheckupBdt? _checkup;
  bool _checkupCarregando = false;

  bool _busy = false;
  String? _formError;
  String? _veiculoError;
  String? _condutorError;

  @override
  void initState() {
    super.initState();
    _carregarCondutores();
  }

  Future<void> _carregarCondutores() async {
    final lista = await BdtService.listarCondutoresAtivos();
    if (!mounted) return;
    // "Sou eu" = o item marcado como souEu:true no backend. Se não tiver
    // (usuário é admin puro, sem cadastro de condutor), força o modo
    // "outro" e desabilita "Para mim" (o backend recusaria mesmo).
    final souEu = lista.where((c) => c.souEu).cast<CondutorLite?>().firstOrNull;
    setState(() {
      _condutores = lista;
      _souEu = souEu;
      if (souEu == null) _modo = _ModoCondutor.outro;
    });
    // Se estou no modo "para mim" e o meu condutor já existe, dispara
    // o checkup do veículo assim que o veículo for escolhido — usando
    // o meu condutor_id.
    if (_veiculo != null) _dispararCheckup();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Criar BDT direto',
      subtitle: 'Sem passar por aprovação',
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Use este fluxo em emergência ou tarefa pontual — o BDT '
              'já sai operacional (sem esperar aprovação). O admin pode '
              'revisar depois na tela web.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            if (_formError != null) ...[
              _bannerErro(_formError!),
              const SizedBox(height: 12),
            ],
            _cardVeiculo(),
            const SizedBox(height: 12),
            _cardCondutor(),
            const SizedBox(height: 12),
            _cardData(),
            if (_checkup != null && _checkup!.avisos.isNotEmpty) ...[
              const SizedBox(height: 12),
              _bannerCheckup(_checkup!),
            ],
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
                    onPressed: _busy ? null : _criar,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.rocket_launch),
                    label: const Text('Criar BDT'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardVeiculo() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Veículo *',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            VeiculoAutocomplete(
              initialValue: _veiculo,
              onChanged: (v) {
                setState(() {
                  _veiculo = v;
                  _veiculoError = null;
                  _checkup = null; // invalida checkup anterior
                });
                if (v != null) _dispararCheckup();
              },
            ),
            if (_veiculoError != null) ...[
              const SizedBox(height: 6),
              Text(
                _veiculoError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            if (_checkupCarregando) ...[
              const SizedBox(height: 8),
              Row(
                children: const [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Checando veículo…',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cardCondutor() {
    final theme = Theme.of(context);
    final carregando = _condutores == null;
    final semSouEu = !carregando && _souEu == null;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Condutor *',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              semSouEu
                  ? 'Você não é condutor cadastrado — escolha o condutor.'
                  : 'Padrão: "Para mim" (você mesmo).',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            SegmentedButton<_ModoCondutor>(
              segments: [
                ButtonSegment(
                  value: _ModoCondutor.paraMim,
                  icon: const Icon(Icons.person_outline),
                  label: Text(
                    _souEu?.nome.split(' ').first ?? 'Para mim',
                  ),
                  enabled: !semSouEu,
                ),
                const ButtonSegment(
                  value: _ModoCondutor.outro,
                  icon: Icon(Icons.people_alt_outlined),
                  label: Text('Outro'),
                ),
              ],
              selected: {_modo},
              onSelectionChanged: (s) {
                setState(() {
                  _modo = s.first;
                  _condutorError = null;
                  _checkup = null;
                });
                if (_veiculo != null) _dispararCheckup();
              },
            ),
            if (_modo == _ModoCondutor.outro) ...[
              const SizedBox(height: 10),
              if (carregando) ...[
                const Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Carregando condutores…',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ] else ...[
                CondutorAutocomplete(
                  condutores: _condutores!,
                  initialValue: _condutorSelecionado,
                  onChanged: (c) {
                    setState(() {
                      _condutorSelecionado = c;
                      _condutorError = null;
                      _checkup = null;
                    });
                    if (_veiculo != null && c != null) _dispararCheckup();
                  },
                ),
              ],
            ],
            if (_condutorError != null) ...[
              const SizedBox(height: 6),
              Text(
                _condutorError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cardData() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Data de referência',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _escolherData,
              icon: const Icon(Icons.calendar_today),
              label: Text(DateFmt.dataBr(_dataRef)),
            ),
            const SizedBox(height: 4),
            Text(
              'Dia em que a viagem acontece. Default: hoje.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _bannerCheckup(CheckupBdt c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFFFFF3CD),
        border: Border.all(color: Colors.amber.shade700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.amber.shade900, size: 20),
              const SizedBox(width: 8),
              Text(
                'Avisos do checkup',
                style: TextStyle(
                  color: Colors.amber.shade900,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final aviso in c.avisos)
            Padding(
              padding: const EdgeInsets.only(bottom: 2, left: 28),
              child: Text(
                '• $aviso',
                style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
              ),
            ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              'Informativo — você pode prosseguir mesmo assim.',
              style: TextStyle(
                color: Colors.amber.shade900,
                fontSize: 12,
                fontStyle: FontStyle.italic,
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

  Future<void> _escolherData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dataRef,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _dataRef = d);
  }

  int? _condutorIdEscolhido() {
    if (_modo == _ModoCondutor.paraMim) return _souEu?.id;
    return _condutorSelecionado?.id;
  }

  Future<void> _dispararCheckup() async {
    if (_veiculo == null) return;
    final condutorId = _condutorIdEscolhido();
    setState(() => _checkupCarregando = true);
    final c = await BdtService.checkupVeiculo(
      veiculoId: _veiculo!.id,
      condutorId: condutorId,
    );
    if (!mounted) return;
    setState(() {
      _checkup = c;
      _checkupCarregando = false;
    });
  }

  Future<void> _criar() async {
    if (_busy) return;
    setState(() {
      _formError = null;
      _veiculoError = null;
      _condutorError = null;
    });

    if (_veiculo == null) {
      setState(() => _veiculoError = 'Selecione um veículo.');
      return;
    }

    final condutorId = _condutorIdEscolhido();
    if (condutorId == null || condutorId <= 0) {
      setState(() {
        _condutorError = _modo == _ModoCondutor.outro
            ? 'Selecione um condutor.'
            : 'Você não é condutor — escolha "Outro" e selecione.';
      });
      return;
    }

    setState(() => _busy = true);
    final res = await BdtService.criarBdtSemSolicitacao(
      veiculoId: _veiculo!.id,
      condutorId: condutorId,
      dataReferencia: DateFmt.apiDate(_dataRef),
    );
    if (!mounted) return;

    if (res['success'] != true) {
      setState(() {
        _busy = false;
        _formError = (res['message']?.toString().trim().isNotEmpty ?? false)
            ? res['message'].toString()
            : 'Não foi possível criar o BDT.';
      });
      return;
    }

    final bdtId = res['bdt_id'];
    final protocolo = res['protocolo']?.toString() ?? '';
    if (bdtId is! int || bdtId <= 0) {
      setState(() {
        _busy = false;
        _formError = 'Backend devolveu resposta inesperada.';
      });
      return;
    }

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            protocolo.isEmpty ? 'BDT criado.' : 'BDT $protocolo criado.',
          ),
        ),
      );

    // Vai direto pro BDT novo — condutor já pode iniciar trecho.
    // pushReplacement evita voltar pra este form ao pressionar back.
    Navigator.pushReplacementNamed(context, '/bdt', arguments: bdtId);
  }
}
