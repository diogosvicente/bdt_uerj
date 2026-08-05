import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../services/token_storage.dart';
import 'pii_sanitizer.dart';
import 'ssl_bootstrap.dart';

class ApiClient {
  // ==========================================================================
  // Sprint 028 de segurança — item A7-mobile (2026-08-05)
  //
  // Este arquivo imprimia o corpo de TODA requisição e resposta cru. No login
  // isso significava CPF e senha em texto puro no logcat, mais os tokens de
  // acesso e refresh na resposta.
  //
  // Dois problemas independentes, e os dois precisavam de correção:
  //
  //   1) `debugPrint` NÃO é removido em release. O nome engana — ele se chama
  //      assim porque estrangula a taxa de saída para não perder linhas, não
  //      porque só rode em debug. Um APK de produção gravava a senha do
  //      condutor a cada login. → resolvido por `_log`, que checa kDebugMode.
  //
  //   2) Mesmo em debug o log não devia trazer PII: durante teste contra a
  //      base real são CPFs de pessoas de verdade na tela de quem
  //      desenvolve. → resolvido pelo `PiiSanitizer`, espelho da política do
  //      backend (`app/Libraries/PiiSanitizer.php`).
  //
  // Quem tem acesso ao logcat: qualquer um com depuração USB no aparelho,
  // relatórios de bug do Android e ferramentas de diagnóstico do fabricante.
  // Desde a API 16 um app comum não lê o log de outro — o que reduz, mas não
  // elimina, porque a senha é reutilizável (diferente de um token de 15 min).
  // ==========================================================================

  /// Log de diagnóstico. Silencioso em release, ao contrário de `debugPrint`.
  ///
  /// Use para QUALQUER coisa derivada de tráfego. Para mensagens fixas que
  /// precisam sobreviver em produção existe o `Logger` de `utils/logger.dart`,
  /// que escreve em release de propósito — mas ele recebe `String`, então
  /// nunca passe payload para lá sem sanitizar.
  static void _log(String msg) {
    if (kDebugMode) debugPrint(msg);
  }

  // ==========================================================================
  // Endereço da API — SEMPRE produção.
  //
  // Até 2026-07-31 existia um switch com cinco ambientes (localhost via
  // `adb reverse`, emulador em 10.0.2.2, host WSL na LAN, IP fixo da rede
  // UERJ) selecionados por `--dart-define=APP_ENV=...`. Foi removido a
  // pedido: o backend agora vive em produção e o app é distribuído apontando
  // só para lá.
  //
  // Ganhos de tirar: some a classe inteira de erro "testei apontando pro
  // lugar errado", e o comportamento passa a ser idêntico em debug e em
  // release — antes, `kReleaseMode` forçava produção e o debug podia
  // divergir, então um bug só reproduzível em release ficava difícil de
  // enxergar.
  //
  // Se um dia precisar apontar para outro host (homologação, por exemplo),
  // o caminho é reintroduzir o dart-define aqui — e não trocar a constante
  // e arriscar comitar apontando para a máquina de alguém.
  //
  // O pinning de TLS (MSEC.5) casa com a cadeia da RNP que serve este host;
  // trocar de domínio exige rever `assets/certs/rnp_icpedu_chain.pem`.
  // ==========================================================================
  static const String _productionBase = "https://www.e-prefeitura.uerj.br";

  /// Sobrescrita por BUILD (2026-08-04), reintroduzida como o comentário
  /// acima previa — para apontar o app a um backend local durante o
  /// desenvolvimento:
  ///
  ///     flutter run --dart-define=API_BASE_URL=http://10.0.2.2/e-prefeitura
  ///
  /// Vazio (o padrão) = produção. A constante de produção continua sendo a
  /// única coisa escrita no código, então **não há como commitar o app
  /// apontando para a máquina de alguém** — o desvio existe só no comando
  /// de build de quem está desenvolvendo.
  ///
  /// ⚠️ No EMULADOR, `localhost` é o próprio emulador. O host onde roda o
  /// Apache é **10.0.2.2** (alias que o emulador cria para a máquina).
  /// Usar `http://localhost/...` aqui não alcança o seu backend.
  static const String _overrideBase = String.fromEnvironment('API_BASE_URL');

  /// Endereço base da API. Produção por padrão; `--dart-define=API_BASE_URL`
  /// desvia para outro host em tempo de build.
  static String get baseUrl =>
      _overrideBase.isNotEmpty ? _overrideBase : _productionBase;

  /// True quando o app está falando com um backend que não é o de produção.
  /// Útil para exibir um aviso na UI e evitar o clássico "testei achando que
  /// era produção".
  static bool get usandoBaseCustomizada => _overrideBase.isNotEmpty;

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
      _log("⏰ Timeout na requisição para $endpoint");
      return {
        "success": false,
        "status": "TIMEOUT",
        "message": "Timeout na requisição.",
      };
    } catch (e, st) {
      // A7-mobile — a mensagem de exceção pode ecoar trecho do corpo, e o
      // stack trace inteiro em release é exposição de informação sem ganho.
      _log("❌ Exceção HTTP em $endpoint: $e");
      _log("$st");
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
        _log("🔄 Retry após refresh: $endpoint");
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

    _log("➡️ POST $uri");
    // A7-mobile — `data` carrega cpf/senha no login. `sanitize` devolve uma
    // CÓPIA tratada; o `data` original segue intacto para a requisição.
    _log("📦 Body: ${PiiSanitizer.sanitize(data)}");

    // MSEC.5 — `SslBootstrap.client` aplica certificate pinning em
    // produção (só confia na cadeia da RNP). Ver `ssl_bootstrap.dart`.
    final res = await SslBootstrap.client
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

    // A7-mobile — a resposta do login traz access_token/refresh_token, e a do
    // perfil traz e-mail. `sanitizeJson` decodifica, trata e reserializa;
    // quando não é JSON (página de erro do Apache), trunca.
    _log("⬅️ Response ${res.statusCode}: ${PiiSanitizer.sanitizeJson(body)}");

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

  /// Sprint W+M — POST multipart pra endpoints de upload de arquivo
  /// (Sprint 17 W+M Fase 2: fotos de ocorrência). Adiciona Bearer +
  /// TIMEOUT maior (30s) porque upload de foto é grande. Retorna o
  /// mesmo Map padronizado do `post()`.
  ///
  /// [fields] são os campos texto do form (equivalente aos `-F` do curl).
  /// [fileField] é o nome do campo (ex: "foto"), [fileBytes] o conteúdo,
  /// [filename] o nome do arquivo (o backend usa a extensão).
  ///
  /// Diferente do `post()`, este método **não** retenta em TOKEN_EXPIRED —
  /// upload é grande demais pra fazer 2x; se o access expirou, a chamada
  /// falha e o app pede login/refresh na próxima interação leve.
  static Future<Map<String, dynamic>> postMultipart(
    String endpoint, {
    required Map<String, String> fields,
    required String fileField,
    required List<int> fileBytes,
    required String filename,
  }) async {
    try {
      final token = await TokenStorage.readAccess();
      final uri = _buildUri(endpoint);

      _log("➡️ POST-multipart $uri (${fileBytes.length} bytes)");

      final req = http.MultipartRequest('POST', uri);
      if (token != null && token.isNotEmpty) {
        req.headers['Authorization'] = 'Bearer $token';
      }
      req.fields.addAll(fields);
      req.files.add(http.MultipartFile.fromBytes(
        fileField,
        fileBytes,
        filename: filename,
      ));

      // MSEC.5 — `req.send()` usa o client default do package:http (sem
      // pin). Enviamos pelo client pinado pra o upload de foto seguir a
      // mesma regra dos demais endpoints.
      final streamed = await SslBootstrap.client
          .send(req)
          .timeout(const Duration(seconds: 30));
      final res = await http.Response.fromStream(streamed);

      final body = res.body.trim();
      // A7-mobile — antes truncava em 200 chars "no escuro"; truncar não é
      // sanitizar (um token cabe folgado em 200 caracteres).
      _log("⬅️ Response ${res.statusCode}: ${PiiSanitizer.sanitizeJson(body)}");

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
        "raw": res.body,
      };
    } on TimeoutException {
      return {
        "success": false,
        "status": "TIMEOUT",
        "message": "Timeout no upload da foto.",
      };
    } catch (e, st) {
      _log("❌ Exceção HTTP multipart em $endpoint: $e\n$st");
      return {
        "success": false,
        "status": "EXCEPTION",
        "message": "Falha de rede no upload.",
      };
    }
  }

  /// Sprint W+M — GET/POST que retorna binário cru (ex: foto de ocorrência
  /// via `bdt/ocorrencias/fotos/obter`). Envia Bearer e retorna os bytes
  /// da resposta se 200, ou `null` se 204/404/erro. Não usa retry.
  ///
  /// Backend espera POST + JSON body (mesma convenção dos outros
  /// endpoints), então esta chamada é POST mesmo devolvendo binário.
  static Future<List<int>?> postForBytes(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    try {
      final token = await TokenStorage.readAccess();
      final uri = _buildUri(endpoint);
      final res = await SslBootstrap.client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
            },
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) return res.bodyBytes;
      _log("postForBytes $endpoint: http=${res.statusCode}");
      return null;
    } catch (e) {
      _log("❌ postForBytes $endpoint exception: $e");
      return null;
    }
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
          _log("🔒 refresh: sem refresh token no storage");
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
            _log("🔓 refresh OK — novo par gravado");
            completer.complete(true);
            return;
          }
        }
        _log("🔒 refresh FALHOU — status=${res['status']}");
        completer.complete(false);
      } catch (e) {
        _log("🔒 refresh exception: $e");
        completer.complete(false);
      } finally {
        _refreshInFlight = null;
      }
    }();

    return completer.future;
  }

  /// Tenta decodificar um JSON e retornar somente se for `Map<String, dynamic>`.
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
