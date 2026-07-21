import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../services/token_storage.dart';

class ApiClient {
  // ==========================================================================
  // Controle de ambiente via --dart-define
  //
  // Valor lido no build time. Se nada for passado, o default é "production" —
  // então nunca corre o risco de subir pra loja apontando pro localhost.
  //
  // Para testar em desenvolvimento, passe --dart-define=APP_ENV=<opção>:
  //
  //   flutter run --dart-define=APP_ENV=localhost   # celular USB + adb reverse tcp:8080 tcp:80
  //   flutter run --dart-define=APP_ENV=emulator    # emulador Android (10.0.2.2)
  //   flutter run --dart-define=APP_ENV=wsl         # PC e celular na mesma LAN (WSL host)
  //   flutter run --dart-define=APP_ENV=localhostIp # IP fixo da rede UERJ
  //   flutter run                                   # default: production
  //
  // O .vscode/launch.json tem perfis prontos ("Dev (localhost via USB)",
  // "Prod") — basta selecionar em "Run and Debug" (Ctrl+Shift+D) e F5.
  //
  // Em release build (`flutter build apk --release`), independente do dart-define,
  // o app sempre vai pra produção — garantia extra.
  // ==========================================================================
  static const String _env = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'production',
  );

  // ✅ Bases por ambiente
  //
  // "localhost": porta 8080 no celular é encaminhada para 80 do PC via
  // `adb reverse tcp:8080 tcp:80` (portas <1024 são privilegiadas no
  // Android). Uso: celular físico plugado via USB, sem depender de WiFi
  // comum entre PC e celular.
  static const String _localhostBase = "http://localhost:8080/e-prefeitura";
  static const String _localhostIp = "http://152.92.228.217/e-prefeitura";
  // "emulator": 10.0.2.2 é o alias mágico do emulador Android para localhost do host.
  static const String _emulatorBase = "http://10.0.2.2/e-prefeitura";
  static const String _wslBase = "http://192.168.1.138/e-prefeitura";
  static const String _productionBase = "https://www.e-prefeitura.uerj.br";

  /// Retorna a baseUrl de acordo com o ambiente.
  /// Em release: sempre produção (segurança).
  /// Em debug: usa _env vindo do --dart-define (default: production).
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
        // fallback seguro
        return _productionBase;
    }
  }

  /// Helper: junta base + endpoint com segurança (evita // e / sobrando).
  static Uri _buildUri(String endpoint) {
    final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final cleanEndpoint = endpoint.replaceAll(RegExp(r'^/+'), '');
    return Uri.parse('$cleanBase/$cleanEndpoint');
  }

  // ═══════════════════════════════════════════════════════════════
  // MSEC.4 — refresh automático em TOKEN_EXPIRED
  //
  // Fluxo:
  //   1) POST original com Bearer <access>
  //   2) Se resposta = 401 status=TOKEN_EXPIRED, dispara refresh
  //      (dedup: só 1 refresh no ar, requests concorrentes esperam)
  //   3) Se refresh OK → grava par novo + retenta a request original
  //   4) Se refresh FAIL → devolve a resposta 401 original (a UI /
  //      AuthService.verifyToken trata como "sessão morta")
  //
  // NUNCA retenta mais de uma vez — evita loops infinitos.
  //
  // Endpoints do próprio refresh não passam pelo retry (evita
  // recursão): rota `bdt/token/refresh` sinaliza via _isRefreshCall.
  // ═══════════════════════════════════════════════════════════════

  /// Completer compartilhado — se N requests recebem TOKEN_EXPIRED
  /// simultaneamente, só a primeira dispara o refresh; as outras
  /// aguardam esse Future e reusam o resultado.
  static Future<bool>? _refreshInFlight;

  static bool _isRefreshCall(String endpoint) =>
      endpoint.contains('/bdt/token/refresh') ||
      endpoint.contains('/bdt/token/revogar');

  /// Faz POST JSON e retorna Map padronizado (sempre tentando decodificar JSON).
  static Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> data, {
    bool isRetry = false,
  }) async {
    Map<String, dynamic> resp;
    try {
      final token = await TokenStorage.readAccess();
      resp = await _doPost(endpoint, data, token);
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

    // MSEC.4 — retry silencioso em TOKEN_EXPIRED (só 1 vez).
    // Nunca retenta o próprio refresh/revogar (evita recursão).
    final isExpired = resp['http_status'] == 401 &&
        (resp['status']?.toString() == 'TOKEN_EXPIRED');
    if (isExpired && !isRetry && !_isRefreshCall(endpoint)) {
      final refreshOk = await refreshTokens();
      if (refreshOk) {
        debugPrint("🔄 Retry após refresh: $endpoint");
        return post(endpoint, data, isRetry: true);
      }
      // refresh falhou → devolve a resposta 401 original; caller
      // (AuthService.verifyToken ou UI) decide o que fazer.
    }
    return resp;
  }

  /// Executa o POST HTTP puro (sem retry). Separado pra facilitar teste
  /// e pra o wrapper acima poder decidir o retry.
  static Future<Map<String, dynamic>> _doPost(
    String endpoint,
    Map<String, dynamic> data,
    String? token,
  ) async {
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

    final decoded = _tryDecodeJsonMap(body);
    if (decoded != null) {
      decoded["http_status"] = res.statusCode;
      return decoded;
    }

    return {
      "success": false,
      "status": "HTTP_ERROR",
      "http_status": res.statusCode,
      "message": body.isNotEmpty
          ? "Resposta inválida do servidor."
          : "Servidor retornou resposta vazia.",
      "raw": rawBody,
    };
  }

  /// Chama `bdt/token/refresh` (dedupado). Retorna true se OK e o par
  /// novo já foi gravado no `TokenStorage`; false em qualquer falha.
  static Future<bool> refreshTokens() async {
    // Dedup: se já tem refresh em andamento, espera ele.
    final existing = _refreshInFlight;
    if (existing != null) return existing;

    final completer = Completer<bool>();
    _refreshInFlight = completer.future;

    () async {
      try {
        final refresh = await TokenStorage.readRefresh();
        if (refresh == null || refresh.isEmpty) {
          debugPrint("🔒 refresh: sem refresh token no storage");
          completer.complete(false);
          return;
        }

        // Chama SEM retry (evita recursão). Passa o refresh no body,
        // não como Bearer — a rota é pública nesse sentido.
        final res = await _doPost(
          'transporte/api/bdt/token/refresh',
          {'refresh_token': refresh},
          null, // sem Bearer — o refresh_token do body é a credencial
        );

        if (res['success'] == true) {
          final newAccess  = (res['access_token']  ?? '').toString();
          final newRefresh = (res['refresh_token'] ?? '').toString();
          if (newAccess.isNotEmpty) {
            await TokenStorage.writePair(
              access: newAccess,
              refresh: newRefresh,
            );
            debugPrint("🔓 refresh OK — novo par gravado");
            completer.complete(true);
            return;
          }
        }
        debugPrint("🔒 refresh FALHOU — status=${res['status']}");
        completer.complete(false);
      } catch (e) {
        debugPrint("🔒 refresh exception: $e");
        completer.complete(false);
      } finally {
        _refreshInFlight = null;
      }
    }();

    return completer.future;
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
