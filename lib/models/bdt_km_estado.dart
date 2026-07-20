/// Estado da KM de um BDT — resposta do endpoint
/// `POST /transporte/api/bdt/km/estado`.
///
/// Usado pelo app antes de iniciar um trecho pra decidir se precisa
/// perguntar a KM inicial ao condutor: se [kmInicial] é null (ainda
/// não foi digitada nem na web nem no mobile), abre o diálogo.
class BdtKmEstado {
  final int bdtId;
  final double? kmInicial;
  final double? kmFinal;
  final int idStatusAtual;

  const BdtKmEstado({
    required this.bdtId,
    this.kmInicial,
    this.kmFinal,
    required this.idStatusAtual,
  });

  factory BdtKmEstado.fromJson(Map<String, dynamic> j) {
    int parseInt(dynamic v) => v is int ? v : int.tryParse(v.toString()) ?? 0;
    double? parseKm(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble() > 0 ? v.toDouble() : null;
      final s = v.toString().trim().replaceAll(',', '.');
      if (s.isEmpty) return null;
      final d = double.tryParse(s);
      return (d != null && d > 0) ? d : null;
    }

    return BdtKmEstado(
      bdtId: parseInt(j['bdt_id']),
      kmInicial: parseKm(j['km_inicial']),
      kmFinal: parseKm(j['km_final']),
      idStatusAtual: parseInt(j['id_status_atual']),
    );
  }

  /// True quando o app DEVE perguntar a KM inicial ao condutor antes
  /// de iniciar o primeiro trecho. `false` se já foi digitada em algum
  /// lugar — nesse caso o app pula o diálogo.
  bool get precisaPerguntarKmInicial => kmInicial == null;
}
