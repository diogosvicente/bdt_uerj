/// Sprint W+M (Sprint 15 web) — resposta do endpoint
/// `POST transporte/api/bdt/checkup`.
///
/// Espelha o retorno de `BdtSemSolicitacaoService::checkup()` do web —
/// só as chaves que a UI mobile realmente usa (avisos + placa + nome
/// do condutor). Novos campos que o backend adicionar podem ser lidos
/// direto do [raw] sem quebrar clientes antigos.
class CheckupBdt {
  final bool ok;
  final List<String> avisos;
  final String? placaVeiculo;
  final String? nomeCondutor;
  final Map<String, dynamic> raw;

  const CheckupBdt({
    required this.ok,
    required this.avisos,
    this.placaVeiculo,
    this.nomeCondutor,
    this.raw = const {},
  });

  factory CheckupBdt.fromJson(Map<String, dynamic> json) {
    final avisosRaw = (json['avisos'] as List<dynamic>? ?? const []);
    final avisos = avisosRaw.map((e) => e.toString()).toList();

    String? readStr(dynamic obj, String key) {
      if (obj is Map) {
        final v = obj[key];
        if (v == null) return null;
        final s = v.toString().trim();
        return s.isEmpty ? null : s;
      }
      return null;
    }

    return CheckupBdt(
      ok: json['ok'] == true,
      avisos: avisos,
      placaVeiculo: readStr(json['veiculo'], 'placa'),
      nomeCondutor: readStr(json['condutor'], 'nome'),
      raw: json,
    );
  }
}
