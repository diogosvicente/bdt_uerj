import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/ssl_bootstrap.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'pages/bdt_page.dart';
import 'pages/bdt_form_page.dart';
import 'pages/pre_bdt_form_page.dart';
import 'pages/validacao_inicio_page.dart';
import 'pages/assinatura_marco_page.dart';
import 'pages/conclusao_page.dart';
import 'pages/historico_ocorrencias_page.dart';
import 'pages/ocorrencia_detalhe_page.dart';
import 'services/alertas_service.dart';
import 'services/background_location_service.dart';
import 'theme/app_theme.dart';

/// Chave global do Navigator — usada pelo `AlertasService.onTap` para
/// abrir a tela do BDT quando o usuário toca numa notificação, sem
/// precisar de context.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Carrega a CA da RNP no truststore ANTES de qualquer requisição HTTPS.
  // Sem isso, o cert de https://www.e-prefeitura.uerj.br é rejeitado
  // com HandshakeException: CERTIFICATE_VERIFY_FAILED (CA não confiável).
  await SslBootstrap.install();

  // Registra o foreground service Android responsável por enviar coordenadas
  // mesmo com tela bloqueada / app em background. Não inicia automaticamente —
  // só sobe quando um trecho é iniciado (GpsLiveService.start).
  await BackgroundLocationService.init();

  // Sprint M5 — alertas locais 1h/30min antes de cada BDT. Só inicializa;
  // o agendamento em si acontece quando a HomePage carrega a lista do dia
  // (`HomePage._reload` chama `AlertasService.sincronizarComBdtsDoDia`).
  await AlertasService.init();
  AlertasService.onTap = (bdtId) {
    navigatorKey.currentState?.pushNamed('/bdt', arguments: bdtId);
  };

  runApp(const BdtUerjApp());
}

class BdtUerjApp extends StatelessWidget {
  const BdtUerjApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
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
        "/pre_bdt/novo":   (_) => const PreBdtFormPage(),
        // Edição: mesmo widget, decide o modo pelo `arguments: int bdtId`.
        "/pre_bdt/editar": (_) => const PreBdtFormPage(),
        // Sprint M4
        "/validacao/inicio": (_) => const ValidacaoInicioPage(), // arg: int bdtId
        "/marco/assinatura": (_) => const AssinaturaMarcoPage(), // arg: AssinaturaMarcoArgs
        "/conclusao":       (_) => const ConclusaoPage(),        // arg: int bdtId
        // Sprint W+M (Sprint 17 web)
        "/ocorrencias/historico": (_) => const HistoricoOcorrenciasPage(),
        "/ocorrencia/detalhe":    (_) => const OcorrenciaDetalhePage(), // arg: int id
      },

      theme: AppTheme.light(),
    );
  }
}
