import 'package:flutter/material.dart';

import '../models/ocorrencia.dart';
import '../models/ocorrencia_filtros.dart';
import '../services/ocorrencia_service.dart';
import '../utils/date_fmt.dart';
import '../widgets/app_scaffold.dart';

/// Sprint W+M (Sprint 17 web — W15 F3) — Histórico institucional de
/// ocorrências. Lista todas as ocorrências registradas no sistema
/// (independente do BDT/condutor logado), com filtros opcionais por
/// veículo, condutor, tipo e período. Espelha a tela admin do web em
/// `/transporte/admin/ocorrencias/historico`.
///
/// UX: filtros ficam num painel expansível ("Filtros" no topo); a
/// lista abaixo é ordenada por data desc (mesmo do backend). Tap
/// numa linha abre o detalhe.
class HistoricoOcorrenciasPage extends StatefulWidget {
  const HistoricoOcorrenciasPage({super.key});

  @override
  State<HistoricoOcorrenciasPage> createState() =>
      _HistoricoOcorrenciasPageState();
}

class _HistoricoOcorrenciasPageState extends State<HistoricoOcorrenciasPage> {
  late Future<List<Ocorrencia>> _futureLista;
  late Future<OcorrenciaFiltros> _futureFiltros;

  // Filtros aplicados (null = sem filtro).
  int? _veiculoId;
  int? _condutorId;
  int? _tipoId;
  DateTime? _de;
  DateTime? _ate;

  bool _filtrosAbertos = false;

  @override
  void initState() {
    super.initState();
    _futureLista = OcorrenciaService.historico();
    _futureFiltros = OcorrenciaService.filtros();
  }

  Future<void> _reload() async {
    setState(() {
      _futureLista = OcorrenciaService.historico(
        veiculoId: _veiculoId,
        condutorId: _condutorId,
        tipoId: _tipoId,
        de: _de != null ? DateFmt.apiDate(_de!) : null,
        ate: _ate != null ? DateFmt.apiDate(_ate!) : null,
      );
    });
    await _futureLista;
  }

  Future<void> _limparFiltros() async {
    setState(() {
      _veiculoId = null;
      _condutorId = null;
      _tipoId = null;
      _de = null;
      _ate = null;
    });
    await _reload();
  }

  Future<void> _pickData(BuildContext ctx, bool isDe) async {
    final now = DateTime.now();
    final initial = (isDe ? _de : _ate) ?? now;
    final picked = await showDatePicker(
      context: ctx,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isDe) {
        _de = picked;
      } else {
        _ate = picked;
      }
    });
  }

  bool get _temFiltroAplicado =>
      _veiculoId != null ||
      _condutorId != null ||
      _tipoId != null ||
      _de != null ||
      _ate != null;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Ocorrências',
      subtitle: 'Histórico institucional',
      onRefresh: _reload,
      body: Column(
        children: [
          _painelFiltros(),
          const Divider(height: 1),
          Expanded(child: _lista()),
        ],
      ),
    );
  }

  Widget _painelFiltros() {
    return FutureBuilder<OcorrenciaFiltros>(
      future: _futureFiltros,
      builder: (context, snap) {
        final filtros = snap.data ?? const OcorrenciaFiltros();
        return ExpansionTile(
          initiallyExpanded: _filtrosAbertos,
          onExpansionChanged: (v) => setState(() => _filtrosAbertos = v),
          leading: const Icon(Icons.filter_list),
          title: const Text(
            'Filtros',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: _temFiltroAplicado
              ? Text(
                  _resumoFiltros(filtros),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                )
              : const Text(
                  'Nenhum aplicado',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            _dropdownFiltro(
              label: 'Veículo',
              items: filtros.veiculos,
              value: _veiculoId,
              onChanged: (v) => setState(() => _veiculoId = v),
            ),
            const SizedBox(height: 8),
            _dropdownFiltro(
              label: 'Condutor',
              items: filtros.condutores,
              value: _condutorId,
              onChanged: (v) => setState(() => _condutorId = v),
            ),
            const SizedBox(height: 8),
            _dropdownFiltro(
              label: 'Tipo de ocorrência',
              items: filtros.tipos,
              value: _tipoId,
              onChanged: (v) => setState(() => _tipoId = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _campoData('De', _de, isDe: true)),
                const SizedBox(width: 10),
                Expanded(child: _campoData('Até', _ate, isDe: false)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _temFiltroAplicado ? _limparFiltros : null,
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Limpar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.search),
                    label: const Text('Aplicar'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _dropdownFiltro({
    required String label,
    required List<OcorrenciaFiltroItem> items,
    required int? value,
    required void Function(int?) onChanged,
  }) {
    // `isDense: true` no InputDecoration deixava o topo do OutlineBorder
    // engolir o `labelText` (o "V" de "Veículo" ficava cortado no print
    // do usuário). Substituído por contentPadding explícito que reserva
    // espaço acima pro label caber inteiro sem overlap.
    return DropdownButtonFormField<int?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('Todos')),
        ...items.map(
          (i) => DropdownMenuItem<int?>(
            value: i.id,
            child: Text(i.label, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _campoData(String label, DateTime? valor, {required bool isDe}) {
    final txt = valor != null ? DateFmt.dataBr(valor) : '';
    return InkWell(
      onTap: () => _pickData(context, isDe),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: valor != null
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    if (isDe) {
                      _de = null;
                    } else {
                      _ate = null;
                    }
                  }),
                )
              : const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(
          txt.isEmpty ? '—' : txt,
          style: TextStyle(
            color: txt.isEmpty ? Colors.black38 : Colors.black87,
          ),
        ),
      ),
    );
  }

  String _resumoFiltros(OcorrenciaFiltros filtros) {
    final partes = <String>[];
    if (_veiculoId != null) {
      final v = filtros.veiculos.firstWhere(
        (i) => i.id == _veiculoId,
        orElse: () => const OcorrenciaFiltroItem(id: 0, label: ''),
      );
      partes.add('Veículo ${v.label.isEmpty ? "#$_veiculoId" : v.label}');
    }
    if (_condutorId != null) {
      final c = filtros.condutores.firstWhere(
        (i) => i.id == _condutorId,
        orElse: () => const OcorrenciaFiltroItem(id: 0, label: ''),
      );
      partes.add('Condutor ${c.label.isEmpty ? "#$_condutorId" : c.label}');
    }
    if (_tipoId != null) {
      final t = filtros.tipos.firstWhere(
        (i) => i.id == _tipoId,
        orElse: () => const OcorrenciaFiltroItem(id: 0, label: ''),
      );
      partes.add('Tipo ${t.label.isEmpty ? "#$_tipoId" : t.label}');
    }
    if (_de != null) partes.add('de ${DateFmt.dataBr(_de!)}');
    if (_ate != null) partes.add('até ${DateFmt.dataBr(_ate!)}');
    return partes.join(' · ');
  }

  Widget _lista() {
    return FutureBuilder<List<Ocorrencia>>(
      future: _futureLista,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data ?? const <Ocorrencia>[];
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Nenhuma ocorrência encontrada.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 0),
          itemBuilder: (_, i) => _linhaOcorrencia(items[i]),
        );
      },
    );
  }

  Widget _linhaOcorrencia(Ocorrencia o) {
    final subLinhas = <String>[];
    if (o.dataHora != null) subLinhas.add(DateFmt.dtCompact(o.dataHora));
    if (o.placa != null) subLinhas.add('🚗 ${o.placa}');
    if (o.condutorNome != null) subLinhas.add('👤 ${o.condutorNome}');
    if (o.bdtLabel != null) subLinhas.add(o.bdtLabel!);

    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFFFF3CD),
        foregroundColor: Color(0xFF856404),
        child: Icon(Icons.warning_amber_rounded),
      ),
      title: Text(
        o.titulo.isEmpty ? o.tipoNome : o.titulo,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (o.titulo.isNotEmpty)
            Text(
              o.tipoNome,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF856404),
              ),
            ),
          if (subLinhas.isNotEmpty)
            Text(
              subLinhas.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.black38),
      onTap: () => Navigator.pushNamed(
        context,
        '/ocorrencia/detalhe',
        arguments: o.id,
      ),
    );
  }
}
