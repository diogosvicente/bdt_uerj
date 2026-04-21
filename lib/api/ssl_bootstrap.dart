import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;

/// Bootstrap de SSL para confiar na CA "RNP ICPEdu GR46 OV TLS CA 2025"
/// (Autoridade Certificadora que assina o certificado de
/// https://www.e-prefeitura.uerj.br).
///
/// Essa CA não está no truststore padrão do Android, então sem isso o
/// app lança `HandshakeException: CERTIFICATE_VERIFY_FAILED`.
///
/// O bundle em `assets/certs/rnp_icpedu_chain.pem` contém:
///   - RNP ICPEdu GR46 OV TLS CA 2025 (intermediate)
///   - GlobalSign Root R46 (root — fallback para Android <11 que não a traz)
///
/// Uso: chamar `await SslBootstrap.install()` em `main()` ANTES de
/// qualquer chamada de rede.
class SslBootstrap {
  static bool _installed = false;

  static Future<void> install() async {
    if (_installed) return;
    _installed = true;

    final pem = await rootBundle.load('assets/certs/rnp_icpedu_chain.pem');
    final bytes = pem.buffer.asUint8List();

    // Adiciona a CA ao contexto default (usado pelo dart:io HttpClient,
    // que por sua vez é o transporte do package:http em plataformas nativas).
    try {
      SecurityContext.defaultContext.setTrustedCertificatesBytes(bytes);
    } on TlsException catch (e) {
      // "CERT_ALREADY_IN_HASH_TABLE" pode ocorrer em hot restart.
      // Qualquer outra falha é relevante, então relança.
      if (!e.toString().contains('CERT_ALREADY_IN_HASH_TABLE')) {
        rethrow;
      }
    }
  }
}
