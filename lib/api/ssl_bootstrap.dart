import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Bootstrap de SSL + **certificate pinning** (MSEC.5) para
/// https://www.e-prefeitura.uerj.br.
///
/// # Parte 1: em quem o app confia
///
/// Em duas autoridades certificadoras, um arquivo para cada em
/// `assets/certs/` (a lista é [_pemAssets]):
///
///   - `rnp_icpedu_chain.pem`: RNP ICPEdu GR46 OV TLS CA 2025
///     (intermediária) e GlobalSign Root R46 (raiz, fallback para
///     Android <11, que não a traz). Assinava o certificado do servidor até
///     30/10/2026.
///   - `lets_encrypt_isrg.pem`: ISRG Root X1, ISRG Root X2 e a Root YR
///     assinada pela X1. Assina desde então; o cabeçalho do arquivo diz para
///     que serve cada uma.
///
/// Sem a cadeia do certificado que o servidor apresenta, o handshake falha
/// com `HandshakeException: CERTIFICATE_VERIFY_FAILED` e o app não fala com
/// o servidor.
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
/// confia **exclusivamente** nas cadeias de [_pemAssets]. A validação passa a
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
/// Da Let's Encrypt entram só as raízes: o certificado dela dura 90 dias, é
/// renovado a cada ~60, e a intermediária muda (YR1, YR2, YR3...).
///
/// ## Escape hatch
///
/// Se o servidor migrar para outra CA sem aviso, o app para de conectar
/// (fail-closed — é o comportamento correto para um pin). Foi o que
/// aconteceu em 30/10/2026 (abaixo). Para destravar sem esperar release
/// novo na loja, existe o dart-define:
///
///     flutter build apk --release --dart-define=SSL_PINNING=off
///
/// Por ser build-time, não há como um atacante desligar em runtime.
///
/// ## Quando o pin está ativo
///
/// Sempre. Desde 2026-07-31 o `ApiClient` aponta só para produção (HTTPS) —
/// os ambientes de dev por `--dart-define=APP_ENV=...` foram removidos.
/// Antes, `localhost`/`emulator`/`wsl` falavam HTTP puro e nem passavam por
/// `SecurityContext`; hoje toda requisição do app é validada contra as
/// cadeias pinadas.
///
/// Consequência prática: proxy de depuração (Charles, mitmproxy) **não**
/// funciona mais sem desligar o pin — use `--dart-define=SSL_PINNING=off`.
///
/// # Como atualizar o pin
///
/// Quando o servidor for trocar de autoridade certificadora:
///   1. veja a cadeia nova:
///      `openssl s_client -showcerts -connect www.e-prefeitura.uerj.br:443`
///   2. ponha a raiz nova num arquivo próprio em `assets/certs/`, e o
///      arquivo em [_pemAssets] e nos `assets` do `pubspec.yaml`. Mantenha os
///      antigos durante a transição: o contexto aceita vários;
///   3. publique a versão nova ANTES da virada do servidor.
///
/// Para conferir um arquivo contra o servidor sem rodar o app (só abre a
/// conexão TLS, não envia requisição):
///
///     openssl s_client -connect www.e-prefeitura.uerj.br:443 -servername www.e-prefeitura.uerj.br -CAfile <arquivo.pem>
///
/// "Verify return code: 0 (ok)" quer dizer que o pin aceita o servidor.
///
/// # O que aconteceu em 30/10/2026
///
/// Venceu o último certificado da RNP, e o servidor passou a usar um da
/// Let's Encrypt (emitido em 21/09/2026), sem aviso ao app. A 1.0.0, que só
/// confiava na RNP, recusava toda conexão no handshake: o login mostrava
/// "Falha de rede/HTTP.", como se faltasse internet. A 1.0.1 acrescentou o
/// `lets_encrypt_isrg.pem` e a mensagem própria de certificado recusado
/// (`ApiClient.mensagemFalhaTls`).
///
/// # Uso
///
/// - `await SslBootstrap.install()` em `main()` e no isolate do
///   foreground service, antes de qualquer rede.
/// - `SslBootstrap.client` no lugar de `http.post(...)` / `http.get(...)`.
class SslBootstrap {
  /// As cadeias em que o app confia, um arquivo por autoridade certificadora.
  static const List<String> _pemAssets = [
    'assets/certs/rnp_icpedu_chain.pem',
    'assets/certs/lets_encrypt_isrg.pem',
  ];

  /// `--dart-define=SSL_PINNING=off` desliga o pin (escape hatch de
  /// build; ver doc da classe).
  static const String _pinningFlag = String.fromEnvironment(
    'SSL_PINNING',
    defaultValue: 'on',
  );

  static bool _installed = false;

  /// Os arquivos de [_pemAssets], já lidos, na mesma ordem.
  static List<Uint8List>? _pems;
  static SecurityContext? _pinnedContext;
  static http.Client? _client;

  /// True quando o pin está ligado por configuração de build.
  /// Não diz se ele se aplica à requisição atual — isso depende do
  /// esquema da URL (ver [clientFor]).
  static bool get pinningEnabled => _pinningFlag != 'off';

  static Future<void> install() async {
    if (_installed) return;
    _installed = true;

    final pems = <Uint8List>[];
    for (final asset in _pemAssets) {
      final dados = await rootBundle.load(asset);
      pems.add(
        dados.buffer.asUint8List(dados.offsetInBytes, dados.lengthInBytes),
      );
    }
    _pems = pems;

    // Mantido: adiciona as CAs ao contexto default. Cobre qualquer código
    // que crie um HttpClient próprio sem passar pelo [client] daqui
    // (plugins, por exemplo) — sem isso, essas chamadas voltariam a
    // falhar com CERTIFICATE_VERIFY_FAILED. Um arquivo por vez, para que a
    // falha de um não impeça o outro.
    for (final pem in pems) {
      try {
        SecurityContext.defaultContext.setTrustedCertificatesBytes(pem);
      } on TlsException catch (e) {
        // "CERT_ALREADY_IN_HASH_TABLE" acontece em hot restart.
        // Qualquer outra falha é relevante, então relança.
        if (!e.toString().contains('CERT_ALREADY_IN_HASH_TABLE')) {
          rethrow;
        }
      }
    }
  }

  /// Contexto que confia SOMENTE nas cadeias de [_pemAssets].
  ///
  /// `withTrustedRoots: false` remove as CAs do sistema — é isso que
  /// transforma o contexto num pin. Retorna null se os arquivos ainda não
  /// foram carregados (`install()` não rodou) ou se o pin está desligado.
  static SecurityContext? get pinnedContext {
    if (!pinningEnabled) return null;
    final pems = _pems;
    if (pems == null) return null;

    final existing = _pinnedContext;
    if (existing != null) return existing;

    final ctx = SecurityContext(withTrustedRoots: false);
    for (final pem in pems) {
      ctx.setTrustedCertificatesBytes(pem);
    }
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
      // Se o pin ESTÁ ligado mas os arquivos ainda não carregaram,
      // `install()` não terminou. Devolvemos um client comum para não travar
      // a chamada, mas NÃO cacheamos — senão o app ficaria sem pin pelo
      // resto da sessão por causa de uma corrida na inicialização.
      if (pinningEnabled && _pems == null) {
        debugPrint('⚠️ SslBootstrap.client antes do install() — '
            'client sem pin (não cacheado)');
        return http.Client();
      }

      _client = http.Client();
      return _client!;
    }

    final inner = HttpClient(context: ctx)
      // Explícito por documentação: com `withTrustedRoots: false`, um
      // certificado fora das cadeias pinadas já é recusado pelo handshake.
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

  /// Só para os testes: o conteúdo dos arquivos que o [install] carregou,
  /// um item por arquivo de [_pemAssets].
  @visibleForTesting
  static List<Uint8List>? get pemCarregado => _pems;

  /// Só para os testes: troca o client compartilhado (por um `MockClient`,
  /// por exemplo). Com `null`, a próxima chamada a [client] monta o normal.
  @visibleForTesting
  static void setClientForTesting(http.Client? client) => _client = client;
}
