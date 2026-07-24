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

  /// Sprint M5 — DateTime da menor hora prevista de saída entre os trechos
  /// das solicitações vinculadas ao BDT. Null quando o BDT ainda não tem
  /// trecho com hora, ou quando a string veio malformada. Usado pelos
  /// alertas locais (1h e 30min antes).
  final DateTime? horaSaidaPrevista;

  BdtResumo({
    required this.id,
    required this.ano,
    required this.numero,
    required this.dataReferencia,
    required this.veiculoId,
    required this.placa,
    this.modeloNome,
    this.marcaNome,
    this.horaSaidaPrevista,
  });

  factory BdtResumo.fromJson(Map<String, dynamic> j) {
    int parseInt(dynamic v) => v is int ? v : int.tryParse(v.toString()) ?? 0;

    DateTime? parseDt(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      // Sprint MSEC.TZ — Backend manda "YYYY-MM-DD HH:MM:SS" em UTC (formato
      // nu do MariaDB). Sem "Z", DateTime.parse assumiria LOCAL do device
      // (drift de 3h no BRT). Adiciona "Z" antes do parse e converte pra
      // local para uso pelas widgets.
      try {
        final raw = s.replaceFirst(' ', 'T');
        final hasTz = raw.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);
        final norm = hasTz ? raw : '${raw}Z';
        return DateTime.parse(norm).toLocal();
      } catch (_) {
        return null;
      }
    }

    return BdtResumo(
      id: parseInt(j['id']),
      ano: parseInt(j['ano']),
      numero: parseInt(j['numero']),
      dataReferencia: j['data_referencia']?.toString() ?? '',
      veiculoId: parseInt(j['fk_veiculo']),
      placa: j['placa']?.toString() ?? '',
      modeloNome: j['modelo_nome']?.toString(),
      marcaNome: j['marca_nome']?.toString(),
      horaSaidaPrevista: parseDt(j['hora_saida_prevista']),
    );
  }

  String get titulo => "BDT $ano/$numero";
  String get subtitulo => "$placa ${marcaNome ?? ''} ${modeloNome ?? ''}".trim();
}
