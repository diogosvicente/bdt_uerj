import 'dart:async';
import 'dart:developer' as developer;

import 'background_location_service.dart';
import 'bdt_service.dart';
import 'location_service.dart';

/// Tracking de GPS com **duplo motor**:
///
/// 1. **Timer no isolate principal** (igual à versão original deste app, que
///    comprovadamente funcionava): a cada N segundos pega a posição via
///    `LocationService.getLocPayload()` e chama `BdtService.enviarLocalizacao`.
///    Esse caminho garante envio enquanto o app está em foreground —
///    aproveita o `ApiClient` (com SSL bootstrap) e o token já em memória.
///
/// 2. **Foreground service Android** ([BackgroundLocationService]): rodado em
///    paralelo, é o que mantém o GPS coletando quando a tela é bloqueada ou
///    o usuário sai do app. Se ele falhar ao subir (versão do Android, plugin,
///    permissão), o tracking principal continua funcionando — não é
///    blocker.
class GpsLiveService {
  static Timer? _timer;
  static int? _bdtId;
  static int? _agendaId;
  static int? _trechoId;

  static void _log(String msg) {
    developer.log(msg, name: 'GPS-LIVE');
    // ignore: avoid_print
    print('[GPS-LIVE] $msg');
  }

  static Future<void> start({
    required int bdtId,
    int? agendaId,
    required int trechoId,
    Duration interval = const Duration(seconds: 5),
  }) async {
    // Garante estado limpo (cancela timer anterior, para service anterior).
    await stop();

    _bdtId = bdtId;
    _agendaId = (agendaId != null && agendaId > 0) ? agendaId : null;
    _trechoId = trechoId;

    _log('start bdt=$bdtId agenda=$_agendaId trecho=$trechoId interval=${interval.inSeconds}s');

    // 1) Timer no isolate principal — caminho confiável de envio.
    _timer = Timer.periodic(interval, (_) async {
      final loc = await LocationService.getLocPayload();
      if (loc == null) {
        _log('LocationService retornou null (sem fix ou sem permissão)');
        return;
      }

      try {
        final ok = await BdtService.enviarLocalizacao(
          bdtId: bdtId,
          agendaId: _agendaId,
          trechoId: trechoId,
          loc: loc,
        );
        _log(
          'envio foreground: ${ok ? "OK" : "FALHOU"} '
          'lat=${(loc["lat"] as num).toStringAsFixed(6)} '
          'lng=${(loc["lng"] as num).toStringAsFixed(6)}',
        );
      } catch (e) {
        _log('exceção no envio foreground: $e');
      }
    });

    // 2) Foreground service em paralelo — sobe a notificação persistente
    //    e mantém o GPS coletando mesmo com tela bloqueada / app em outra
    //    atividade. Se falhar, o tracking foreground continua funcionando.
    try {
      final started = await BackgroundLocationService.start(
        bdtId: bdtId,
        agendaId: agendaId,
        trechoId: trechoId,
        interval: interval,
      );
      _log('foreground service: ${started ? "iniciado" : "FALHOU iniciar"}');
    } catch (e) {
      _log('foreground service exceção: $e');
    }
  }

  static Future<void> stop() async {
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
      _log('timer foreground parado');
    }
    _bdtId = null;
    _agendaId = null;
    _trechoId = null;
    try {
      await BackgroundLocationService.stop();
    } catch (_) {
      // mesmo se falhar, segue
    }
  }

  static bool get isRunning => _timer != null;
}
