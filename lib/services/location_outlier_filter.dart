import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

/// Filtragem de pontos GPS "ruins" antes de gravar/enviar.
///
/// Três verificações rápidas, todas configuráveis:
///
/// - **Precisão baixa**: `accuracy > maxAccuracyMeters` (padrão 50m).
///   O receptor GPS estava confuso — o ponto pode estar centenas de
///   metros do lugar real. Descarta.
/// - **Velocidade impossível**: `speed_kmh > maxSpeedKmh` (padrão 200).
///   Em veículo urbano ninguém vai a mais que isso; qualquer valor maior
///   é ruído do receptor. Descarta.
/// - **Teleporte**: distância pro ponto anterior é grande demais para
///   o intervalo de tempo. Ex.: pulou 500m em 5s = 360 km/h. Descarta.
///   A checagem só roda se houver um ponto anterior aceito (`lastAccepted`).
///
/// O filtro é **stateful de propósito**: guarda o último ponto aceito
/// para calcular teleporte. Chame [reset] ao iniciar um novo trecho para
/// não comparar com posições de um trecho antigo.
class LocationOutlierFilter {
  final double maxAccuracyMeters;
  final double maxSpeedKmh;
  final double maxTeleportMeters;
  final Duration teleportWindow;

  Position? _lastAccepted;

  LocationOutlierFilter({
    this.maxAccuracyMeters = 50,
    this.maxSpeedKmh = 200,
    this.maxTeleportMeters = 500,
    this.teleportWindow = const Duration(seconds: 5),
  });

  /// Retorna null se o ponto passou nos três testes (é para enviar),
  /// ou a razão de descarte (string curta) para logging.
  String? reject(Position pos) {
    // 1. Precisão
    if (pos.accuracy > maxAccuracyMeters) {
      return 'accuracy=${pos.accuracy.toStringAsFixed(1)}m>$maxAccuracyMeters';
    }

    // 2. Velocidade (Geolocator dá em m/s; converte)
    final speedKmh = pos.speed * 3.6;
    if (speedKmh > maxSpeedKmh) {
      return 'speed=${speedKmh.toStringAsFixed(1)}kmh>$maxSpeedKmh';
    }

    // 3. Teleporte (só se houver âncora)
    final last = _lastAccepted;
    if (last != null) {
      final dt = pos.timestamp.difference(last.timestamp);
      if (dt <= teleportWindow && !dt.isNegative) {
        final d = _haversineMeters(
          last.latitude, last.longitude,
          pos.latitude, pos.longitude,
        );
        if (d > maxTeleportMeters) {
          return 'teleport=${d.toStringAsFixed(0)}m em ${dt.inSeconds}s';
        }
      }
    }

    _lastAccepted = pos;
    return null;
  }

  /// Zera o histórico. Chamar ao iniciar novo trecho.
  void reset() {
    _lastAccepted = null;
  }

  /// Distância em metros entre dois pontos (fórmula de Haversine —
  /// suficiente para as ~centenas de metros em jogo aqui, não precisa
  /// Vincenty).
  static double _haversineMeters(
    double lat1, double lon1, double lat2, double lon2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _deg2rad(double deg) => deg * math.pi / 180;
}
