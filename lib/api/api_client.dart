import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  // ✅ Controle de ambiente
  // opções: "localhost", "localhostIp", "emulator", "wsl", "production"
  static const String _env = "production";

  // ✅ Bases
  static const String _localhostBase = "http://localhost/e-prefeitura";
  static const String _localhostIp = "http://152.92.228.217/e-prefeitura";
  static const String _emulatorBase = "http://10.0.2.2/e-prefeitura";
  static const String _wslBase = "http://192.168.1.138/e-prefeitura";

  // ✅ Produção (como você informou)
  static const String _productionBase = "https://www.e-prefeitura.uerj.br";
  // Se a produção tiver /e-prefeitura, troque para:
  // static const String _productionBase = "https://www.e-prefeitura.uerj.br/e-prefeitura";

  /// Retorna a baseUrl de acordo com o ambiente.
  /// Em release: sempre produção.
  /// Em debug: usa _env.
  static String get baseUrl {
    if (kReleaseMode) return _productionBase;

    switch (_env) {
      case "production":
        return _productionBase;
      case "localhost":
        return _localhostBase;
      case "localhostIp":
        return _localhostIp;
      case "emulator":
        return _emulatorBase;
      case "wsl":
        return _wslBase;
      default:
        // ✅ melhor fallback do que cair em localhost sem querer
        return _productionBase;
    }
  }

  /// Helper: junta base + endpoint com segurança (evita // e / sobrando).
  static Uri _buildUri(String endpoint) {
    final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final cleanEndpoint = endpoint.replaceAll(RegExp(r'^/+'), '');
    return Uri.parse('$cleanBase/$cleanEndpoint');
  }

  /// Faz POST JSON e retorna Map padronizado (sempre tentando decodificar JSON).
  static Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");

      final uri = _buildUri(endpoint);

      debugPrint("➡️ POST $uri");
      debugPrint("📦 Body: $data");

      final res = await http
          .post(
            uri,
            headers: {
              "Content-Type": "application/json",
              if (token != null && token.isNotEmpty)
                "Authorization": "Bearer $token",
            },
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 10));

      final rawBody = res.body;
      final body = rawBody.trim();

      debugPrint("⬅️ Response ${res.statusCode}: $body");

      // ✅ tenta decodificar JSON SEMPRE
      final decoded = _tryDecodeJsonMap(body);

      // ✅ se veio JSON, retorna ele (mesmo em 400/401/403)
      if (decoded != null) {
        decoded["http_status"] = res.statusCode;
        return decoded;
      }

      // ✅ se não veio JSON, retorna erro padronizado
      return {
        "success": false,
        "status": "HTTP_ERROR",
        "http_status": res.statusCode,
        "message": body.isNotEmpty
            ? "Resposta inválida do servidor."
            : "Servidor retornou resposta vazia.",
        "raw": rawBody,
      };
    } on TimeoutException {
      debugPrint("⏰ Timeout na requisição para $endpoint");
      return {
        "success": false,
        "status": "TIMEOUT",
        "message": "Timeout na requisição.",
      };
    } catch (e, st) {
      debugPrint("❌ Exceção HTTP em $endpoint: $e");
      debugPrint("$st");
      return {
        "success": false,
        "status": "EXCEPTION",
        "message": "Falha de rede/HTTP.",
      };
    }
  }

  /// Tenta decodificar um JSON e retornar somente se for Map<String, dynamic>.
  static Map<String, dynamic>? _tryDecodeJsonMap(String body) {
    if (body.isEmpty) return null;

    try {
      final obj = jsonDecode(body);
      if (obj is Map) {
        return Map<String, dynamic>.from(obj);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
