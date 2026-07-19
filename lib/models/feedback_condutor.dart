/// Feedback do condutor sobre a viagem (Sprint M4).
///
/// Vem de `POST /transporte/api/bdt/feedback-condutor/obter`.
class FeedbackCondutor {
  final int id;
  final int fkBdt;
  final int nota; // 1-5
  final String? comentario;
  final int criadoPor;

  const FeedbackCondutor({
    required this.id,
    required this.fkBdt,
    required this.nota,
    this.comentario,
    required this.criadoPor,
  });

  factory FeedbackCondutor.fromJson(Map<String, dynamic> j) {
    int parseInt(dynamic v) => v is int ? v : int.tryParse(v.toString()) ?? 0;
    String? nn(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return FeedbackCondutor(
      id: parseInt(j['id']),
      fkBdt: parseInt(j['fk_bdt']),
      nota: parseInt(j['nota']),
      comentario: nn(j['comentario']),
      criadoPor: parseInt(j['criado_por']),
    );
  }
}
