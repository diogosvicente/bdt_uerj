// Os itens do aplicativo no roteiro de testes da 053 do e-prefeitura
// (docs/transporte/reuniao-2026-mes_10-dia_28/053-testes.md, lá no e-prefeitura):
// o S3, o B3, o H4, o H5 e o G7. Rodam no emulador, contra a cópia de teste do
// e-prefeitura, pelo testador de tela de lá (tests/e2e/lib/aplicativo.js), que
// sobe o emulador, passa os parâmetros pela ponte e depois confere na folha,
// no PDF e no banco o que o aplicativo gravou. O S3 (13/11/2026) é a parte da
// tela do item de segurança: a API recusando o BDT de outro condutor, o
// testador confere lá, com o token do mesmo login.
//
// Cada item roda sozinho, num `flutter test --plain-name "<item> ·"`, com o
// Motorista do aplicativo ([T-053]) e um BDT só dele, que o seeder da 053 cria
// de novo a cada rodada (as letras W, Y, Z e J do resumo do seeder).

import 'dart:io' show HttpClient;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';

import 'package:bdt_uerj/api/ssl_bootstrap.dart';
import 'package:bdt_uerj/main.dart' as app;
import 'package:bdt_uerj/services/permissoes_service.dart';
import 'package:bdt_uerj/services/token_storage.dart';
import 'package:bdt_uerj/services/usuario_foto_storage.dart';

import 'apoio/passos.dart';
import 'apoio/ponte.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('S3 · o login, os BDTs do dia e os passageiros abrem; o BDT de outro condutor não aparece', (t) async {
    final p = Passos(t);
    final par = await entrar(p);
    final bdts = Map<String, dynamic>.from(par['bdts'] as Map);
    final outro = par['outro'] as Map;

    // Os BDTs do dia: os quatro do Motorista do aplicativo, e nenhum de outro condutor.
    for (final b in bdts.values) {
      await p.esperar(find.text((b as Map)['titulo'] as String), oQue: 'o ${b['titulo']} nos BDTs do dia');
    }
    expect(find.text(outro['titulo'] as String), findsNothing,
        reason: 'o ${outro['titulo']}, do [T-053] Motorista, não pode aparecer nos BDTs do dia do Motorista do aplicativo');

    // Os passageiros do W abrem, sem marcar nada (o G7 é quem marca a presença).
    final w = bdts['W'] as Map;
    await abrirBdt(p, w['titulo'] as String);
    await p.tocar(find.text('Ações'));
    await p.tocar(find.text('Validar início'));
    await p.esperar(find.text('Passageiros previstos'));
    await p.esperar(find.text('0/2'), oQue: 'a contagem 0/2 dos passageiros');
    await p.esperar(find.text('[T-053] Passageira do aplicativo'));
    await p.esperar(find.text('[T-053] Passageiro do aplicativo'));

    await Ponte.resultado({
      'bdts': [for (final b in bdts.values) (b as Map)['titulo']],
      'passageiros': 2,
    });
  });

  testWidgets('B3 · o Encerrar do aplicativo encerra o BDT (C12)', (t) async {
    final p = Passos(t);
    final par = await entrar(p);
    final bdt = par['bdts']['Y'] as Map;

    await abrirBdt(p, bdt['titulo'] as String);
    await concluirViagem(p, comentario: '[T-053] o B3 encerra pelo aplicativo');

    await Ponte.resultado({'encerrado': bdt['id']});
  });

  testWidgets('H4 · a partida, a ocorrência e o abastecimento do aplicativo com a hora do relógio (D47)', (t) async {
    final p = Passos(t);
    final par = await entrar(p);
    final bdt = par['bdts']['Z'] as Map;

    await abrirBdt(p, bdt['titulo'] as String);

    // A partida, pela tela "Validar início" (o marco assinado): ela inicia o BDT.
    late String partida;
    final rPartida = await Relogio.medindo(() async {
      partida = await registrarPartida(p);
    });
    expect(rPartida.aceita(partida), isTrue,
        reason: 'a Partida diz $partida, e o relógio estava $rPartida');
    await p.voltar();

    await abrirFormulario(p);

    // A ocorrência: a hora é a do servidor, na hora de gravar.
    const tituloOc = '[T-053] ocorrência do aplicativo (H4)';
    final rOcorrencia = await Relogio.medindo(() async {
      await p.tocar(find.descendant(of: p.cartao('Ocorrências'), matching: find.text('Adicionar')),
          oQue: 'o Adicionar das Ocorrências');
      await escolherNaLista(p, find.byType(DropdownButtonFormField<int?>), oQue: 'o Tipo da ocorrência');
      await p.digitar(p.campo('Título *'), tituloOc);
      await p.tocar(p.botao('Registrar'), oQue: 'o Registrar da ocorrência');
      // A linha da lista, e não o texto solto (o campo da tela que fecha ainda o tem).
      await p.esperar(linhaDe(tituloOc), oQue: 'a ocorrência na lista');
    });
    final ocorrencia = p.dataHoraEm(linhaDe(tituloOc), oQue: 'a linha da ocorrência');
    expect(rOcorrencia.aceita(ocorrencia), isTrue,
        reason: 'a ocorrência diz $ocorrencia, e o relógio estava $rOcorrencia');

    // O abastecimento: a hora é a que o condutor escolhe (agora, nos dois seletores).
    final rAbastecimento = await Relogio.medindo(() async {
      await p.tocar(find.descendant(of: p.cartao('Abastecimentos'), matching: find.text('Adicionar')),
          oQue: 'o Adicionar dos Abastecimentos');
      await p.tocar(p.campo('Data/Hora *'));
      await p.tocar(find.text('OK'), oQue: 'o OK da data');
      await p.tocar(find.text('OK'), oQue: 'o OK da hora');
      await escolherNaLista(p, find.byType(DropdownButtonFormField<String>), oQue: 'o Tipo combustível');
      await p.digitar(p.campo('Litros *'), '31');
      await p.digitar(p.campo('Valor total *'), '186');
      await p.tocar(p.botao('Adicionar abastecimento'));
      await p.esperar(find.text('Abastecimento salvo.'), oQue: 'o aviso "Abastecimento salvo."');
    });
    final linhaAbast = linhaQueContem(RegExp(r'• 31(\.0+)? L •'));
    await p.esperar(linhaAbast, oQue: 'o abastecimento de 31 L na lista');
    final abastecimento = p.dataHoraEm(linhaAbast, oQue: 'a linha do abastecimento');
    expect(rAbastecimento.aceita(abastecimento), isTrue,
        reason: 'o abastecimento diz $abastecimento, e o relógio estava $rAbastecimento');

    await Ponte.resultado({
      'partida': partida,
      'ocorrencia': ocorrencia,
      'abastecimento': abastecimento,
    });
  });

  testWidgets('H5 · editar a manutenção e o abastecimento sem mexer na data não muda a hora', (t) async {
    final p = Passos(t);
    final par = await entrar(p);
    final bdt = par['bdts']['J'] as Map;
    final horaManutencao = par['horaManutencao'] as String;
    final horaAbastecimento = par['horaAbastecimento'] as String;

    await abrirBdt(p, bdt['titulo'] as String);
    await abrirFormulario(p);

    // A linha da lista, e não o texto solto: o `find.text` acha também o campo
    // do formulário que ainda está fechando, com o mesmo texto.
    const manutencao = '[T-053] manutenção para editar no aplicativo';
    final linhaManut = linhaDe(manutencao);
    final linhaAbast = linhaQueContem(RegExp(r'• 25(\.0+)? L •'));
    await p.esperar(linhaManut, oQue: 'a manutenção do H5 na lista');
    await p.esperar(linhaAbast, oQue: 'o abastecimento de 25 L do H5 na lista');
    final antesM = p.dataHoraEm(linhaManut, oQue: 'a linha da manutenção');
    final antesA = p.dataHoraEm(linhaAbast, oQue: 'a linha do abastecimento');
    expect(antesM.endsWith(horaManutencao), isTrue,
        reason: 'antes de editar, a manutenção diz $antesM, e a fixture é das $horaManutencao');
    expect(antesA.endsWith(horaAbastecimento), isTrue,
        reason: 'antes de editar, o abastecimento diz $antesA, e a fixture é das $horaAbastecimento');

    await p.tocar(find.descendant(of: linhaManut, matching: find.byTooltip('Editar')),
        oQue: 'o Editar da manutenção');
    await p.tocar(p.botao('Salvar alterações'), oQue: 'o Salvar alterações da manutenção');
    await p.esperar(find.text('Manutenção salva.'), oQue: 'o aviso "Manutenção salva."');
    await p.esperarSumir(p.botao('Salvar alterações'), oQue: 'o formulário da manutenção');

    await p.esperar(linhaAbast);
    await p.tocar(find.descendant(of: linhaAbast, matching: find.byTooltip('Editar')),
        oQue: 'o Editar do abastecimento');
    await p.tocar(p.botao('Salvar alterações'), oQue: 'o Salvar alterações do abastecimento');
    await p.esperar(find.text('Abastecimento salvo.'), oQue: 'o aviso "Abastecimento salvo."');
    await p.esperarSumir(p.botao('Salvar alterações'), oQue: 'o formulário do abastecimento');

    // De novo do servidor: sai do formulário e volta, como quem confere.
    await p.voltar();
    await abrirFormulario(p);
    await p.esperar(linhaManut, oQue: 'a manutenção do H5 na lista, de novo');
    await p.esperar(linhaAbast, oQue: 'o abastecimento do H5 na lista, de novo');
    final depoisM = p.dataHoraEm(linhaManut, oQue: 'a linha da manutenção');
    final depoisA = p.dataHoraEm(linhaAbast, oQue: 'a linha do abastecimento');
    expect(depoisM, antesM, reason: 'depois de salvar sem mexer, a manutenção diz $depoisM, e antes dizia $antesM');
    expect(depoisA, antesA, reason: 'depois de salvar sem mexer, o abastecimento diz $depoisA, e antes dizia $antesA');

    await Ponte.resultado({'manutencao': depoisM, 'abastecimento': depoisA});
  });

  testWidgets('G7 · o aplicativo do condutor: o login, os BDTs do dia, os passageiros e o encerrar', (t) async {
    final p = Passos(t);
    final par = await entrar(p);
    final bdts = Map<String, dynamic>.from(par['bdts'] as Map);
    final bdt = bdts['W'] as Map;

    // Os BDTs do dia: os quatro do Motorista do aplicativo.
    await p.esperar(find.text('BDTs do dia'), oQue: 'a lista "BDTs do dia"');
    for (final b in bdts.values) {
      await p.esperar(find.text((b as Map)['titulo'] as String), oQue: 'o ${b['titulo']} nos BDTs do dia');
    }

    await abrirBdt(p, bdt['titulo'] as String);

    // Os passageiros previstos: os dois da viagem, ninguém presente; a Passageira embarca.
    await p.tocar(find.text('Ações'));
    await p.tocar(find.text('Validar início'));
    await p.esperar(find.text('Passageiros previstos'));
    await p.esperar(find.text('0/2'), oQue: 'a contagem 0/2 dos passageiros');
    await p.esperar(find.text('[T-053] Passageiro do aplicativo'));
    await p.tocar(find.text('[T-053] Passageira do aplicativo'));
    await p.esperar(find.text('1/2'), oQue: 'a contagem 1/2 depois de marcar a Passageira');
    await p.tocar(p.botao('Salvar presenças'));
    await p.esperar(find.text('Presenças salvas.'), oQue: 'o aviso "Presenças salvas."');

    // A partida inicia o BDT (o Encerrar só aceita em andamento).
    final partida = await registrarPartida(p, jaNaValidacao: true);
    await p.voltar();

    await concluirViagem(p, comentario: '[T-053] o G7 do começo ao fim');

    await Ponte.resultado({'partida': partida, 'encerrado': bdt['id']});
  });
}

// ---------------------------------------------------------------------------
// O caminho de cada tela
// ---------------------------------------------------------------------------

/// Do zero: sem sessão guardada, as permissões dadas, o aplicativo aberto e o
/// login do Motorista do aplicativo. Devolve os parâmetros do item.
Future<Map<String, dynamic>> entrar(Passos p) async {
  p.anotar('pedindo os parâmetros e as permissões ao testador');
  final par = await Ponte.parametros();
  await Ponte.conceder();

  p.anotar('apagando a sessão guardada');
  await TokenStorage.clear();
  await PermissoesService.clear();
  await UsuarioFotoStorage.clear();
  await (await SharedPreferences.getInstance()).clear();

  // O cliente HTTP do aplicativo guarda a conexão ociosa por 15 s, e o Apache
  // do e-prefeitura local a fecha em 5 s (o KeepAliveTimeout): quem reaproveita
  // a conexão no instante em que o servidor a fecha recebe "Falha de
  // rede/HTTP.", ao acaso. No teste, o cliente larga a conexão em 3 s, antes do
  // servidor; o resto (o pin, os endereços, as chamadas) é o do aplicativo.
  SslBootstrap.setClientForTesting(IOClient(HttpClient()..idleTimeout = const Duration(seconds: 3)));

  p.anotar('abrindo o aplicativo');
  await app.main();
  p.anotar('esperando a tela de login');
  await p.esperar(find.text('Entrar'), oQue: 'a tela de login', prazo: const Duration(seconds: 90));
  await p.digitar(p.campo('CPF'), par['cpf'] as String);
  await p.digitar(p.campo('Senha'), par['senha'] as String);
  await p.tocar(p.botao('Entrar'));
  await p.esperar(find.text('BDTs do dia'), oQue: 'a Home com os BDTs do dia', prazo: const Duration(seconds: 60));
  return par;
}

Future<void> abrirBdt(Passos p, String titulo) async {
  await p.tocar(find.text(titulo), oQue: 'o $titulo nos BDTs do dia');
  await p.esperar(find.text('Ações'), oQue: 'a tela do BDT');
}

Future<void> abrirFormulario(Passos p) async {
  await p.tocar(find.text('Ações'));
  await p.tocar(find.text('Formulário'));
  await p.esperar(find.text('Formulário do BDT'));
  await p.esperar(find.text('Ocorrências'), oQue: 'o formulário carregado');
}

/// A Partida em "Validar início", com a assinatura. Devolve a data e a hora
/// que a tela mostra depois.
Future<String> registrarPartida(Passos p, {bool jaNaValidacao = false}) async {
  if (!jaNaValidacao) {
    await p.tocar(find.text('Ações'));
    await p.tocar(find.text('Validar início'));
  }
  await p.esperar(find.text('Passageiros previstos'), oQue: 'a tela "Validar início"');
  final linha = linhaDaPartida();
  await p.tocar(find.descendant(of: linha, matching: find.text('Registrar')), oQue: 'o Registrar da Partida');
  await p.assinar(find.byType(Signature));
  await p.tocar(p.botao('Confirmar assinatura'));
  await p.esperar(find.text('Marco registrado'), oQue: 'o aviso "Marco registrado"');
  await p.tocar(find.text('OK'));
  await p.esperar(find.descendant(of: linhaDaPartida(), matching: find.text('Refazer')),
      oQue: 'a Partida registrada (o botão vira "Refazer")');
  return p.dataHoraEm(linhaDaPartida(), oQue: 'a linha da Partida');
}

/// "Concluir viagem": a nota, o feedback salvo (o Encerrar pede) e o Encerrar.
Future<void> concluirViagem(Passos p, {required String comentario}) async {
  await p.tocar(find.text('Ações'));
  await p.tocar(find.text('Concluir viagem'));
  await p.esperar(find.text('Feedback do condutor'));
  await p.tocar(find.byIcon(Icons.star_border).last, oQue: 'a quinta estrela');
  await p.digitar(p.campo('Comentário (opcional)'), comentario);
  await p.tocar(p.botao('Salvar feedback'));
  await p.esperar(find.text('Feedback salvo.'), oQue: 'o aviso "Feedback salvo."');
  await p.esperar(find.text('Salvo'), oQue: 'o selo "Salvo" do feedback');
  await p.tocar(p.botao('Encerrar BDT'));
  await p.esperar(find.text('Encerrar BDT?'), oQue: 'a pergunta "Encerrar BDT?"');
  await p.tocar(find.widgetWithText(FilledButton, 'Encerrar'), oQue: 'o Encerrar da pergunta');
  await p.esperar(find.text('BDT encerrado'), oQue: 'o aviso "BDT encerrado"');
  await p.tocar(find.text('OK'));
  await p.esperarSumir(find.text('BDT encerrado'));
}

/// A linha (Row) da Partida em "Validar início": a do rótulo, do botão e da hora.
Finder linhaDaPartida() => find
    .ancestor(of: find.text('Partida'), matching: find.byType(Row))
    .first;

/// A linha da lista (ListTile) que tem o texto.
Finder linhaDe(String texto) =>
    find.ancestor(of: find.text(texto), matching: find.byType(ListTile)).first;

/// A linha da lista cujo título casa com a expressão.
Finder linhaQueContem(RegExp re) => find
    .ancestor(
      of: find.byWidgetPredicate((w) => w is Text && re.hasMatch(w.data ?? '')),
      matching: find.byType(ListTile),
    )
    .first;

/// Abre a lista suspensa e escolhe a primeira opção de verdade (não o
/// "Selecione…") no menu aberto. As opções do botão fechado também estão na
/// árvore (escondidas), por isso a busca é só dentro dos itens do menu.
Future<void> escolherNaLista(Passos p, Finder lista, {required String oQue}) async {
  await p.tocar(lista, oQue: oQue);
  final menu = find.byWidgetPredicate((w) => w.runtimeType.toString().startsWith('_DropdownMenuItemButton'));
  final opcoes = find.descendant(
    of: menu,
    matching: find.byWidgetPredicate((w) => w is DropdownMenuItem && w.value != null),
  );
  await p.esperar(opcoes, oQue: 'as opções de $oQue no menu');
  await p.tocar(opcoes.first, oQue: 'a primeira opção de $oQue');
  await p.esperarSumir(menu, oQue: 'o menu de $oQue');
}
