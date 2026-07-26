import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../utils/logger.dart';

/// Sprint 15 W+M (2026-07-26) — Cache local das flags de permissão que
/// o mobile usa pra mostrar/esconder opções (ex.: item "Criar BDT
/// direto" no bottom sheet da HomePage).
///
/// # Contrato
///
/// - `reload()` chama `POST bdt/permissoes-mobile` e persiste o JSON
///   no SharedPreferences sob a chave `permissoes_cache`. Chamado no
///   login e no reload da Home (é barato).
/// - `pode(chave)` lê SÓ o cache local. Retorna `false` por default
///   (comportamento seguro: sem cache → esconde a opção).
/// - `clear()` apaga o cache (chamado no logout).
///
/// # Por que cache local e não fetch síncrono?
///
/// A HomePage renderiza IMEDIATO ao abrir — se dependêssemos de um
/// fetch pra decidir se mostra a opção, teria um piscar. Cache-first
/// resolve. Reload roda em background e reflete no próximo build.
///
/// # Contrato com o backend
///
/// Chaves são `snake_case` iguais às do JSON do backend. Por enquanto
/// só uma:
///   - `criar_bdt_sem_solicitacao` — admin do módulo Transporte OU
///     papel `Criar BDT sem Solicitação`.
///
/// Novas chaves entram sem mudança neste service — o `Map<String,bool>`
/// aceita qualquer coisa; a UI que decide o que consultar.
class PermissoesService {
  static const _prefsKey = 'permissoes_cache';
  static final _log = Logger('PERMISSOES');

  /// Consulta O CACHE LOCAL. Nunca faz rede — sem cache = false.
  static Future<bool> pode(String chave) async {
    final map = await _lerCache();
    return map[chave] == true;
  }

  /// Todas as flags em cache (útil se a UI precisa consultar várias
  /// de uma vez — evita N idas ao SharedPreferences).
  static Future<Map<String, bool>> todas() async {
    return _lerCache();
  }

  /// Chama o backend e persiste. Idempotente e safe pra rodar em
  /// paralelo com outras chamadas (só grava se a resposta tiver
  /// success:true). Retorna as flags atualizadas OU o cache anterior
  /// em caso de falha (o app não pode ficar inutilizável se a
  /// conexão cair — as opções ficam com o último valor conhecido).
  static Future<Map<String, bool>> reload() async {
    try {
      final res = await ApiClient.post(
        'transporte/api/bdt/permissoes-mobile',
        const {},
      );
      if (res['success'] != true) {
        _log.warn('reload FALHOU: ${res['message']}');
        return _lerCache();
      }
      final data = res['data'];
      if (data is! Map) return _lerCache();

      final map = <String, bool>{};
      for (final e in data.entries) {
        map[e.key.toString()] = e.value == true;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(map));
      _log.info('reload ok: ${map.entries.map((e) => "${e.key}=${e.value}").join(", ")}');
      return map;
    } catch (e) {
      _log.warn('reload exception: $e — mantém cache anterior');
      return _lerCache();
    }
  }

  /// Apaga o cache. Chamado no logout — se a próxima pessoa a logar
  /// tem permissões diferentes, o cache do anterior não pode vazar.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static Future<Map<String, bool>> _lerCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, bool>{};
      for (final e in decoded.entries) {
        out[e.key.toString()] = e.value == true;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }
}
