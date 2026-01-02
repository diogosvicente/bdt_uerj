import 'dart:async';
import 'location_service.dart';
import 'bdt_service.dart';

class GpsLiveService {
  static Timer? _timer;

  static void start({
    required int bdtId,
    required int agendaId,
    required int trechoId,
    Duration interval = const Duration(seconds: 5),
  }) {
    stop();

    _timer = Timer.periodic(interval, (_) async {
      final loc = await LocationService.getLocPayload();
      if (loc == null) return;

      await BdtService.enviarLocalizacao(
        bdtId: bdtId,
        agendaId: agendaId,
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
