import 'package:flutter/material.dart';
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'pages/bdt_page.dart';

void main() {
  runApp(const BdtUerjApp());
}

class BdtUerjApp extends StatelessWidget {
  const BdtUerjApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BDT UERJ',
      debugShowCheckedModeBanner: false,
      initialRoute: "/login",
      routes: {
        "/login": (_) => const LoginPage(),
        "/home": (_) => const HomePage(),
        "/bdt": (_) => const BdtPage(),
      },
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
    );
  }
}
