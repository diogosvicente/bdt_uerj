/// Ocorrência do BDT — resposta dos endpoints
/// `POST transporte/api/bdt/ocorrencias/historico` (linha da lista)
/// e `POST transporte/api/bdt/ocorrencias/detalhes` (mesma shape com
/// `modeloNome` a mais no detalhe).
///
/// Sprint W+M (Sprint 17 web / W15 F3) — histórico institucional
/// [[bdt_uerj_reusar_codigo_web]]: espelha o retorno do
/// `OcorrenciaRepository::getHistorico/findOne` do web.
class Ocorrencia {
  final int id;
  final String? dataHora; // "2026-07-22 14:30:00"
  final String titulo;
  final String? descricao;
  final int? fkOcorrenciaTipo;
  final String tipoNome;
  final int? fkBdt;
  final String? bdtAno;
  final String? bdtNumero;
  final int? fkVeiculo;
  final String? placa;
  final String? modeloNome; // só no /detalhes
  final int? fkCondutor;
  final String? condutorNome;

  const Ocorrencia({
    required this.id,
    this.dataHora,
    required this.titulo,
    this.descricao,
    this.fkOcorrenciaTipo,
    required this.tipoNome,
    this.fkBdt,
    this.bdtAno,
    this.bdtNumero,
    this.fkVeiculo,
    this.placa,
    this.modeloNome,
    this.fkCondutor,
    this.condutorNome,
  });

  factory Ocorrencia.fromJson(Map<String, dynamic> j) {
    int? parseIntN(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    String? nn(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return Ocorrencia(
      id: parseIntN(j['id']) ?? 0,
      dataHora: nn(j['data_hora']),
      titulo: (j['titulo'] ?? '').toString(),
      descricao: nn(j['descricao']),
      fkOcorrenciaTipo: parseIntN(j['fk_ocorrencia_tipo']),
      tipoNome: (j['tipo_nome'] ?? '').toString(),
      fkBdt: parseIntN(j['fk_bdt']),
      bdtAno: nn(j['bdt_ano']),
      bdtNumero: nn(j['bdt_numero']),
      fkVeiculo: parseIntN(j['fk_veiculo']),
      placa: nn(j['placa']),
      modeloNome: nn(j['modelo_nome']),
      fkCondutor: parseIntN(j['fk_condutor']),
      condutorNome: nn(j['condutor_nome']),
    );
  }

  /// "BDT 2026/17" ou null se falta ano/numero.
  String? get bdtLabel {
    if (bdtAno == null || bdtNumero == null) return null;
    return 'BDT $bdtAno/$bdtNumero';
  }
}
