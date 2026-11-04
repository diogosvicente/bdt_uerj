// Mensagem do ApiClient quando o certificado do servidor é recusado.
//
// Certificado recusado no handshake não é falta de rede. Até a 1.0.0 os dois
// davam o mesmo "Falha de rede/HTTP.", e foi assim que, quando o servidor
// trocou de autoridade certificadora em 30/10/2026, ninguém tinha como saber
// que o app precisava ser atualizado.

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bdt_uerj/api/api_client.dart';
import 'package:bdt_uerj/api/ssl_bootstrap.dart';

const _mensagemTls =
    'Não foi possível conectar com segurança ao servidor. Confira a data e a '
    'hora do celular. Se estiverem certas, atualize o aplicativo.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => SslBootstrap.setClientForTesting(null));

  /// O client do app recusando o certificado, como o handshake faz.
  void certificadoRecusado() => SslBootstrap.setClientForTesting(
        MockClient((_) async => throw const HandshakeException(
              'CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate',
            )),
      );

  test('certificado recusado tem mensagem própria', () async {
    certificadoRecusado();

    final res = await ApiClient.post('transporte/api/login', const {});

    expect(res['success'], isFalse);
    expect(res['status'], 'TLS_ERROR');
    expect(res['message'], _mensagemTls);
  });

  test('o envio de foto também diz que o certificado foi recusado', () async {
    certificadoRecusado();

    final res = await ApiClient.postMultipart(
      'transporte/api/bdt/ocorrencias/fotos/upload',
      fields: const {},
      fileField: 'foto',
      fileBytes: const [1, 2, 3],
      filename: 'foto.jpg',
    );

    expect(res['status'], 'TLS_ERROR');
    expect(res['message'], _mensagemTls);
  });

  test('sem rede continua "Falha de rede/HTTP."', () async {
    SslBootstrap.setClientForTesting(
      MockClient((_) async => throw const SocketException('Network is unreachable')),
    );

    final res = await ApiClient.post('transporte/api/login', const {});

    expect(res['status'], 'EXCEPTION');
    expect(res['message'], 'Falha de rede/HTTP.');
  });
}
