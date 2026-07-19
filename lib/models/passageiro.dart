/// Passageiro previsto de um BDT (Sprint M4).
///
/// Vem do endpoint `POST /transporte/api/bdt/passageiros/listar`.
/// `presente` e `embarque_extra` são 0/1 no backend — aqui viram bool
/// pra ficar natural na UI (checkbox).
class Passageiro {
  final int id;
  final String nome;
  final String? matricula;
  final String? telefone;
  final String? cpf;
  final bool presente;
  final bool embarqueExtra;
  final String? motivoExtra;

  const Passageiro({
    required this.id,
    required this.nome,
    this.matricula,
    this.telefone,
    this.cpf,
    this.presente = false,
    this.embarqueExtra = false,
    this.motivoExtra,
  });

  factory Passageiro.fromJson(Map<String, dynamic> j) {
    int parseInt(dynamic v) => v is int ? v : int.tryParse(v.toString()) ?? 0;
    String? nn(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return Passageiro(
      id: parseInt(j['id']),
      nome: (j['nome'] ?? '').toString(),
      matricula: nn(j['matricula']),
      telefone: nn(j['telefone']),
      cpf: nn(j['cpf']),
      presente: parseInt(j['presente']) == 1,
      embarqueExtra: parseInt(j['embarque_extra']) == 1,
      motivoExtra: nn(j['motivo_extra']),
    );
  }

  /// Cópia com campos alterados (imutável).
  Passageiro copyWith({
    bool? presente,
    bool? embarqueExtra,
    String? motivoExtra,
  }) {
    return Passageiro(
      id: id,
      nome: nome,
      matricula: matricula,
      telefone: telefone,
      cpf: cpf,
      presente: presente ?? this.presente,
      embarqueExtra: embarqueExtra ?? this.embarqueExtra,
      motivoExtra: motivoExtra ?? this.motivoExtra,
    );
  }
}
