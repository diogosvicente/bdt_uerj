import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

class LocationService {
  /// Pede permissão de localização "em uso" (foreground).
  /// Retorna true se o app pode capturar GPS no mínimo enquanto está aberto.
  static Future<bool> ensureForegroundPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return false;
    }
    return true; // whileInUse OU always
  }

  /// Pede permissão **always** (background location, Android 10+).
  /// No Android isso só pode ser solicitado *depois* de já ter `whileInUse`
  /// e abre uma tela separada do sistema.
  ///
  /// Retorna true se o tracking em background está liberado.
  static Future<bool> ensureBackgroundPermission() async {
    final okFg = await ensureForegroundPermission();
    if (!okFg) return false;

    // Em Android 10+ (API 29+) precisamos pedir explicitamente "Permitir o
    // tempo todo". Em versões anteriores, `whileInUse` já cobre background.
    final status = await ph.Permission.locationAlways.status;
    if (status.isGranted) return true;

    final result = await ph.Permission.locationAlways.request();
    if (result.isGranted) return true;

    if (kDebugMode) {
      // ignore: avoid_print
      print('[LocationService] permissão "Permitir o tempo todo" negada: $result');
    }
    return false;
  }

  /// M2: pede ao usuário que retire o app da otimização de bateria
  /// (Doze / App Standby). Sem isso, o foreground service pode ser
  /// morto pelo Android após ~30 min de tela bloqueada, especialmente em
  /// fabricantes agressivos (Xiaomi, Huawei, Samsung One UI).
  ///
  /// Abre a tela do sistema **apenas se a permissão ainda não foi dada**.
  /// Retorna true se a isenção está ativa (ou se a Android é antiga
  /// demais para ter Doze — raro hoje).
  static Future<bool> ensureBatteryOptimizationDisabled() async {
    final status = await ph.Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted) return true;

    final result = await ph.Permission.ignoreBatteryOptimizations.request();
    if (result.isGranted) return true;

    if (kDebugMode) {
      // ignore: avoid_print
      print('[LocationService] usuário negou isenção de bateria: $result');
    }
    return false;
  }

  static Future<Position?> getCurrentPosition() async {
    final ok = await ensureForegroundPermission();
    if (!ok) return null;

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getLocPayload() async {
    final pos = await getCurrentPosition();
    if (pos == null) return null;

    return {
      "lat": pos.latitude,
      "lng": pos.longitude,
      "accuracy": pos.accuracy, // metros
      "speed": pos.speed, // m/s
      "bearing": pos.heading, // graus
      "altitude": pos.altitude,
      "captured_at": DateTime.now().toIso8601String(),
      "provider": "gps",
    };
  }
}
