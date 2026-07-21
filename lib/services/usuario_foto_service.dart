import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../utils/logger.dart';
import 'token_storage.dart';
import 'usuario_foto_storage.dart';

/// Orquestra o cache + fetch da foto do condutor logado (Sprint MSEC.6).
///
/// - `obterCached()`: retorna o arquivo local imediato (ou null).
///   Se o TTL expirou, dispara `refetch()` em background — não bloqueia
///   a UI. Próxima chamada já vê a foto atualizada.
/// - `refetch()`: chama `POST bdt/usuario/foto` com Bearer.
///   Envia `If-None-Match` se tem ETag salvo → 304 = mantém local
///   e só reseta o TTL; 200 = grava novo binário + ETag; 204 =
///   não tem foto cadastrada, limpa local.
/// - Se receber 401 TOKEN_EXPIRED, chama `ApiClient.refreshTokens()`
///   e retenta UMA vez.
///
/// **NÃO** usa `ApiClient.post` porque esse presume resposta JSON;
/// aqui a resposta pode ser binário puro ou vazia. Fetch manual via
/// `http.post` + Bearer lido do `TokenStorage`.
class UsuarioFotoService {
  static const _log = Logger('FOTO-SVC');

  /// Tempo máximo que o cache local é considerado fresco. Passou disso,
  /// próxima leitura dispara refetch em bg. O ETag/If-None-Match
  /// garante que se a foto no backend não mudou, o server responde
  /// 304 e a gente só reseta o TTL — sem baixar bytes de novo.
  static const Duration _ttl = Duration(hours: 24);

  /// Retorna o arquivo local da foto, atualizando conforme o estado
  /// do cache:
  ///
  /// - **Cache vazio (primeira vez)** — faz `refetch()` em **foreground**
  ///   e aguarda; retorna o arquivo recém-baixado (ou null se o
  ///   condutor não tem foto cadastrada).
  /// - **Cache válido (idade < TTL)** — retorna imediato, sem tocar
  ///   no backend.
  /// - **Cache velho (idade >= TTL)** — retorna o velho **agora** +
  ///   dispara `refetch()` em background (fire-and-forget) pra atualizar
  ///   pra próxima leitura. Assim a UI nunca fica "esperando" quando
  ///   já tem uma versão razoável mostrada.
  static Future<File?> obterCached() async {
    final file = await UsuarioFotoStorage.read();

    // Primeira vez sem cache — espera o download pra a UI já mostrar
    // a foto no primeiro render (senão o AppNavbar mostraria o ícone
    // fallback até o próximo abrir da tela).
    if (file == null) {
      final novo = await refetch();
      if (novo) return UsuarioFotoStorage.read();
      return null;
    }

    final age = await UsuarioFotoStorage.age();
    if (age > _ttl) {
      // Cache velho — não atrasa a UI, refetch em bg. Se veio versão
      // nova, aparece no próximo `_carregarFoto()` (próximo abrir da
      // tela) — a atual continua servindo até lá.
      // ignore: discarded_futures
      refetch();
    }
    return file;
  }

  /// Baixa a foto do backend agora. Retorna true se algo mudou
  /// (200 novo binário ou 204 apagou local); false se 304 (ficou igual)
  /// ou em qualquer falha silenciosa.
  ///
  /// Idempotente: pode ser chamado em paralelo — o `TokenStorage` +
  /// `_refreshTokens` do `ApiClient` já dedupam refresh.
  static Future<bool> refetch() async {
    try {
      final res = await _doFetch();
      switch (res.statusCode) {
        case 200:
          final etag = _extractEtag(res);
          final mime = res.headers['content-type'];
          await UsuarioFotoStorage.write(
            res.bodyBytes,
            etag: etag,
            mime: mime,
          );
          _log.info('foto atualizada (${res.bodyBytes.length} bytes)');
          return true;

        case 304:
          await UsuarioFotoStorage.touch();
          _log.info('foto sem mudança (304)');
          return false;

        case 204:
          await UsuarioFotoStorage.clear();
          _log.info('sem foto no backend — cache limpo');
          return true;

        case 401:
          // MSEC.4 — pode ser TOKEN_EXPIRED. Chama refresh, retenta 1x.
          _log.warn('401 na foto — tentando refresh do token');
          final ok = await ApiClient.refreshTokens();
          if (ok) {
            final res2 = await _doFetch();
            if (res2.statusCode == 200) {
              final etag2 = _extractEtag(res2);
              final mime2 = res2.headers['content-type'];
              await UsuarioFotoStorage.write(
                res2.bodyBytes,
                etag: etag2,
                mime: mime2,
              );
              return true;
            }
          }
          return false;

        default:
          _log.warn('foto retornou ${res.statusCode}');
          return false;
      }
    } catch (e) {
      // Sem rede? Cache antigo continua servindo — sem barulho.
      _log.warn('refetch falhou: $e');
      return false;
    }
  }

  static Future<http.Response> _doFetch() async {
    final token = await TokenStorage.readAccess();
    final etag = await UsuarioFotoStorage.etag();

    final uri = Uri.parse(
      '${ApiClient.baseUrl.replaceAll(RegExp(r'/+$'), '')}'
      '/transporte/api/bdt/usuario/foto',
    );

    return http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
            if (etag != null && etag.isNotEmpty) 'If-None-Match': etag,
          },
          body: '{}',
        )
        .timeout(const Duration(seconds: 10));
  }

  static String? _extractEtag(http.Response res) {
    // http headers são case-insensitive mas o pacote dart:http normaliza
    // pra lowercase.
    final v = res.headers['etag'];
    return (v != null && v.isNotEmpty) ? v : null;
  }
}
