import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bdt_uerj/api/pii_sanitizer.dart';

/// Sprint 028 de segurança — item **A7-mobile**.
///
/// Os payloads destes testes são os **reais**, copiados do logcat durante o
/// teste de login de 2026-08-05 que revelou o problema. Se algum dia alguém
/// mexer no `PiiSanitizer` e reabrir o vazamento, é aqui que quebra.
void main() {
  group('PiiSanitizer.sanitize — requisição', () {
    test('redige a senha e mascara o CPF no corpo do login', () {
      // Exatamente o que aparecia no log antes da correção.
      final corpo = {
        'cpf': '12192209738',
        'senha': 'Teste@123456',
        'manter_conectado': false,
        'captcha_token': '25c2f95c1bb46dbac0085e3848539d6f',
        'captcha': 'CARTA',
      };

      final limpo = PiiSanitizer.sanitize(corpo) as Map<String, dynamic>;

      expect(limpo['senha'], '[REDACTED]');
      expect(limpo['cpf'], '*******9738'); // só os 4 últimos sobrevivem
      expect(limpo['cpf'], isNot(contains('12192')));

      // O que não é sensível continua legível — senão o log perde a utilidade.
      expect(limpo['manter_conectado'], false);
      expect(limpo['captcha'], 'CARTA');
    });

    test('não modifica o mapa original', () {
      final corpo = {'senha': 'Teste@123456', 'cpf': '12192209738'};
      PiiSanitizer.sanitize(corpo);

      // A requisição de verdade precisa sair com o dado real.
      expect(corpo['senha'], 'Teste@123456');
      expect(corpo['cpf'], '12192209738');
    });
  });

  group('PiiSanitizer.sanitizeJson — resposta', () {
    test('redige os tokens da resposta de login', () {
      final resposta = jsonEncode({
        'success': true,
        'status': 'SUCCESS',
        'access_token': '7257322185f7189fa5e8645bb0dc46c1',
        'refresh_token': '7da3b06a64b71e56ba55d04ddc031f97',
        'token': '7257322185f7189fa5e8645bb0dc46c1',
        'usuario': {'id': '46', 'nome': 'Diogo da Silva Vicente do Nascimento'},
      });

      final limpo = PiiSanitizer.sanitizeJson(resposta);

      expect(limpo, isNot(contains('7257322185f7189fa5e8645bb0dc46c1')));
      expect(limpo, isNot(contains('7da3b06a64b71e56ba55d04ddc031f97')));
      expect(limpo, contains('[REDACTED]'));

      // `nome` não é mascarado: é o que identifica a sessão no log, e sozinho
      // não abre porta nenhuma. A política do backend também o deixa passar.
      expect(limpo, contains('Diogo da Silva'));
      expect(limpo, contains('SUCCESS'));
    });

    test('mascara e-mail e telefone se voltarem em qualquer resposta', () {
      final resposta = jsonEncode({
        'usuario': {
          'email': 'fulano@uerj.br',
          'telefone1': '21999887766',
          'matricula': '20260001',
        }
      });

      final limpo = PiiSanitizer.sanitizeJson(resposta);

      expect(limpo, isNot(contains('fulano@uerj.br')));
      expect(limpo, isNot(contains('21999887766')));
      expect(limpo, contains('*j.br'));
    });

    test('resume o base64 do captcha em vez de despejar 400 caracteres', () {
      final resposta = jsonEncode({
        'captcha_token': 'abc',
        'image_base64': 'iVBORw0KGgoAAAANSUhEUg${'A' * 400}',
      });

      final limpo = PiiSanitizer.sanitizeJson(resposta);

      expect(limpo, isNot(contains('iVBORw0KGgo')));
      expect(limpo, contains('chars]'));
    });

    test('trunca corpo não-JSON em vez de imprimir inteiro', () {
      // Página de erro do Apache: não dá para saber o que há dentro.
      final html = '<html><body>${'x' * 500}</body></html>';

      final limpo = PiiSanitizer.sanitizeJson(html);

      expect(limpo.length, lessThan(260));
      expect(limpo, contains('chars)'));
    });

    test('corpo vazio não quebra', () {
      expect(PiiSanitizer.sanitizeJson(''), '(vazio)');
    });
  });

  group('PiiSanitizer.mascarar', () {
    test('valor curto vira **** inteiro', () {
      // Com 4 caracteres ou menos, "manter os 4 últimos" exporia tudo.
      expect(PiiSanitizer.mascarar('123'), '****');
      expect(PiiSanitizer.mascarar('1234'), '****');
    });

    test('mantém o comprimento original para conferência visual', () {
      expect(PiiSanitizer.mascarar('12192209738').length, 11);
    });

    test('null não quebra', () {
      expect(PiiSanitizer.mascarar(null), '****');
    });
  });
}
