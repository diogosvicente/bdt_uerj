// A imagem do captcha que não carrega não pode deixar a tela muda.
//
// Até a 1.0.0, a falha ao buscar a imagem (rede ruim, erro do servidor,
// certificado recusado) virava "captcha desligado": a tela escondia o campo,
// o envio ia sem captcha, o backend recusava (CAPTCHA_ERROR) e o aviso era
// desenhado dentro da caixa escondida. O condutor tocava em Entrar e a tela
// só voltava, sem dizer nada.
//
// O backend daqui é um MockClient com o captcha ligado e a geração da imagem
// falhando: `captcha/new` responde 500, e o login e o "esqueci a senha"
// recusam por falta de captcha, como o `AuthApiController` faz.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bdt_uerj/api/ssl_bootstrap.dart';
import 'package:bdt_uerj/pages/esqueci_senha_page.dart';
import 'package:bdt_uerj/pages/login_page.dart';

final _chamadas = <String>[];

http.Response _json(Map<String, Object> corpo, int status) => http.Response(
      jsonEncode(corpo),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

MockClient _backendSemImagemDoCaptcha() => MockClient((req) async {
      final rota = req.url.path.replaceFirst(RegExp(r'^/'), '');
      _chamadas.add(rota);

      if (rota == 'transporte/api/captcha/new') {
        return _json({
          'success': false,
          'status': 'ERROR',
          'message': 'Falha ao gerar captcha.',
        }, 500);
      }

      // login e esqueci-senha: o captcha que não veio é exigido
      return _json({
        'success': false,
        'status': 'CAPTCHA_ERROR',
        'message': 'Captcha não encontrado. Recarregue a página.',
        'captcha_reload': true,
      }, 400);
    });

int _pedidosDeImagem() =>
    _chamadas.where((c) => c == 'transporte/api/captcha/new').length;

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    _chamadas.clear();
    SslBootstrap.setClientForTesting(_backendSemImagemDoCaptcha());
  });

  tearDown(() => SslBootstrap.setClientForTesting(null));

  testWidgets('login: a imagem que não veio aparece como falha, com o botão '
      'de tentar de novo', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pumpAndSettle();

    expect(_pedidosDeImagem(), 1);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(
      find.text('Não foi possível carregar a imagem. Toque no botão ao lado '
          'para tentar de novo.'),
      findsOneWidget,
    );
  });

  testWidgets('login: a recusa do backend por falta de captcha aparece na tela',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'CPF'), '12345678909');
    await tester.enterText(
        find.widgetWithText(TextField, 'Senha'), 'senha-inventada');
    final entrar = find.widgetWithText(ElevatedButton, 'Entrar');
    await tester.ensureVisible(entrar); // a tela de teste é baixa (800x600)
    await tester.pumpAndSettle();
    await tester.tap(entrar);
    await tester.pumpAndSettle();

    // O login foi ao backend, a recusa está na tela, e a imagem foi pedida de
    // novo.
    expect(_chamadas, contains('transporte/api/login'));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Para entrar, digite também o texto da imagem.'),
        findsOneWidget);
    expect(_pedidosDeImagem(), 2);

    await tester.pump(const Duration(seconds: 5)); // o SnackBar sai
  });

  testWidgets('esqueci a senha: a recusa por falta de captcha aparece no '
      'formulário', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EsqueciSenhaPage()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.refresh), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'CPF'), '12345678909');
    await tester.tap(find.text('Enviar link de redefinição'));
    await tester.pumpAndSettle();

    expect(_chamadas, contains('transporte/api/esqueci-senha'));
    expect(find.text('Para continuar, digite também o texto da imagem.'),
        findsOneWidget);
    expect(_pedidosDeImagem(), 2);
  });
}
