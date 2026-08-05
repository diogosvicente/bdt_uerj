/// Remoção de dados pessoais de qualquer payload que vá para log.
///
/// **Espelho Dart** de `app/Libraries/PiiSanitizer.php` do e-Prefeitura
/// (backend), criado na sprint 028 de segurança — item **A7-mobile**.
///
/// # Por que existe
///
/// O `api_client.dart` imprimia o corpo das requisições e respostas cru:
///
/// ```
/// 📦 Body: {cpf: 12192209738, senha: Teste@123456, ...}
/// ⬅️ Response 200: { "access_token": "7257322185f7...", ... }
/// ```
///
/// Ou seja: **CPF e senha em texto puro no logcat**, e os tokens junto. O
/// backend já tinha resolvido isso no `PiiSanitizer`/`BaseModel` (item A7),
/// mas o lado mobile tinha ficado de fora do plano.
///
/// O agravante é que `debugPrint` **não é removido em release** — o nome
/// engana. Ele se chama assim porque estrangula a taxa de saída para não
/// perder linhas, não porque só rode em debug. Um APK de produção no celular
/// do condutor gravava a senha dele a cada login.
///
/// # A política (idêntica ao backend)
///
/// - **redige** (`[REDACTED]`) credenciais: senha, token, etc. — o valor não
///   serve para nada no log;
/// - **mascara** (mantém só os 4 últimos caracteres) contato/identificação:
///   CPF, e-mail, telefone — o suficiente para conferir um registro sem
///   expor o dado.
///
/// Ao mexer aqui, mexa também no PHP: as duas listas são a MESMA política
/// (ARCHITECTURE.md §8 do e-Prefeitura). Divergir cria o pior dos mundos —
/// um campo protegido de um lado e vazando do outro.
library;

import 'dart:convert';

class PiiSanitizer {
  /// Credenciais: o valor não serve para nada no log.
  ///
  /// Idêntico a `PiiSanitizer::REDIGIR` no backend.
  static const Set<String> _redigir = {
    'senha',
    'password',
    'token',
    'access_token',
    'refresh_token',
    'csrf_token',
    'assinatura',
    'assinatura_svg',
  };

  /// Contato/identificação: mantém os 4 últimos caracteres.
  ///
  /// Idêntico a `PiiSanitizer::MASCARAR` no backend. Inclui os nomes REAIS
  /// das colunas (`email2`, `telefone1`, `telefone2`).
  static const Set<String> _mascarar = {
    'cpf',
    'email',
    'email2',
    'telefone',
    'telefone1',
    'telefone2',
    'celular',
    'matricula',
    'id_funcional',
  };

  /// Campos que só existem no tráfego do app — não estão no backend porque
  /// lá eles nunca chegam a um log.
  ///
  /// Não são PII; são substituídos por um resumo apenas para o log ficar
  /// legível. O `image_base64` do captcha, por exemplo, são ~400 caracteres
  /// que empurravam o resto da resposta para fora da tela.
  static const Set<String> _resumir = {
    'image_base64',
    'foto_base64',
    'raw',
  };

  /// Devolve uma cópia com os campos sensíveis tratados (recursivo).
  ///
  /// Nunca modifica a entrada — o chamador continua usando o dado real.
  static dynamic sanitize(dynamic dados) {
    if (dados is Map) {
      final saida = <String, dynamic>{};
      dados.forEach((chave, valor) {
        final nome = chave.toString().toLowerCase();

        if (_redigir.contains(nome)) {
          saida[chave.toString()] = '[REDACTED]';
        } else if (_mascarar.contains(nome)) {
          saida[chave.toString()] = mascarar(valor);
        } else if (_resumir.contains(nome)) {
          saida[chave.toString()] = '[${valor.toString().length} chars]';
        } else {
          saida[chave.toString()] = sanitize(valor);
        }
      });
      return saida;
    }

    if (dados is List) {
      return dados.map(sanitize).toList();
    }

    return dados;
  }

  /// Mantém apenas os 4 últimos caracteres.
  static String mascarar(dynamic valor) {
    final texto = valor?.toString() ?? '';
    if (texto.length <= 4) return '****';
    return '${'*' * (texto.length - 4)}${texto.substring(texto.length - 4)}';
  }

  /// Sanitiza uma resposta que ainda é texto.
  ///
  /// Tenta decodificar como JSON e aplicar [sanitize]. Quando não é JSON
  /// (tipicamente uma página de erro HTML do Apache), devolve só o começo:
  /// não dá para saber o que há ali dentro, então o seguro é truncar em vez
  /// de imprimir o corpo inteiro.
  static String sanitizeJson(String corpo) {
    if (corpo.isEmpty) return '(vazio)';

    try {
      final decodificado = jsonDecode(corpo);
      return const JsonEncoder.withIndent('  ').convert(sanitize(decodificado));
    } catch (_) {
      const limite = 200;
      if (corpo.length <= limite) return corpo;
      return '${corpo.substring(0, limite)}… (+${corpo.length - limite} chars)';
    }
  }
}
