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

/// Serviço de captura contínua de GPS rodando em **foreground service Android**.
///
/// Diferente do antigo [GpsLiveService] (que era um `Timer.periodic` dentro do
/// próprio app), aqui o tracking continua mesmo com:
///   - tela bloqueada;
///   - app em background (outro app aberto);
///   - app recolhido na tela inicial.
///
/// Para isso o Android exige um foreground service com notificação persistente.
class BackgroundLocationService {
  static const String _notifChannelId = 'bdt_uerj_gps_channel';
  static const String _notifChannelName = 'BDT UERJ — GPS';
  static const int _notifId = 9011;

  // Chaves de SharedPreferences usadas para passar contexto pro isolate do
  // service (não há acesso direto à memória do app aqui).
  static const String _prefBdtId = 'bg_gps_bdt_id';
  static const String _prefAgendaId = 'bg_gps_agenda_id';
  static const String _prefTrechoId = 'bg_gps_trecho_id';
  static const String _prefIntervalSec = 'bg_gps_interval_sec';
  static const String _prefRunning = 'bg_gps_running';

  static final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();

  /// Chamar **uma vez** no `main()` (depois do
  /// `WidgetsFlutterBinding.ensureInitialized()` e do SslBootstrap).
  static Future<void> init() async {
    // 1. Configura canal de notificação Android.
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
        importance: Importance.low, // não vibra, não toca
        showBadge: false,
      ),
    );

    // 2. Configura o foreground service.
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onServiceStart,
        autoStart: false, // só inicia quando a UI mandar
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

  /// Inicia o foreground service para o trecho informado.
  /// Idempotente: se já estiver rodando, apenas atualiza o contexto.
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
      // já rodando: atualiza contexto
      service.invoke('update_context', {
        'bdt_id': bdtId,
        'agenda_id': agendaId,
        'trecho_id': trechoId,
        'interval_sec': interval.inSeconds,
      });
    }
    return true;
  }

  /// Para o serviço e dispensa a notificação.
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

  // ==========================================================================
  // ENTRYPOINTS DO SERVICE (isolate separado — sem acesso ao state do app)
  // ==========================================================================

  /// Entry-point obrigatório (top-level/static) executado no isolate do
  /// foreground service.
  @pragma('vm:entry-point')
  static void _onServiceStart(ServiceInstance service) async {
    // Necessário para usar plugins (HTTP/SharedPreferences) no isolate.
    DartPluginRegistrant.ensureInitialized();

    // ⚠️ Cada isolate Dart tem seu próprio SecurityContext.defaultContext.
    // O isolate principal chama SslBootstrap.install() no main(), mas esse
    // efeito NÃO se propaga para o isolate do foreground service. Sem este
    // bootstrap aqui, qualquer POST para https://www.e-prefeitura.uerj.br
    // falha silenciosamente com HandshakeException (a CA da RNP que assina
    // o certificado da UERJ não está no truststore Android padrão).
    try {
      await SslBootstrap.install();
      _log('SSL bootstrap OK no isolate de service');
    } catch (e) {
      _log('SSL bootstrap FALHOU: $e');
    }

    StreamSubscription<Position>? posSub;
    Timer? heartbeatTimer;

    // contexto inicial vindo do SharedPreferences
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

    // Atualiza a notificação persistente.
    void setNotif(String content) {
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'BDT UERJ — Coletando GPS',
          content: content,
        );
      }
    }

    setNotif('Trecho #$trechoId ativo');

    // Escuta comandos vindos da UI (atualizar contexto / parar).
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
        trechoId = event['trecho_id'] as int;
        await p.setInt(_prefTrechoId, trechoId);
      }
      if (event['interval_sec'] is int) {
        intervalSec = event['interval_sec'] as int;
        await p.setInt(_prefIntervalSec, intervalSec);
      }
      setNotif('Trecho #$trechoId ativo');
    });

    service.on('stop').listen((_) async {
      await posSub?.cancel();
      heartbeatTimer?.cancel();
      await service.stopSelf();
    });

    // Stream do geolocator: GPS de alta acurácia, mas filtrando por distância
    // mínima também — assim economizamos bateria quando o veículo está parado.
    _log('iniciando stream GPS (intervalo=${intervalSec}s, distancia=5m)');
    posSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5, // metros
        intervalDuration: Duration(seconds: intervalSec),
        foregroundNotificationConfig: null,
      ),
    ).listen(
      (pos) async {
        if (bdtId <= 0 || trechoId <= 0) {
          _log('ponto descartado (bdtId=$bdtId trechoId=$trechoId)');
          return;
        }
        await _enviarPonto(
          bdtId: bdtId,
          agendaId: agendaId,
          trechoId: trechoId,
          pos: pos,
        );
      },
      onError: (e, st) => _log('Geolocator stream ERROR: $e'),
    );

    // Heartbeat: garante envio mesmo se o stream não disparar (carro parado).
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
          await _enviarPonto(
            bdtId: bdtId,
            agendaId: agendaId,
            trechoId: trechoId,
            pos: pos,
          );
        } catch (_) {
          // sem fix; tudo bem
        }
      },
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> _iosOnBackground(ServiceInstance service) async {
    // iOS está fora do escopo deste projeto (sem implementação Apple),
    // mas mantemos o hook para evitar crash se um dia compilarmos pra iOS.
    return true;
  }

  /// Envia um ponto para `transporte/api/bdt/localizacao` do isolate do
  /// service. **Não pode usar [BdtService]** porque o ApiClient depende de
  /// `debugPrint` e de plugins que podem não estar 100% acessíveis em isolate
  /// separado — fazemos a chamada HTTP "à mão", com o mesmo contrato.
  static Future<void> _enviarPonto({
    required int bdtId,
    int? agendaId,
    required int trechoId,
    required Position pos,
  }) async {
    final uri = Uri.parse(
      '${ApiClient.baseUrl.replaceAll(RegExp(r'/+$'), '')}/transporte/api/bdt/localizacao',
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final usuarioId = prefs.getInt('usuario_id') ?? 0;

      if (token == null || token.isEmpty) {
        _log('SEM TOKEN no SharedPreferences — refaça o login.');
      }
      if (usuarioId <= 0) {
        _log('usuario_id inválido ($usuarioId) — refaça o login.');
      }

      final body = jsonEncode({
        'bdt_id': bdtId,
        'usuario_id': usuarioId,
        if (agendaId != null && agendaId > 0) 'agenda_id': agendaId,
        'trecho_id': trechoId,
        'loc': {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracy': pos.accuracy,
          'speed': pos.speed,
          'bearing': pos.heading,
          'altitude': pos.altitude,
          'captured_at': DateTime.now().toIso8601String(),
          'provider': 'gps',
          'origem_registro': 'app_mobile_bg',
        },
      });

      _log(
        'POST $uri lat=${pos.latitude.toStringAsFixed(6)} '
        'lng=${pos.longitude.toStringAsFixed(6)} acc=${pos.accuracy.toStringAsFixed(1)}m',
      );

      final res = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        _log('OK ${res.statusCode}');
      } else {
        _log('HTTP ${res.statusCode}: ${res.body}');
      }
    } catch (e, st) {
      _log('EXCEÇÃO ao enviar ponto: $e');
      _log('  stack: ${st.toString().split("\n").take(3).join(" | ")}');
    }
  }

  /// Log unificado para o isolate de service. Aparece no `adb logcat` com
  /// tag `flutter` e prefixo `[BG-GPS]`. Em release também sai (não usa
  /// `kDebugMode`), pois só assim é possível diagnosticar problemas no APK
  /// instalado.
  static void _log(String msg) {
    developer.log(msg, name: 'BG-GPS');
    // ignore: avoid_print
    print('[BG-GPS] $msg');
  }
}
