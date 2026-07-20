/// Pré-BDT aguardando aprovação do admin (Sprint M3).
///
/// Vem do endpoint `POST /transporte/api/bdt/pre-bdt/meus-pendentes` — só
/// os Pré-BDTs criados PELO usuário logado que ainda estão `pendente`.
///
/// Backend enriquece cada item com `protocolo` (TRN-BDT-YYYY-NNNNN)
/// e uma lista de `trechos_previstos` (origem/destino/etc.).
class PreBdtPendente {
  final int id;
  final int ano;
  final int numero;
  final String dataReferencia;
  final String? observacoesGerais;
  final String createdAt;
  final int fkVeiculo;
  final String? veiculoPlaca;
  final String? veiculoMarca;
  final String? veiculoModelo;
  final String protocolo;
  final List<TrechoPrevisto> trechos;

  const PreBdtPendente({
    required this.id,
    required this.ano,
    required this.numero,
    required this.dataReferencia,
    this.observacoesGerais,
    required this.createdAt,
    required this.fkVeiculo,
    this.veiculoPlaca,
    this.veiculoMarca,
    this.veiculoModelo,
    required this.protocolo,
    this.trechos = const [],
  });

  factory PreBdtPendente.fromJson(Map<String, dynamic> j) {
    int parseInt(dynamic v) => v is int ? v : int.tryParse(v.toString()) ?? 0;
    String? nn(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final rawTrechos = j['trechos_previstos'];
    final trechos = <TrechoPrevisto>[];
    if (rawTrechos is List) {
      for (final t in rawTrechos) {
        if (t is Map) {
          trechos.add(TrechoPrevisto.fromJson(Map<String, dynamic>.from(t)));
        }
      }
    }

    return PreBdtPendente(
      id: parseInt(j['id']),
      ano: parseInt(j['ano']),
      numero: parseInt(j['numero']),
      dataReferencia: (j['data_referencia'] ?? '').toString(),
      observacoesGerais: nn(j['observacoes_gerais']),
      createdAt: (j['created_at'] ?? '').toString(),
      fkVeiculo: parseInt(j['fk_veiculo']),
      veiculoPlaca: nn(j['veiculo_placa']),
      veiculoMarca: nn(j['veiculo_marca']),
      veiculoModelo: nn(j['veiculo_modelo']),
      protocolo: (j['protocolo'] ?? '').toString(),
      trechos: trechos,
    );
  }

  /// "BDT ano/numero" — mesmo padrão de BdtResumo.titulo.
  String get titulo => 'BDT $ano/$numero';

  /// "PLACA — Marca Modelo" ou só a placa se as outras faltarem.
  String get veiculoLabel {
    final meta = [veiculoMarca, veiculoModelo]
        .whereType<String>()
        .join(' ')
        .trim();
    final placa = veiculoPlaca ?? '—';
    return meta.isEmpty ? placa : '$placa — $meta';
  }
}

/// Trecho previsto (origem → destino + horários opcionais).
/// Backend usa nomes `saida` / `chegada` (datetime string ou null).
class TrechoPrevisto {
  final int id;
  final String origem;
  final String destino;
  final String? saida;
  final String? chegada;
  final int ordem;

  const TrechoPrevisto({
    required this.id,
    required this.origem,
    required this.destino,
    this.saida,
    this.chegada,
    required this.ordem,
  });

  factory TrechoPrevisto.fromJson(Map<String, dynamic> j) {
    int parseInt(dynamic v) => v is int ? v : int.tryParse(v.toString()) ?? 0;
    String? nn(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return TrechoPrevisto(
      id: parseInt(j['id']),
      origem: (j['origem'] ?? '').toString(),
      destino: (j['destino'] ?? '').toString(),
      saida: nn(j['saida']),
      chegada: nn(j['chegada']),
      ordem: parseInt(j['ordem']),
    );
  }
}
