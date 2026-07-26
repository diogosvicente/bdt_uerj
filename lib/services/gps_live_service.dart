import 'dart:async';

import '../utils/logger.dart';
import 'background_location_service.dart';
import 'bdt_service.dart';
import 'location_queue_db.dart';
import 'location_service.dart';

/// Tracking de GPS com **duplo motor**:
///
/// 1. **Timer no isolate principal** (igual à versão original deste app, que
///    comprovadamente funcionava): a cada N segundos pega a posição via
///    `LocationService.getLocPayload()` e chama `BdtService.enviarLocalizacao`.
///    Esse caminho garante envio enquanto o app está em foreground —
///    aproveita o `ApiClient` (com SSL bootstrap) e o token já em memória.
///
/// 2. **Foreground service Android** ([BackgroundLocationService]): rodado em
///    paralelo, é o que mantém o GPS coletando quando a tela é bloqueada ou
///    o usuário sai do app. Se ele falhar ao subir (versão do Android, plugin,
///    permissão), o tracking principal continua funcionando — não é
///    blocker.
class GpsLiveService {
  static Timer? _timer;
  // `_agendaId` é lido dentro do timer (linha 55). `_bdtId`/`_trechoId`
  // eram guardados pra debug mas nunca lidos — removidos. Se um dia
  // precisar (ex.: adicionar `status()` que reporta o BDT/trecho ativo),
  // basta ressuscitar aqui + no start/stop.
  static int? _agendaId;

  static const _log = Logger('GPS-LIVE');

  /// Fila compartilhada — usada como fallback quando o envio direto do
  /// timer falha (rede caída). O worker do `BackgroundLocationService`
  /// consome esta MESMA fila (mesmo arquivo SQLite), então o ponto que
  /// falhou aqui é reenviado automaticamente quando reconectar.
  static final LocationQueueDb _queue = LocationQueueDb();

  static Future<void> start({
    required int bdtId,
    int? agendaId,
    required int trechoId,
    Duration interval = const Duration(seconds: 5),
  }) async {
    // Garante estado limpo (cancela timer anterior, para service anterior).
    await stop();

    _agendaId = (agendaId != null && agendaId > 0) ? agendaId : null;

    _log.info('start bdt=$bdtId agenda=$_agendaId trecho=$trechoId interval=${interval.inSeconds}s');

    // 1) Timer no isolate principal — caminho confiável de envio.
    _timer = Timer.periodic(interval, (_) async {
      final loc = await LocationService.getLocPayload();
      if (loc == null) {
        _log.warn('LocationService retornou null (sem fix ou sem permissão)');
        return;
      }

      // Sprint 15 W+M (2026-07-26) — resiliência offline. Antes: se
      // `enviarLocalizacao` falhava (rede caída), o ponto era PERDIDO.
      // O único que sobrevivia era o BG service (que enfileira). Agora
      // enfileiramos aqui também quando falha — o worker do BG service
      // consome a mesma fila SQLite e reenviará quando reconectar.
      // O timer principal é preferido pra latência (envio direto), mas
      // NUNCA descarta silenciosamente.
      bool ok = false;
      try {
        ok = await BdtService.enviarLocalizacao(
          bdtId: bdtId,
          agendaId: _agendaId,
          trechoId: trechoId,
          loc: loc,
        );
      } catch (e) {
        _log.error('exceção no envio foreground', e);
      }

      if (ok) {
        _log.info(
          'envio foreground OK '
          'lat=${(loc["lat"] as num).toStringAsFixed(6)} '
          'lng=${(loc["lng"] as num).toStringAsFixed(6)}',
        );
      } else {
        // Falhou o envio direto — enfileira pra retry via worker BG.
        try {
          await _queue.enqueue(
            bdtId: bdtId,
            agendaId: _agendaId,
            trechoId: trechoId,
            payload: {
              'bdt_id': bdtId,
              if (_agendaId != null && _agendaId! > 0) 'agenda_id': _agendaId,
              'trecho_id': trechoId,
              'loc': loc,
            },
          );
          _log.warn(
            'envio foreground FALHOU → enfileirado pra retry '
            'lat=${(loc["lat"] as num).toStringAsFixed(6)} '
            'lng=${(loc["lng"] as num).toStringAsFixed(6)}',
          );
        } catch (e) {
          // Se nem enfileirar deu (disco cheio? SQLite corrompido?),
          // o ponto se perde — mas isso é MUITO raro e o log ajuda.
          _log.error('enqueue foreground FALHOU — ponto perdido', e);
        }
      }
    });

    // 2) Foreground service em paralelo — sobe a notificação persistente
    //    e mantém o GPS coletando mesmo com tela bloqueada / app em outra
    //    atividade. Se falhar, o tracking foreground continua funcionando.
    try {
      final started = await BackgroundLocationService.start(
        bdtId: bdtId,
        agendaId: agendaId,
        trechoId: trechoId,
        interval: interval,
      );
      _log.info('foreground service: ${started ? "iniciado" : "FALHOU iniciar"}');
    } catch (e) {
      _log.error('foreground service', e);
    }
  }

  static Future<void> stop() async {
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
      _log.info('timer foreground parado');
    }
    _agendaId = null;
    try {
      await BackgroundLocationService.stop();
    } catch (_) {
      // mesmo se falhar, segue
    }
  }

  /// Sprint 15 W+M (2026-07-26) — parada "com drain": para o timer/service
  /// e AGUARDA até `timeout` pra esvaziar a fila (worker do BG service
  /// drena a cada 30s; aqui a gente segura o fluxo pra confirmar antes de
  /// mostrar "trecho finalizado ok" pro condutor).
  ///
  /// Retorna quantos pontos SOBRARAM na fila (0 = drenou tudo).
  /// Chamador pode alertar "N pontos ainda serão enviados em background"
  /// se > 0.
  static Future<int> stopWithDrain({
    required int bdtId,
    required int trechoId,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // Para o timer imediatamente (não vamos capturar mais pontos).
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
      _log.info('timer foreground parado (drain start)');
    }

    // Espera até o timeout OU a fila zerar. O BG service ainda roda o
    // worker durante essa janela (drena a cada 30s por padrão, mas
    // acabou de rodar). Se a rede estiver de volta, tende a esvaziar
    // rápido; se não, ficam pra retry em background após stop.
    final deadline = DateTime.now().add(timeout);
    int pendentes = 0;
    while (DateTime.now().isBefore(deadline)) {
      pendentes = await _queue.countPendingFor(
        bdtId: bdtId,
        trechoId: trechoId,
      );
      if (pendentes == 0) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Agora sim, para o service (o worker do BG continuaria drenando).
    _agendaId = null;
    try {
      await BackgroundLocationService.stop();
    } catch (_) {}

    if (pendentes > 0) {
      _log.warn(
        'stopWithDrain: $pendentes ponto(s) restantes na fila para '
        'bdt=$bdtId trecho=$trechoId — serão reenviados em background',
      );
    } else {
      _log.info('stopWithDrain: fila zerada bdt=$bdtId trecho=$trechoId');
    }
    return pendentes;
  }

  static bool get isRunning => _timer != null;
}
