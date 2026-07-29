import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Bootstrap de SSL + **certificate pinning** (MSEC.5) para
/// https://www.e-prefeitura.uerj.br.
///
/// # Parte 1 — confiar na CA da RNP
///
/// O certificado do servidor é assinado pela "RNP ICPEdu GR46 OV TLS CA
/// 2025", que não está no truststore padrão do Android. Sem adicioná-la,
/// o app lança `HandshakeException: CERTIFICATE_VERIFY_FAILED`.
///
/// O bundle em `assets/certs/rnp_icpedu_chain.pem` contém:
///   - RNP ICPEdu GR46 OV TLS CA 2025 (intermediária)
///   - GlobalSign Root R46 (raiz — fallback para Android <11, que não a traz)
///
/// # Parte 2 — pinning (MSEC.5, 2026-07-28)
///
/// Antes desta sprint o app usava `SecurityContext.defaultContext`, que
/// **soma** a CA da RNP a todas as ~150 CAs do sistema. Na prática o app
/// aceitava qualquer certificado emitido por qualquer uma delas — um
/// proxy corporativo, ou uma CA comprometida, conseguiria interceptar o
/// tráfego (inclusive o Bearer token) numa rede pública.
///
/// A correção é criar um `SecurityContext(withTrustedRoots: false)` que
/// confia **exclusivamente** na cadeia da RNP. A validação passa a
/// acontecer no handshake TLS, ou seja, **antes de qualquer byte da
/// requisição sair do aparelho** — diferente de checar o certificado na
/// resposta, quando o dado já vazou.
///
/// ## Por que pinar a CADEIA e não o certificado folha
///
/// Pinar o certificado do servidor (ou o SPKI dele) quebraria o app a
/// cada renovação — certificados TLS duram ~1 ano e a chave costuma ser
/// trocada junto. Pinar a cadeia (intermediária + raiz) sobrevive à
/// renovação normal e ainda assim exclui as outras CAs do sistema, que
/// é de onde vem o risco real.
///
/// ## Escape hatch
///
/// Se a RNP migrar para outra CA sem aviso, o app para de conectar
/// (fail-closed — é o comportamento correto para um pin). Para destravar
/// sem esperar release novo na loja, existe o dart-define:
///
///     flutter build apk --release --dart-define=SSL_PINNING=off
///
/// Por ser build-time, não há como um atacante desligar em runtime.
///
/// ## Quando o pin está ativo
///
/// Só quando a base é a de **produção** (HTTPS). Ambientes de dev
/// (`--dart-define=APP_ENV=localhost|emulator|wsl`) falam HTTP puro, que
/// nem passa por `SecurityContext`, e proxies de debug continuam
/// funcionando.
///
/// # Como atualizar o pin
///
/// Quando a RNP anunciar troca de CA:
///   1. baixe a nova cadeia:
///      `openssl s_client -showcerts -connect www.e-prefeitura.uerj.br:443`
///   2. concatene intermediária + raiz em `assets/certs/rnp_icpedu_chain.pem`
///      (pode manter a cadeia antiga junto durante a transição — o
///      contexto aceita várias);
///   3. publique a versão nova ANTES da virada do servidor.
///
/// # Uso
///
/// - `await SslBootstrap.install()` em `main()` e no isolate do
///   foreground service, antes de qualquer rede.
/// - `SslBootstrap.client` no lugar de `http.post(...)` / `http.get(...)`.
class SslBootstrap {
  static const String _pemAsset = 'assets/certs/rnp_icpedu_chain.pem';

  /// `--dart-define=SSL_PINNING=off` desliga o pin (escape hatch de
  /// build; ver doc da classe).
  static const String _pinningFlag = String.fromEnvironment(
    'SSL_PINNING',
    defaultValue: 'on',
  );

  static bool _installed = false;
  static Uint8List? _pemBytes;
  static SecurityContext? _pinnedContext;
  static http.Client? _client;

  /// True quando o pin está ligado por configuração de build.
  /// Não diz se ele se aplica à requisição atual — isso depende do
  /// esquema da URL (ver [clientFor]).
  static bool get pinningEnabled => _pinningFlag != 'off';

  static Future<void> install() async {
    if (_installed) return;
    _installed = true;

    final pem = await rootBundle.load(_pemAsset);
    _pemBytes = pem.buffer.asUint8List();

    // Mantido: adiciona a CA ao contexto default. Cobre qualquer código
    // que crie um HttpClient próprio sem passar pelo [client] daqui
    // (plugins, por exemplo) — sem isso, essas chamadas voltariam a
    // falhar com CERTIFICATE_VERIFY_FAILED.
    try {
      SecurityContext.defaultContext.setTrustedCertificatesBytes(_pemBytes!);
    } on TlsException catch (e) {
      // "CERT_ALREADY_IN_HASH_TABLE" acontece em hot restart.
      // Qualquer outra falha é relevante, então relança.
      if (!e.toString().contains('CERT_ALREADY_IN_HASH_TABLE')) {
        rethrow;
      }
    }
  }

  /// Contexto que confia SOMENTE na cadeia da RNP.
  ///
  /// `withTrustedRoots: false` remove as CAs do sistema — é isso que
  /// transforma o contexto num pin. Retorna null se o bundle ainda não
  /// foi carregado (`install()` não rodou) ou se o pin está desligado.
  static SecurityContext? get pinnedContext {
    if (!pinningEnabled) return null;
    final bytes = _pemBytes;
    if (bytes == null) return null;

    final existing = _pinnedContext;
    if (existing != null) return existing;

    final ctx = SecurityContext(withTrustedRoots: false);
    ctx.setTrustedCertificatesBytes(bytes);
    _pinnedContext = ctx;
    return ctx;
  }

  /// Client HTTP compartilhado. Usa o contexto pinado quando disponível;
  /// cai no client padrão (dev sobre HTTP, ou pin desligado) caso
  /// contrário.
  ///
  /// É um singleton de propósito: reaproveitar a conexão evita refazer o
  /// handshake TLS a cada ponto de GPS enviado.
  static http.Client get client {
    final existing = _client;
    if (existing != null) return existing;

    final ctx = pinnedContext;
    if (ctx == null) {
      // Se o pin ESTÁ ligado mas o bundle ainda não carregou, `install()`
      // não terminou. Devolvemos um client comum para não travar a
      // chamada, mas NÃO cacheamos — senão o app ficaria sem pin pelo
      // resto da sessão por causa de uma corrida na inicialização.
      if (pinningEnabled && _pemBytes == null) {
        debugPrint('⚠️ SslBootstrap.client antes do install() — '
            'client sem pin (não cacheado)');
        return http.Client();
      }

      _client = http.Client();
      return _client!;
    }

    final inner = HttpClient(context: ctx)
      // Explícito por documentação: com `withTrustedRoots: false`, um
      // certificado fora da cadeia da RNP já é recusado pelo handshake.
      // Este callback só seria chamado nesse caso — e recusamos de novo.
      // Um `return true` aqui anularia o pin inteiro.
      ..badCertificateCallback = (cert, host, port) {
        debugPrint('🔒 pin rejeitou certificado de $host:$port '
            '(issuer=${cert.issuer})');
        return false;
      };

    _client = IOClient(inner);
    return _client!;
  }

  /// Fecha o client (libera conexões). Útil ao encerrar o isolate do
  /// foreground service.
  static void closeClient() {
    _client?.close();
    _client = null;
  }
}
