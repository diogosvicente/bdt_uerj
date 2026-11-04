// O pin do TLS (MSEC.5): em quem o app confia.
//
// Em 30/10/2026 venceu o último certificado da RNP do servidor, que passou a
// usar um da Let's Encrypt. A 1.0.0 só confiava na RNP e parou de conectar
// para todo mundo ("Falha de rede/HTTP." no login). Este teste garante que as
// duas autoridades estão no que o SslBootstrap carrega. A conexão de verdade
// com o servidor não roda aqui, porque teste não sai para a rede; para ela,
// ver "Como atualizar o pin" no `ssl_bootstrap.dart`.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bdt_uerj/api/ssl_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('o pin aceita a RNP e a Let\'s Encrypt', () async {
    await SslBootstrap.install();

    final subjects = [
      for (final pem in SslBootstrap.pemCarregado!)
        for (final der in _certificados(utf8.decode(pem))) _subject(der),
    ];

    for (final nome in const [
      // RNP
      'RNP ICPEdu GR46 OV TLS CA 2025',
      'GlobalSign Root R46',
      // Let's Encrypt
      'ISRG Root X1',
      'ISRG Root X2',
      'Root YR',
    ]) {
      expect(
        subjects.any((s) => _contem(s, nome)),
        isTrue,
        reason: '"$nome" não está no pin',
      );
    }

    // E o contexto do pin aceita os arquivos: um PEM estragado lançaria aqui.
    expect(SslBootstrap.pinnedContext, isNotNull);
  });
}

/// Os certificados (DER) de um texto PEM.
List<List<int>> _certificados(String pem) => RegExp(
      r'-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----',
    )
        .allMatches(pem)
        .map((m) => base64.decode(m.group(1)!.replaceAll(RegExp(r'\s'), '')))
        .toList();

/// O campo "subject" de um certificado DER, sem biblioteca: Certificate >
/// tbsCertificate > [versão], série, algoritmo, emissor, validade, subject.
///
/// É o subject, e não o certificado inteiro, porque o nome de uma raiz também
/// aparece no campo emissor dos certificados que ela assina (o da Root YR
/// traz "ISRG Root X1" como emissor).
List<int> _subject(List<int> der) {
  final (tbs, _) = _tlv(der, _tlv(der, 0).$1);
  var i = tbs;
  if (der[i] == 0xA0) i = _tlv(der, i).$2; // versão
  for (var campo = 0; campo < 4; campo++) {
    i = _tlv(der, i).$2; // série, algoritmo, emissor, validade
  }
  final (inicio, fim) = _tlv(der, i);
  return der.sublist(inicio, fim);
}

/// Início do conteúdo e fim de um TLV de DER que começa em [i].
(int, int) _tlv(List<int> der, int i) {
  var tamanho = der[i + 1];
  var inicio = i + 2;
  if (tamanho & 0x80 != 0) {
    final bytes = tamanho & 0x7f;
    tamanho = 0;
    for (var k = 0; k < bytes; k++) {
      tamanho = (tamanho << 8) | der[inicio + k];
    }
    inicio += bytes;
  }
  return (inicio, inicio + tamanho);
}

bool _contem(List<int> onde, String texto) {
  final alvo = utf8.encode(texto);
  for (var i = 0; i + alvo.length <= onde.length; i++) {
    var igual = true;
    for (var k = 0; k < alvo.length && igual; k++) {
      igual = onde[i + k] == alvo[k];
    }
    if (igual) return true;
  }
  return false;
}
