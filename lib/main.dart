import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/ssl_bootstrap.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'pages/bdt_page.dart';
import 'pages/bdt_form_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Carrega a CA da RNP no truststore ANTES de qualquer requisição HTTPS.
  // Sem isso, o cert de https://www.e-prefeitura.uerj.br é rejeitado
  // com HandshakeException: CERTIFICATE_VERIFY_FAILED (CA não confiável).
  await SslBootstrap.install();

  runApp(const BdtUerjApp());
}

class BdtUerjApp extends StatelessWidget {
  const BdtUerjApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BDT UERJ',
      debugShowCheckedModeBanner: false,

      locale: const Locale('pt', 'BR'),
      supportedLocales: const [
        Locale('pt', 'BR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // ✅ FORÇA 24H NO APP TODO (inclusive showTimePicker)
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },

      initialRoute: "/login",
      routes: {
        "/login": (_) => const LoginPage(),
        "/home": (_) => const HomePage(),
        "/bdt": (_) => const BdtPage(),
        "/bdt_form": (_) => const BdtFormPage(),
      },

      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
    );
  }
}
