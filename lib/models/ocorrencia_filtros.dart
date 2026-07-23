/// Opções pros filtros da tela de histórico de ocorrências —
/// resposta de `POST transporte/api/bdt/ocorrencias/filtros`.
///
/// Espelha `OcorrenciaService::veiculosFiltro/condutoresFiltro/tiposFiltro`
/// do web. Cada lista é `{id, nome}` (veiculos usa `placa` no lugar de nome).
class OcorrenciaFiltros {
  final List<OcorrenciaFiltroItem> veiculos;
  final List<OcorrenciaFiltroItem> condutores;
  final List<OcorrenciaFiltroItem> tipos;

  const OcorrenciaFiltros({
    this.veiculos = const [],
    this.condutores = const [],
    this.tipos = const [],
  });

  factory OcorrenciaFiltros.fromJson(Map<String, dynamic> j) {
    List<OcorrenciaFiltroItem> parseList(dynamic raw, String labelKey) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => OcorrenciaFiltroItem.fromJson(
                Map<String, dynamic>.from(e),
                labelKey,
              ))
          .toList();
    }

    return OcorrenciaFiltros(
      veiculos: parseList(j['veiculos'], 'placa'),
      condutores: parseList(j['condutores'], 'nome'),
      tipos: parseList(j['tipos'], 'nome'),
    );
  }
}

/// Item genérico `{id, label}` — a chave do label varia (placa/nome).
class OcorrenciaFiltroItem {
  final int id;
  final String label;

  const OcorrenciaFiltroItem({required this.id, required this.label});

  factory OcorrenciaFiltroItem.fromJson(
    Map<String, dynamic> j,
    String labelKey,
  ) {
    final rawId = j['id'];
    final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '') ?? 0;
    return OcorrenciaFiltroItem(
      id: id,
      label: (j[labelKey] ?? '').toString().trim(),
    );
  }
}
