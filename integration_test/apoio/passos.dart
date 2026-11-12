// O `print` aqui é o andamento do item: o testador de tela mostra a saída do
// `flutter test` aos poucos, no terminal e no painel.
// ignore_for_file: avoid_print

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter_test/flutter_test.dart';

import 'ponte.dart';

/// As ações do teste na tela, como uma pessoa faria: esperar aparecer, tocar,
/// digitar, assinar, voltar. Antes de cada ação, o portão do painel: se a
/// rodada estiver pausada, espera; se estiver devagar, espera o tempo pedido.
///
/// Nada de `pumpAndSettle`: o aplicativo tem indicadores de carregamento que
/// giram sem parar, e ele nunca "assenta". Cada espera é um laço de quadros
/// de 200 ms até o que se procura aparecer, com prazo.
class Passos {
  Passos(this.t);

  final WidgetTester t;

  static const _prazo = Duration(seconds: 45);
  static final _rotulos = Expando<String>('rótulo');

  /// O nome do que se procura, para o andamento e as falhas: o rótulo dado
  /// (o campo, o botão) ou o texto ("Ações"), em vez da descrição do finder.
  static String nomeDe(Finder f) {
    final r = _rotulos[f];
    if (r != null) return r;
    final d = f.describeMatch(Plurality.one);
    final m = RegExp(r'^widgets? with text "(.*)"$').firstMatch(d);
    return m != null ? '"${m.group(1)}"' : d.replaceFirst(RegExp(r'^widgets? with '), '');
  }

  /// Se o finder acha algo agora. O `.first` de um finder vazio lança, em vez
  /// de dizer "nada": enquanto a tela recarrega, isso é "ainda não".
  static bool _existe(Finder f) {
    try {
      return f.evaluate().isNotEmpty;
    } on StateError {
      return false;
    }
  }

  static Finder rotular(Finder f, String rotulo) {
    _rotulos[f] = rotulo;
    return f;
  }
  static final _dataHora = RegExp(r'\d{2}/\d{2}/\d{4} \d{2}:\d{2}');

  /// A pausa e a velocidade do painel, consultadas antes de cada ação.
  Future<void> _portao(String acao) async {
    print('  · $acao');
    var c = await Ponte.controle();
    var avisou = false;
    while (c['pausado'] == true) {
      if (!avisou) {
        print('  ⏸ pausado antes de: $acao');
        avisou = true;
      }
      await t.pump(const Duration(milliseconds: 500));
      c = await Ponte.controle();
    }
    if (avisou) print('  ▶ retomado');
    final devagar = (c['devagar'] as num?)?.toInt() ?? 0;
    if (devagar > 0) await espere(Duration(milliseconds: devagar));
  }

  /// Uma linha no andamento, sem esperar o portão (o que o teste está fazendo
  /// por dentro, entre as ações na tela).
  void anotar(String texto) => print('  · $texto');

  /// Espera o tempo, desenhando a tela.
  Future<void> espere(Duration d) async {
    final fim = DateTime.now().add(d);
    while (DateTime.now().isBefore(fim)) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// Os textos à vista agora (para a mensagem de quando algo não aparece).
  List<String> textosNaTela() => find
      .byType(Text)
      .evaluate()
      .map((e) {
        final w = e.widget as Text;
        return (w.data ?? w.textSpan?.toPlainText() ?? '').trim();
      })
      .where((s) => s.isNotEmpty)
      .toList();

  Future<Finder> esperar(Finder f, {String? oQue, Duration prazo = _prazo}) async {
    final fim = DateTime.now().add(prazo);
    while (!_existe(f)) {
      if (DateTime.now().isAfter(fim)) {
        throw TestFailure(
          'Não apareceu na tela: ${oQue ?? nomeDe(f)} '
          '(esperei ${prazo.inSeconds} s).\n'
          'Na tela: ${textosNaTela().take(60).join(' | ')}',
        );
      }
      await t.pump(const Duration(milliseconds: 200));
    }
    return f;
  }

  Future<void> esperarSumir(Finder f, {String? oQue, Duration prazo = _prazo}) async {
    final fim = DateTime.now().add(prazo);
    while (_existe(f)) {
      if (DateTime.now().isAfter(fim)) {
        throw TestFailure('Não saiu da tela: ${oQue ?? nomeDe(f)}.');
      }
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> tocar(Finder f, {String? oQue}) async {
    await esperar(f, oQue: oQue);
    await _portao('tocar em ${oQue ?? nomeDe(f)}');
    // O toque tem de chegar ao alvo. Se outra coisa está por cima (o teclado,
    // que encolhe a tela depois de digitar; uma animação que ainda não
    // acabou), fecha o teclado, rola de novo e espera; se não chegar, o teste
    // diz o que estava por cima, em vez de seguir achando que tocou.
    final alvo = f.first;
    late Offset centro;
    late HitTestResult caminho;
    var chega = false;
    for (var tentativa = 0; tentativa < 10 && !chega; tentativa++) {
      final foco = FocusManager.instance.primaryFocus;
      if (tentativa > 0 && foco != null && foco is! FocusScopeNode) foco.unfocus();
      await t.ensureVisible(alvo);
      await t.pump(const Duration(milliseconds: 300));
      centro = t.getCenter(alvo);
      caminho = HitTestResult();
      t.binding.hitTestInView(caminho, centro, t.view.viewId);
      chega = _alcanca(t.renderObject(alvo), centro, caminho);
    }
    if (!chega) {
      final tela = t.view.physicalSize / t.view.devicePixelRatio;
      final acerta = caminho.path
          .take(4)
          .map((e) => e.target is RenderObject
              ? ((e.target as RenderObject).debugCreator?.toString() ?? e.target.runtimeType.toString())
              : e.target.runtimeType.toString())
          .map((s) => s.length > 80 ? s.substring(0, 80) : s)
          .join(' < ');
      throw TestFailure('O toque em ${oQue ?? nomeDe(f)} (em $centro, alvo ${t.getRect(alvo)}, '
          'tela de ${tela.width.toStringAsFixed(0)}x${tela.height.toStringAsFixed(0)}) não chega a ele. '
          'O toque acerta: $acerta. Na tela: ${textosNaTela().take(30).join(' | ')}');
    }
    await t.tapAt(centro);
    await t.pump(const Duration(milliseconds: 300));
  }

  /// Se o toque no ponto [global] chega ao [alvo]:
  ///  - nenhuma área rolável em volta dele o corta naquele ponto (o caso do
  ///    teclado, que encolhe a tela e deixa o botão fora da área visível); e
  ///  - o que o toque acerta primeiro é o alvo, algo dentro dele, ou o que está
  ///    em volta dele (o espaço vazio de um item de menu, ao lado do texto), e
  ///    não outra coisa por cima (um aviso, a tela que ainda está fechando).
  static bool _alcanca(RenderObject alvo, Offset global, HitTestResult caminho) {
    for (RenderObject? r = alvo.parent; r != null; r = r.parent) {
      if (r is RenderBox && r is RenderAbstractViewport) {
        final local = r.globalToLocal(global);
        if (!(Offset.zero & r.size).contains(local)) return false;
      }
    }
    // (o primeiro objeto de pintura do caminho: antes dele pode vir um trecho de texto, o TextSpan)
    final primeiro = caminho.path.map((e) => e.target).whereType<RenderObject>().firstOrNull;
    return primeiro != null && (_descendeDe(primeiro, alvo) || _descendeDe(alvo, primeiro));
  }

  /// Se o objeto de pintura [filho] fica dentro de [pai].
  static bool _descendeDe(HitTestTarget filho, RenderObject pai) {
    if (filho is! RenderObject) return false;
    RenderObject? r = filho;
    while (r != null) {
      if (identical(r, pai)) return true;
      r = r.parent;
    }
    return false;
  }

  Future<void> digitar(Finder campo, String texto, {String? oQue}) async {
    await esperar(campo, oQue: oQue);
    await _portao('escrever "$texto" em ${oQue ?? nomeDe(campo)}');
    await t.ensureVisible(campo.first);
    await t.pump(const Duration(milliseconds: 200));
    await t.enterText(campo.first, texto);
    await t.pump(const Duration(milliseconds: 300));
  }

  /// O botão "voltar" do Android.
  Future<void> voltar() async {
    await _portao('voltar');
    await t.binding.handlePopRoute();
    await t.pump(const Duration(milliseconds: 600));
  }

  /// Uma assinatura de verdade, com o dedo: um zigue-zague na área.
  Future<void> assinar(Finder area) async {
    await esperar(area, oQue: 'a área da assinatura');
    await _portao('assinar');
    await t.ensureVisible(area.first);
    await t.pump(const Duration(milliseconds: 200));
    final centro = t.getCenter(area.first);
    final gesto = await t.startGesture(centro - const Offset(90, 0));
    for (var i = 1; i <= 18; i++) {
      await gesto.moveBy(Offset(10, i.isEven ? 14 : -14));
      await t.pump(const Duration(milliseconds: 16));
    }
    await gesto.up();
    await t.pump(const Duration(milliseconds: 300));
  }

  /// O campo de texto pelo rótulo (o `labelText`).
  Finder campo(String rotulo) => rotular(
        find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == rotulo),
        'o campo "$rotulo"',
      );

  /// O botão pelo texto, de qualquer tipo (o `find.text` acha o Text dentro).
  Finder botao(String texto) => rotular(
        find.ancestor(
          of: find.text(texto),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton || w is FloatingActionButton || w is IconButton),
        ),
        'o botão "$texto"',
      );

  /// O cartão (Card) que tem o título.
  Finder cartao(String titulo) =>
      find.ancestor(of: find.text(titulo), matching: find.byType(Card)).first;

  /// A data e a hora (DD/MM/AAAA HH:MM) escrita dentro de [onde].
  String dataHoraEm(Finder onde, {String? oQue}) {
    final achados = find
        .descendant(of: onde, matching: find.byType(Text))
        .evaluate()
        .map((e) {
          final w = e.widget as Text;
          return w.data ?? w.textSpan?.toPlainText() ?? '';
        })
        .map((s) => _dataHora.firstMatch(s)?.group(0))
        .whereType<String>()
        .toList();
    if (achados.isEmpty) {
      throw TestFailure('Sem data e hora em ${oQue ?? onde.describeMatch(Plurality.one)}.');
    }
    return achados.first;
  }
}

/// A hora certa: a do relógio, entre o minuto de antes da ação e o de depois
/// (com um minuto de folga de cada lado, como na web).
class Relogio {
  Relogio._(this.antes, this.depois);

  final DateTime antes;
  final DateTime depois;

  static Future<Relogio> medindo(Future<void> Function() acao) async {
    final antes = DateTime.now();
    await acao();
    return Relogio._(antes, DateTime.now());
  }

  /// "DD/MM/AAAA HH:MM" na hora do aparelho (o emulador fica em São Paulo).
  static DateTime lerBr(String s) {
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4}) (\d{2}):(\d{2})$').firstMatch(s.trim());
    if (m == null) throw TestFailure('"$s" não é DD/MM/AAAA HH:MM.');
    int n(int i) => int.parse(m.group(i)!);
    return DateTime(n(3), n(2), n(1), n(4), n(5));
  }

  bool aceita(String br) {
    final dt = lerBr(br);
    final de = DateTime(antes.year, antes.month, antes.day, antes.hour, antes.minute)
        .subtract(const Duration(minutes: 1));
    final ate = depois.add(const Duration(minutes: 1));
    return !dt.isBefore(de) && !dt.isAfter(ate);
  }

  @override
  String toString() => 'entre ${_br(antes)} e ${_br(depois)}';

  static String _br(DateTime d) {
    String dois(int v) => v.toString().padLeft(2, '0');
    return '${dois(d.day)}/${dois(d.month)}/${d.year} ${dois(d.hour)}:${dois(d.minute)}:${dois(d.second)}';
  }
}
