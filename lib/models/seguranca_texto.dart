/// Bloco de texto institucional de segurança exibido no modal do BDT
/// (Sprint W1 web / Sprint M6 mobile).
///
/// Fonte: endpoint `POST /transporte/api/bdt/seguranca/textos`, que
/// por sua vez é wrapper de `SegurancaTextoService::getAtivosParaModal()`
/// do web — a MESMA fonte que o modal web do BDT usa. Editável pelo
/// admin em `/transporte/admin/seguranca/textos` — sem redeploy.
class SegurancaTexto {
  final int id;
  final String titulo;
  /// Conteúdo pode ter quebras de linha (`\n`). O widget renderiza
  /// preservando quebras via `Text` — não usa Markdown/HTML.
  final String conteudo;
  final int ordem;

  const SegurancaTexto({
    required this.id,
    required this.titulo,
    required this.conteudo,
    this.ordem = 0,
  });

  factory SegurancaTexto.fromJson(Map<String, dynamic> j) {
    int parseInt(dynamic v) => v is int ? v : int.tryParse(v.toString()) ?? 0;
    return SegurancaTexto(
      id: parseInt(j['id']),
      titulo: (j['titulo'] ?? '').toString(),
      conteudo: (j['conteudo'] ?? '').toString(),
      ordem: parseInt(j['ordem']),
    );
  }
}
