import 'dart:async';

import 'package:flutter/material.dart';

import '../models/veiculo.dart';
import '../services/bdt_service.dart';
import '../theme/app_theme.dart';

/// Autocomplete de veículo — abre um menu suspenso conforme o usuário
/// digita placa/modelo/marca.
///
/// Otimizações UX:
/// - **Debounce de 250ms** — não faz uma requisição por tecla.
/// - **Cache do último resultado** — se o usuário volta a digitar o mesmo
///   prefixo, mostra instantaneamente.
/// - **Estado de loading** dentro do próprio dropdown (sem bloquear a UI).
/// - **Chip de seleção** — depois de escolher, mostra placa + marca +
///   modelo num card compacto com botão "trocar".
/// - **Placas em maiúsculas** — auto-uppercase enquanto digita.
///
/// Ver `docs/ARCHITECTURE.md` §4.8 para o padrão de widget composto.
class VeiculoAutocomplete extends StatefulWidget {
  /// Callback quando o usuário confirma um veículo (clica ou tecla Enter).
  final ValueChanged<Veiculo?> onChanged;

  /// Valor inicial (edição).
  final Veiculo? initialValue;

  const VeiculoAutocomplete({
    super.key,
    required this.onChanged,
    this.initialValue,
  });

  @override
  State<VeiculoAutocomplete> createState() => _VeiculoAutocompleteState();
}

class _VeiculoAutocompleteState extends State<VeiculoAutocomplete> {
  Veiculo? _selecionado;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  // Cache simples: última busca (q → resultado). Serve pra evitar
  // requisição repetida se o usuário apagar e digitar o mesmo prefixo.
  String? _cachedQ;
  List<Veiculo> _cachedResult = const [];

  @override
  void initState() {
    super.initState();
    _selecionado = widget.initialValue;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Chamado por cada tecla no campo de busca do Autocomplete.
  /// Retorna a lista de opções (Autocomplete espera Iterable).
  Future<List<Veiculo>> _fetchOptions(String q) async {
    final query = q.trim();
    if (_cachedQ != null && _cachedQ == query) {
      return _cachedResult;
    }
    final result = await BdtService.buscarVeiculos(q: query);
    _cachedQ = query;
    _cachedResult = result;
    return result;
  }

  /// Debounce em cima do fetch — o Autocomplete chama optionsBuilder a
  /// cada tecla; nós esperamos 250ms parados antes de bater no backend.
  Future<Iterable<Veiculo>> _debouncedFetch(TextEditingValue tev) async {
    _debounce?.cancel();
    final completer = Completer<List<Veiculo>>();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final result = await _fetchOptions(tev.text);
        if (!completer.isCompleted) completer.complete(result);
      } catch (e) {
        if (!completer.isCompleted) completer.complete(<Veiculo>[]);
      }
    });
    return completer.future;
  }

  void _selecionar(Veiculo v) {
    setState(() => _selecionado = v);
    widget.onChanged(v);
  }

  void _trocar() {
    setState(() => _selecionado = null);
    _cachedQ = null;
    _searchCtrl.clear();
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    if (_selecionado != null) return _cardSelecionado();
    return _autocomplete();
  }

  // ── Card mostrado depois de escolher ────────────────────────────────
  Widget _cardSelecionado() {
    final v = _selecionado!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.primary, width: 1.6),
        borderRadius: BorderRadius.circular(10),
        color: AppTheme.primary.withValues(alpha: 0.06),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_car, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  v.placa,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [v.marca, v.modelo].whereType<String>().join(' ').trim().isEmpty
                      ? '—'
                      : [v.marca, v.modelo].whereType<String>().join(' '),
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _trocar,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Trocar'),
          ),
        ],
      ),
    );
  }

  // ── Campo de busca com dropdown ─────────────────────────────────────
  Widget _autocomplete() {
    return Autocomplete<Veiculo>(
      displayStringForOption: (v) => v.label,
      optionsBuilder: _debouncedFetch,
      onSelected: _selecionar,
      fieldViewBuilder: (context, textCtrl, focusNode, onSubmitted) {
        // Sincroniza o controller local (pra abrir dropdown mesmo sem digitar).
        _searchCtrl.value = textCtrl.value;
        return TextField(
          controller: textCtrl,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Veículo',
            hintText: 'Digite placa, marca ou modelo…',
            prefixIcon: const Icon(Icons.directions_car),
            suffixIcon: textCtrl.text.isEmpty
                ? IconButton(
                    tooltip: 'Ver veículos disponíveis',
                    icon: const Icon(Icons.arrow_drop_down),
                    onPressed: () {
                      // Trick: entra e sai do foco pra abrir o dropdown vazio.
                      focusNode.requestFocus();
                      textCtrl.text = ' ';
                      textCtrl.text = '';
                    },
                  )
                : IconButton(
                    tooltip: 'Limpar',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      textCtrl.clear();
                    },
                  ),
          ),
          onSubmitted: (_) => onSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 400),
              child: list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Nenhum veículo encontrado.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 0),
                      itemBuilder: (_, i) {
                        final v = list[i];
                        return ListTile(
                          leading: const Icon(Icons.directions_car_outlined),
                          title: Text(
                            v.placa,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          subtitle: Text(
                            [v.marca, v.modelo]
                                .whereType<String>()
                                .join(' ')
                                .trim(),
                            style: const TextStyle(fontSize: 12),
                          ),
                          onTap: () => onSelected(v),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}
