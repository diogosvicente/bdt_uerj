/// Veículo simplificado retornado pelo autocomplete
/// (`POST /transporte/api/bdt/veiculos/buscar`).
class Veiculo {
  final int id;
  final String placa;
  final String? modelo;
  final String? marca;

  /// Rótulo pronto pra exibição, no formato "PLACA — Marca Modelo".
  /// Vem calculado do backend pra a UI não precisar concatenar.
  final String label;

  const Veiculo({
    required this.id,
    required this.placa,
    this.modelo,
    this.marca,
    required this.label,
  });

  factory Veiculo.fromJson(Map<String, dynamic> j) {
    int parseInt(dynamic v) => v is int ? v : int.tryParse(v.toString()) ?? 0;
    String? nn(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return Veiculo(
      id: parseInt(j['id']),
      placa: (j['placa'] ?? '').toString(),
      modelo: nn(j['modelo']),
      marca: nn(j['marca']),
      label: (j['label'] ?? j['placa'] ?? '').toString(),
    );
  }

  @override
  String toString() => label;
}
