import 'package:flutter/material.dart';

import '../models/condutor_lite.dart';
import '../theme/app_theme.dart';

/// Sprint 15 W+M (2026-07-26) — Autocomplete de condutor, alimentado
/// por uma lista IN-MEMORY (a `CriarBdtPage` já carrega a lista inteira
/// via `bdt/condutores-ativos` no `initState`).
///
/// Diferente do `VeiculoAutocomplete` (que faz debounce + fetch por
/// tecla), este filtra localmente — a lista de condutores ativos é
/// pequena (dezenas), não faz sentido bater no backend por tecla.
///
/// Filtro: `contains` case-insensitive no nome, com fallback pra prefixo
/// normalizado (sem acento) — "diogo" acha "Diogo da Silva", "silv"
/// acha "Diogo da Silva Vicente do Nascimento", etc.
///
/// UX igual ao `VeiculoAutocomplete`:
///  - Card compacto depois de escolher, com botão "Trocar".
///  - Menu suspenso enquanto digita.
///  - Ícone dropdown na direita abre o menu sem exigir digitar nada.
class CondutorAutocomplete extends StatefulWidget {
  /// Lista completa (já filtrada pelos ativos no backend).
  final List<CondutorLite> condutores;

  /// Valor inicial — opcional, pra edição.
  final CondutorLite? initialValue;

  /// Callback quando escolhe (ou aperta "Trocar" → null).
  final ValueChanged<CondutorLite?> onChanged;

  const CondutorAutocomplete({
    super.key,
    required this.condutores,
    required this.onChanged,
    this.initialValue,
  });

  @override
  State<CondutorAutocomplete> createState() => _CondutorAutocompleteState();
}

class _CondutorAutocompleteState extends State<CondutorAutocomplete> {
  CondutorLite? _selecionado;

  @override
  void initState() {
    super.initState();
    _selecionado = widget.initialValue;
  }

  /// Normaliza pra busca: minúsculo + sem acento comum. Simples o
  /// bastante pra não puxar `diacritic` package só pra isto.
  static String _norm(String s) {
    const acentos = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const puros   = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
    final buf = StringBuffer();
    for (final ch in s.characters) {
      final idx = acentos.indexOf(ch);
      buf.write(idx >= 0 ? puros[idx] : ch);
    }
    return buf.toString().toLowerCase().trim();
  }

  Iterable<CondutorLite> _filtrar(String q) {
    final nq = _norm(q);
    if (nq.isEmpty) return widget.condutores;
    return widget.condutores.where((c) => _norm(c.nome).contains(nq));
  }

  void _selecionar(CondutorLite c) {
    setState(() => _selecionado = c);
    widget.onChanged(c);
  }

  void _trocar() {
    setState(() => _selecionado = null);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    if (_selecionado != null) return _cardSelecionado();
    return _autocomplete();
  }

  Widget _cardSelecionado() {
    final c = _selecionado!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.primary, width: 1.6),
        borderRadius: BorderRadius.circular(10),
        color: AppTheme.primary.withValues(alpha: 0.06),
      ),
      child: Row(
        children: [
          Icon(
            c.souEu ? Icons.person : Icons.person_outline,
            color: AppTheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  c.nome,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (c.souEu) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Você mesmo',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
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

  Widget _autocomplete() {
    return Autocomplete<CondutorLite>(
      displayStringForOption: (c) => c.nome,
      optionsBuilder: (tev) => _filtrar(tev.text),
      onSelected: _selecionar,
      fieldViewBuilder: (context, textCtrl, focusNode, onSubmitted) {
        return TextField(
          controller: textCtrl,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Condutor',
            hintText: 'Digite o nome…',
            prefixIcon: const Icon(Icons.person_search_outlined),
            border: const OutlineInputBorder(),
            suffixIcon: textCtrl.text.isEmpty
                ? IconButton(
                    tooltip: 'Ver condutores',
                    icon: const Icon(Icons.arrow_drop_down),
                    onPressed: () {
                      // Trick pra abrir o menu sem exigir digitar nada:
                      // força um rebuild de options com "" (mostra todos).
                      focusNode.requestFocus();
                      textCtrl.text = ' ';
                      textCtrl.text = '';
                    },
                  )
                : IconButton(
                    tooltip: 'Limpar',
                    icon: const Icon(Icons.close),
                    onPressed: textCtrl.clear,
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
                        'Nenhum condutor encontrado.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 0),
                      itemBuilder: (_, i) {
                        final c = list[i];
                        return ListTile(
                          leading: Icon(
                            c.souEu ? Icons.person : Icons.person_outline,
                            color: c.souEu ? AppTheme.primary : null,
                          ),
                          title: Text(
                            c.nome,
                            style: TextStyle(
                              fontWeight: c.souEu
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                          subtitle: c.souEu
                              ? Text(
                                  'Você mesmo',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.primary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                              : null,
                          onTap: () => onSelected(c),
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
