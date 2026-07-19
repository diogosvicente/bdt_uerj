import 'dart:convert';
import 'dart:typed_data';

import '../api/api_client.dart';

/// Desafio de captcha vindo do backend.
///
/// - Se [enabled] for false, o backend está com o captcha desligado (via env)
///   e o app não deve exibir o campo nem enviar `captcha_token`/`captcha` no
///   login.
/// - Se [enabled] for true, [token] e [imageBytes] estão populados.
class CaptchaChallenge {
  final bool enabled;
  final String? token;
  final Uint8List? imageBytes;
  final int ttlSeconds;

  const CaptchaChallenge({
    required this.enabled,
    this.token,
    this.imageBytes,
    this.ttlSeconds = 180,
  });

  bool get isPresent => enabled && token != null && imageBytes != null;
}

class CaptchaService {
  /// Solicita um novo desafio ao backend.
  ///
  /// Retorna:
  /// - `CaptchaChallenge(enabled: false)` se o backend estiver com o captcha
  ///   desligado (env MOBILE_LOGIN_CAPTCHA_ENABLED=false), ou se a chamada
  ///   falhar de forma que valha a pena permitir login mesmo assim.
  /// - `CaptchaChallenge(enabled: true, token, imageBytes)` no caso normal.
  ///
  /// Nunca lança — em caso de falha total, devolve enabled=false. O
  /// AuthApiController::login ainda vai proteger validando o token.
  static Future<CaptchaChallenge> fetchNew() async {
    final res = await ApiClient.post('transporte/api/captcha/new', const {});

    if (res['success'] != true) {
      return const CaptchaChallenge(enabled: false);
    }

    final enabled = res['enabled'] == true;
    if (!enabled) {
      return const CaptchaChallenge(enabled: false);
    }

    final token = res['captcha_token']?.toString();
    final b64 = res['image_base64']?.toString();
    if (token == null || token.isEmpty || b64 == null || b64.isEmpty) {
      return const CaptchaChallenge(enabled: false);
    }

    Uint8List bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      return const CaptchaChallenge(enabled: false);
    }

    final ttl = int.tryParse((res['ttl_seconds'] ?? 180).toString()) ?? 180;

    return CaptchaChallenge(
      enabled: true,
      token: token,
      imageBytes: bytes,
      ttlSeconds: ttl,
    );
  }
}
