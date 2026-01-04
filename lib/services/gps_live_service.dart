import 'dart:async';
import 'location_service.dart';
import 'bdt_service.dart';

class GpsLiveService {
  static Timer? _timer;

  static void start({
    required int bdtId,
    int? agendaId, // ✅ agora pode ser null (trecho extra)
    required int trechoId,
    Duration interval = const Duration(seconds: 5),
  }) {
    stop();

    _timer = Timer.periodic(interval, (_) async {
      final loc = await LocationService.getLocPayload();
      if (loc == null) return;

      await BdtService.enviarLocalizacao(
        bdtId: bdtId,
        agendaId: (agendaId != null && agendaId > 0) ? agendaId : null,
        trechoId: trechoId,
        loc: loc,
      );
    });
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
