import '../api/api_client.dart';

class BdtService {
  /// Abre (ou obtém) o BDT do dia para o condutor/veículo.
  /// Por enquanto está fixo, depois você pode passar IDs reais.
  static Future<int?> abrirBDT({
    int condutorId = 1,
    int veiculoId = 1,
  }) async {
    // TODO: ajustar endpoint conforme sua API
    final res = await ApiClient.post("bdt/abrir", {
      "condutor_id": condutorId,
      "veiculo_id": veiculoId,
    });

    if (res == null) return null;
    return res["bdt_id"] as int?;
  }
}
