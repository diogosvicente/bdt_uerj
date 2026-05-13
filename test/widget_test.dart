// Smoke test mínimo: garante que o app inicializa sem crash.
//
// O app real depende de SslBootstrap (carga de CA) e do
// BackgroundLocationService.init, que precisam de plataforma. Por isso
// montamos diretamente o widget root sem passar pelo `main()`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bdt_uerj/main.dart';

void main() {
  testWidgets('App monta sem crash', (WidgetTester tester) async {
    await tester.pumpWidget(const BdtUerjApp());
    // o root deve renderizar a tela de login (initialRoute "/login")
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
