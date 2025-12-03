import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static const String _env = "emulator"; 
  // opções: "localhost", "emulator", "wsl", "production"

  static const String _localhostBase   = "http://localhost/e-prefeitura";
  static const String _emulatorBase    = "http://10.0.2.2/e-prefeitura"; 
  static const String _wslBase         = "http://192.168.1.138/e-prefeitura";
  static const String _productionBase  = "https://www.e-prefeitura.uerj.br";

  static String get baseUrl {
    if (kReleaseMode) return _productionBase;

    switch (_env) {
      case "localhost":
        return _localhostBase;
      case "emulator":
        return _emulatorBase;
      case "wsl":
        return _wslBase;
      default:
        return _localhostBase;
    }
  }

  static Future<Map<String, dynamic>?> post(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");

      final uri = Uri.parse("$baseUrl/$endpoint");

      print("➡️ POST $uri");
      print("📦 Body: $data");

      final res = await http
          .post(
            uri,
            headers: {
              "Content-Type": "application/json",
              if (token != null) "Authorization": "Bearer $token",
            },
            body: json.encode(data),
          )
          .timeout(const Duration(seconds: 10));

      print("⬅️ Response ${res.statusCode}: ${res.body}");

      if (res.statusCode == 200) {
        try {
          return json.decode(res.body) as Map<String, dynamic>;
        } catch (e) {
          print("❌ Erro ao decodificar JSON: $e");
          return null;
        }
      }

      print("❌ Erro POST $endpoint -> ${res.statusCode} ${res.body}");
      return null;
    } on TimeoutException {
      print("⏰ Timeout na requisição para $endpoint");
      return null;
    } catch (e, st) {
      print("❌ Exceção HTTP em $endpoint: $e");
      print(st);
      return null;
    }
  }
}
