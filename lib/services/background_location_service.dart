import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/ssl_bootstrap.dart';
import 'location_outlier_filter.dart';
import 'location_queue_db.dart';

/// Serviço de captura contínua de GPS em foreground service Android.
///
/// **Arquitetura M2:**
///
/// ```
///  Geolocator ──► Filtro Outliers ──► Fila SQLite ──► Worker HTTP
///  (coleta)      (accuracy/speed/     (persistente,   (batch,
///                 teleporte)           sobrevive       retry)
///                                      offline)
/// ```
///
/// **Por que fila?** Sem rede (túnel, área rural) o ponto é armazenado
/// localmente e reenviado quando reconectar. Sem isso, esses pontos seriam
/// perdidos silenciosamente (o request HTTP falha e nada mais).
///
/// **Por que filtro?** GPS é ruidoso — receptores frequentemente reportam
/// pontos com accuracy alta (>50m) ou velocidade impossível (>200 km/h);
/// esses pontos falseiam o traçado do trecho.
///
/// Continua funcionando com:
///   - tela bloqueada;
///   - app em background;
///   - app recolhido na home;
///   - **sem conexão de dados** (novo em M2).
class BackgroundLocationService {
  static const String _notifChannelId = 'bdt_uerj_gps_channel';
  static const String _notifChannelName = 'BDT UERJ — GPS';
  static const int _notifId = 9011;

  // Chaves de SharedPreferences para passar contexto pro isolate do service.
  static const String _prefBdtId = 'bg_gps_bdt_id';
  static const String _prefAgendaId = 'bg_gps_agenda_id';
  static const String _prefTrechoId = 'bg_gps_trecho_id';
  static const String _prefIntervalSec = 'bg_gps_interval_sec';
  static const String _prefRunning = 'bg_gps_running';

  /// A cada quantos segundos o worker consome a fila.
  static const _workerIntervalSec = 30;

  /// Tamanho do batch por rodada de envio.
  static const _workerBatchSize = 20;

  static final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();

  /// Chamar uma vez no `main()`.
  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notif.initialize(
      const InitializationSettings(android: androidInit),
    );

    final androidImpl = _notif
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _notifChannelId,
        _notifChannelName,
        description: 'Mantém o GPS ativo durante o trecho do BDT.',
        importance: Importance.low,
        showBadge: false,
      ),
    );

    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onServiceStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _notifChannelId,
        initialNotificationTitle: 'BDT UERJ',
        initialNotificationContent: 'Aguardando início do trecho',
        foregroundServiceNotificationId: _notifId,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onServiceStart,
        onBackground: _iosOnBackground,
      ),
    );
  }

  static Future<bool> start({
    required int bdtId,
    int? agendaId,
    required int trechoId,
    Duration interval = const Duration(seconds: 5),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefBdtId, bdtId);
    if (agendaId != null && agendaId > 0) {
      await prefs.setInt(_prefAgendaId, agendaId);
    } else {
      await prefs.remove(_prefAgendaId);
    }
    await prefs.setInt(_prefTrechoId, trechoId);
    await prefs.setInt(_prefIntervalSec, interval.inSeconds);
    await prefs.setBool(_prefRunning, true);

    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!running) {
      final started = await service.startService();
      if (!started) return false;
    } else {
      service.invoke('update_context', {
        'bdt_id': bdtId,
        'agenda_id': agendaId,
        'trecho_id': trechoId,
        'interval_sec': interval.inSeconds,
      });
    }
    return true;
  }

  static Future<void> stop() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefRunning, false);
    await prefs.remove(_prefBdtId);
    await prefs.remove(_prefAgendaId);
    await prefs.remove(_prefTrechoId);

    final service = FlutterBackgroundService();
    service.invoke('stop');
  }

  static Future<bool> isRunning() async {
    return FlutterBackgroundService().isRunning();
  }

  /// Consultado pela UI para mostrar quantos pontos ainda estão em fila.
  static Future<int> countPendingFor({required int bdtId, int? trechoId}) async {
    final q = LocationQueueDb();
    try {
      return await q.countPendingFor(bdtId: bdtId, trechoId: trechoId);
    } finally {
      await q.close();
    }
  }

  // ==========================================================================
  // ENTRYPOINTS DO SERVICE (isolate separado)
  // ==========================================================================

  @pragma('vm:entry-point')
  static void _onServiceStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    // Cada isolate tem seu próprio SecurityContext.defaultContext.
    try {
      await SslBootstrap.install();
      _log('SSL bootstrap OK no isolate de service');
    } catch (e) {
      _log('SSL bootstrap FALHOU: $e');
    }

    final queue = LocationQueueDb();
    final filter = LocationOutlierFilter();

    StreamSubscription<Position>? posSub;
    Timer? heartbeatTimer;
    Timer? syncTimer;

    int bdtId = 0;
    int? agendaId;
    int trechoId = 0;
    int intervalSec = 5;

    Future<void> refreshContextFromPrefs() async {
      final prefs = await SharedPreferences.getInstance();
      bdtId = prefs.getInt(_prefBdtId) ?? 0;
      agendaId = prefs.getInt(_prefAgendaId);
      trechoId = prefs.getInt(_prefTrechoId) ?? 0;
      intervalSec = prefs.getInt(_prefIntervalSec) ?? 5;
    }

    await refreshContextFromPrefs();

    Future<void> updateNotifWithQueue() async {
      if (service is! AndroidServiceInstance) return;
      final pending = await queue.countPending();
      final content = pending == 0
          ? 'Trecho ativo — pontos enviados em tempo real'
          : 'Trecho ativo — $pending ponto${pending == 1 ? "" : "s"} na fila';
      service.setForegroundNotificationInfo(
        title: 'BDT UERJ — Coletando GPS',
        content: content,
      );
    }

    await updateNotifWithQueue();

    service.on('update_context').listen((event) async {
      if (event == null) return;
      final p = await SharedPreferences.getInstance();
      if (event['bdt_id'] is int) {
        bdtId = event['bdt_id'] as int;
        await p.setInt(_prefBdtId, bdtId);
      }
      final ag = event['agenda_id'];
      if (ag is int && ag > 0) {
        agendaId = ag;
        await p.setInt(_prefAgendaId, ag);
      } else {
        agendaId = null;
        await p.remove(_prefAgendaId);
      }
      if (event['trecho_id'] is int) {
        final novoTrecho = event['trecho_id'] as int;
        if (novoTrecho != trechoId) {
          // trecho mudou — âncora do filtro de teleporte precisa resetar
          filter.reset();
        }
        trechoId = novoTrecho;
        await p.setInt(_prefTrechoId, trechoId);
      }
      if (event['interval_sec'] is int) {
        intervalSec = event['interval_sec'] as int;
        await p.setInt(_prefIntervalSec, intervalSec);
      }
      await updateNotifWithQueue();
    });

    service.on('stop').listen((_) async {
      await posSub?.cancel();
      heartbeatTimer?.cancel();
      syncTimer?.cancel();
      await queue.close();
      await service.stopSelf();
    });

    // Enfileira um ponto (aplica filtro primeiro).
    Future<void> capturarPonto(Position pos) async {
      if (bdtId <= 0 || trechoId <= 0) return;

      final rejeicao = filter.reject(pos);
      if (rejeicao != null) {
        _log('descartado por outlier: $rejeicao');
        return;
      }

      final payload = _buildPayload(
        bdtId: bdtId,
        agendaId: agendaId,
        trechoId: trechoId,
        pos: pos,
      );

      await queue.enqueue(
        bdtId: bdtId,
        agendaId: agendaId,
        trechoId: trechoId,
        payload: payload,
      );

      _log(
        'enfileirado lat=${pos.latitude.toStringAsFixed(6)} '
        'lng=${pos.longitude.toStringAsFixed(6)} '
        'acc=${pos.accuracy.toStringAsFixed(1)}m',
      );
      await updateNotifWithQueue();
    }

    _log('iniciando stream GPS (intervalo=${intervalSec}s, distancia=5m)');
    posSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
        intervalDuration: Duration(seconds: intervalSec),
        foregroundNotificationConfig: null,
      ),
    ).listen(
      capturarPonto,
      onError: (e, st) => _log('Geolocator stream ERROR: $e'),
    );

    // Heartbeat: garante ponto mesmo se o stream não disparar (carro parado).
    heartbeatTimer = Timer.periodic(
      Duration(seconds: intervalSec * 2),
      (_) async {
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
              timeLimit: Duration(seconds: 8),
            ),
          );
          await capturarPonto(pos);
        } catch (_) {
          // sem fix; tudo bem
        }
      },
    );

    // Worker de reenvio — consome a fila em batch a cada N segundos.
    syncTimer = Timer.periodic(
      const Duration(seconds: _workerIntervalSec),
      (_) => _drainQueue(queue, updateNotifWithQueue),
    );

    // Chuta a fila logo, sem esperar 30s (útil quando o app reabre após
    // ficar sem rede e há backlog acumulado).
    _drainQueue(queue, updateNotifWithQueue);
  }

  @pragma('vm:entry-point')
  static Future<bool> _iosOnBackground(ServiceInstance service) async {
    return true;
  }

  /// Constrói o payload no mesmo formato aceito por `bdt/localizacao`.
  static Map<String, dynamic> _buildPayload({
    required int bdtId,
    int? agendaId,
    required int trechoId,
    required Position pos,
  }) {
    return {
      'bdt_id': bdtId,
      if (agendaId != null && agendaId > 0) 'agenda_id': agendaId,
      'trecho_id': trechoId,
      'loc': {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': pos.accuracy,
        'speed': pos.speed,
        'bearing': pos.heading,
        'altitude': pos.altitude,
        'captured_at': (pos.timestamp).toIso8601String(),
        'provider': 'gps',
        'origem_registro': 'app_mobile_bg',
      },
    };
  }

  /// Consome a fila: pega um batch, tenta enviar cada um. Sucesso apaga,
  /// falha incrementa tentativas.
  static Future<void> _drainQueue(
    LocationQueueDb queue,
    Future<void> Function() onProgress,
  ) async {
    List<PendingPoint> lote;
    try {
      lote = await queue.takePending(limit: _workerBatchSize);
    } catch (e) {
      _log('takePending FALHOU: $e');
      return;
    }
    if (lote.isEmpty) return;

    _log('drenando fila: ${lote.length} ponto(s) para enviar');

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final usuarioId = prefs.getInt('usuario_id') ?? 0;

    if (token == null || token.isEmpty || usuarioId <= 0) {
      _log('sem credenciais (token=${token != null} uid=$usuarioId) — mantendo fila');
      return;
    }

    final uri = Uri.parse(
      '${ApiClient.baseUrl.replaceAll(RegExp(r'/+$'), '')}/transporte/api/bdt/localizacao',
    );

    for (final p in lote) {
      final body = jsonEncode({
        ...p.payload,
        'usuario_id': usuarioId,
      });

      try {
        final res = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: body,
            )
            .timeout(const Duration(seconds: 10));

        if (res.statusCode >= 200 && res.statusCode < 300) {
          await queue.markSent(p.id);
        } else {
          _log('HTTP ${res.statusCode} (tent ${p.attempts + 1}) body=${_truncar(res.body, 120)}');
          await queue.markFailed(p.id, error: 'HTTP ${res.statusCode}');
        }
      } catch (e) {
        _log('EXCEÇÃO no envio (tent ${p.attempts + 1}): $e');
        await queue.markFailed(p.id, error: e.toString());
      }
    }

    await onProgress();
  }

  static String _truncar(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  static void _log(String msg) {
    developer.log(msg, name: 'BG-GPS');
    // ignore: avoid_print
    print('[BG-GPS] $msg');
  }
}
