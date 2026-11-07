// A data que a edição manda de volta não pode adiantar 3 horas.
//
// Até a 1.0.1, o formulário de edição da manutenção e do abastecimento
// guardava a hora crua que vinha do servidor ("2026-11-06 17:30:00", em UTC e
// sem fuso) e a devolvia assim quando a pessoa não mexia na data. O servidor
// lê data sem fuso como hora de Brasília, e cada edição adiantava 3 horas.
// Agora o campo mostra a hora local, e o que vai para a API é o mesmo
// instante em UTC com o "Z" (`DateFmt.paraApiIsoUtc`).

import 'package:bdt_uerj/utils/date_fmt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DateFmt.paraApiIsoUtc', () {
    test('a hora sem fuso do servidor é UTC e volta com o Z', () {
      expect(DateFmt.paraApiIsoUtc('2026-11-06 17:30:00'), '2026-11-06T17:30:00Z');
      expect(DateFmt.paraApiIsoUtc('2026-11-06T17:30'), '2026-11-06T17:30:00Z');
    });

    test('o que já traz o fuso volta no mesmo instante, em UTC', () {
      expect(DateFmt.paraApiIsoUtc('2026-11-06T14:30:00-03:00'), '2026-11-06T17:30:00Z');
      expect(DateFmt.paraApiIsoUtc('2026-11-06T17:30:00Z'), '2026-11-06T17:30:00Z');
    });

    test('vazio e inválido dão null, e o formulário trata como sem data', () {
      expect(DateFmt.paraApiIsoUtc(null), isNull);
      expect(DateFmt.paraApiIsoUtc(''), isNull);
      expect(DateFmt.paraApiIsoUtc('amanhã'), isNull);
    });

    test('editar sem mexer na data devolve o mesmo instante', () {
      // O que o formulário guarda ao abrir e o que ele manda ao salvar.
      final aoAbrir = DateFmt.paraApiIsoUtc('2026-11-06 17:30:00')!;
      expect(DateFmt.paraApiIsoUtc(aoAbrir), aoAbrir);
      // E o campo mostra a hora do aparelho para esse instante, não a UTC.
      final local = DateTime.utc(2026, 11, 6, 17, 30).toLocal();
      expect(
        DateFmt.dataHoraBr(aoAbrir),
        '${DateFmt.two(local.day)}/${DateFmt.two(local.month)}/${local.year} '
        '${DateFmt.two(local.hour)}:${DateFmt.two(local.minute)}',
      );
    });
  });
}
