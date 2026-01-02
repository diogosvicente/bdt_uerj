// lib/models/bdt_resumo.dart
class BdtResumo {
  final int id;
  final int ano;
  final int numero;
  final String dataReferencia;
  final int veiculoId;
  final String placa;
  final String? modeloNome;
  final String? marcaNome;

  BdtResumo({
    required this.id,
    required this.ano,
    required this.numero,
    required this.dataReferencia,
    required this.veiculoId,
    required this.placa,
    this.modeloNome,
    this.marcaNome,
  });

  factory BdtResumo.fromJson(Map<String, dynamic> j) {
    int parseInt(dynamic v) => v is int ? v : int.tryParse(v.toString()) ?? 0;

    return BdtResumo(
      id: parseInt(j['id']),
      ano: parseInt(j['ano']),
      numero: parseInt(j['numero']),
      dataReferencia: j['data_referencia']?.toString() ?? '',
      veiculoId: parseInt(j['fk_veiculo']),
      placa: j['placa']?.toString() ?? '',
      modeloNome: j['modelo_nome']?.toString(),
      marcaNome: j['marca_nome']?.toString(),
    );
  }

  String get titulo => "BDT $ano/$numero";
  String get subtitulo => "$placa ${marcaNome ?? ''} ${modeloNome ?? ''}".trim();
}
