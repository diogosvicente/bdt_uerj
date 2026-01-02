import 'package:geolocator/geolocator.dart';

class LocationService {
  static Future<Position?> getCurrentPosition() async {
    try {
      // 1) GPS ligado?
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      // 2) permissão
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }

      // 3) pega 1 leitura (boa para “iniciar trecho”)
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 8),
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
      "speed": pos.speed,       // m/s
      "bearing": pos.heading,   // graus
      "altitude": pos.altitude,
      "captured_at": DateTime.now().toIso8601String(),
      "provider": "gps",
    };
  }
}
