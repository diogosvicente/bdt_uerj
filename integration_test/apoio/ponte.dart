import 'dart:convert';
import 'dart:io';

/// A ponte com o testador de tela do e-prefeitura (`tests/e2e/lib/aplicativo.js`),
/// que roda no PC e sobe um servidorzinho HTTP enquanto o item roda.
///
/// No emulador, o PC é o `10.0.2.2`; o endereço vem do build:
///
///     --dart-define=E2E_PONTE=http://10.0.2.2:47053
///
/// Por ela o teste pega os parâmetros do item (o CPF e a senha do condutor de
/// teste, os BDTs da rodada), espera enquanto o painel está pausado, anda na
/// velocidade escolhida, pede ao PC as permissões do Android (o `pm grant`,
/// que o próprio aplicativo não pode dar a si) e devolve o que viu na tela.
class Ponte {
  static const String endereco = String.fromEnvironment('E2E_PONTE');

  static Future<Map<String, dynamic>> _pedir(
    String metodo,
    String caminho, [
    Map<String, dynamic>? corpo,
  ]) async {
    if (endereco.isEmpty) {
      throw StateError(
        'Sem a ponte com o testador: estes testes rodam pelo testador de tela '
        'do e-prefeitura (npm run teste), que passa --dart-define=E2E_PONTE.',
      );
    }
    final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await cliente.openUrl(metodo, Uri.parse('$endereco$caminho'));
      req.headers.contentType = ContentType.json;
      if (corpo != null) req.write(jsonEncode(corpo));
      final res = await req.close().timeout(const Duration(seconds: 90));
      final texto = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        throw StateError('A ponte respondeu ${res.statusCode} em $caminho: $texto');
      }
      if (texto.trim().isEmpty) return <String, dynamic>{};
      return Map<String, dynamic>.from(jsonDecode(texto) as Map);
    } finally {
      cliente.close(force: true);
    }
  }

  /// O que o item precisa: `cpf`, `senha` e `bdts` (letra → {id, titulo}).
  static Future<Map<String, dynamic>> parametros() => _pedir('GET', '/parametros');

  /// `{pausado: bool, devagar: ms}`, como o painel deixou.
  static Future<Map<String, dynamic>> controle() => _pedir('GET', '/controle');

  /// As permissões do Android que o aplicativo pede ao abrir (localização o
  /// tempo todo, notificação, sem otimização de bateria): sem elas, a janela
  /// do sistema cobre a tela, e o teste não a alcança.
  static Future<void> conceder() => _pedir('POST', '/conceder', const {});

  /// O que o teste viu (as horas na tela, por exemplo), para o testador
  /// conferir na folha e no PDF do BDT.
  static Future<void> resultado(Map<String, dynamic> r) => _pedir('POST', '/resultado', r);
}
