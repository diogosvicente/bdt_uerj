/// Sprint 15 W+M (2026-07-26) — Condutor "leve" retornado por
/// `POST /transporte/api/bdt/condutores-ativos`.
///
/// Só os campos que o dropdown "Outro condutor" da `CriarBdtPage`
/// precisa — id + nome + flag `souEu` (verdadeiro no condutor
/// associado ao próprio usuário logado, se houver).
class CondutorLite {
  final int id;
  final String nome;
  final bool souEu;

  const CondutorLite({
    required this.id,
    required this.nome,
    required this.souEu,
  });

  factory CondutorLite.fromJson(Map<String, dynamic> j) {
    int parseInt(dynamic v) => v is int ? v : int.tryParse(v.toString()) ?? 0;

    return CondutorLite(
      id: parseInt(j['id']),
      nome: (j['nome'] ?? '').toString(),
      souEu: j['sou_eu'] == true,
    );
  }

  @override
  String toString() => nome;
}
