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

/// A imagem do captcha não veio: sem rede, certificado recusado, erro do
/// servidor ou resposta incompleta. [mensagem] é a do `ApiClient`, quando há.
class CaptchaIndisponivelException implements Exception {
  final String? mensagem;

  const CaptchaIndisponivelException([this.mensagem]);

  @override
  String toString() =>
      'CaptchaIndisponivelException: ${mensagem ?? 'sem detalhe'}';
}

class CaptchaService {
  /// Solicita um novo desafio ao backend.
  ///
  /// Retorna:
  /// - `CaptchaChallenge(enabled: false)` se o backend responder que o
  ///   captcha está desligado (env MOBILE_LOGIN_CAPTCHA_ENABLED=false).
  /// - `CaptchaChallenge(enabled: true, token, imageBytes)` no caso normal.
  ///
  /// Lança [CaptchaIndisponivelException] em qualquer outra resposta: sem
  /// rede, certificado recusado, erro do servidor, resposta incompleta. O
  /// `CaptchaField` mostra a falha, com o botão de tentar de novo.
  ///
  /// Até a 1.0.0 essas falhas viravam `enabled: false`, e a tela escondia o
  /// captcha como se o backend o tivesse desligado. O login ia sem captcha,
  /// o backend (com o captcha ligado) recusava, e o aviso era desenhado
  /// dentro da caixa escondida: a tela voltava sem dizer nada.
  static Future<CaptchaChallenge> fetchNew() async {
    final res = await ApiClient.post('transporte/api/captcha/new', const {});

    if (res['success'] != true) {
      throw CaptchaIndisponivelException(res['message']?.toString());
    }

    final enabled = res['enabled'] == true;
    if (!enabled) {
      return const CaptchaChallenge(enabled: false);
    }

    final token = res['captcha_token']?.toString();
    final b64 = res['image_base64']?.toString();
    if (token == null || token.isEmpty || b64 == null || b64.isEmpty) {
      throw const CaptchaIndisponivelException(
        'Resposta do captcha sem imagem.',
      );
    }

    Uint8List bytes;
    try {
      bytes = base64Decode(b64);
    } on FormatException {
      throw const CaptchaIndisponivelException('Imagem do captcha inválida.');
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
