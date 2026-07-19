/// Helpers centralizados de formatação de data/hora.
///
/// Antes desses helpers, `_two(int)` / `_fmtDt(v)` / `_fmtTimeOnly(v)`
/// estavam duplicados em várias pages. Ver `docs/ARCHITECTURE.md` §4.11.
class DateFmt {
  DateFmt._();

  /// Pad zero à esquerda em números 0-99.
  ///
  ///     DateFmt.two(3)  → "03"
  ///     DateFmt.two(15) → "15"
  static String two(int v) => v.toString().padLeft(2, '0');

  /// Formata `DateTime` como `dd/MM/yyyy` (padrão pt-BR de exibição).
  ///
  ///     DateFmt.dataBr(DateTime(2026, 7, 15)) → "15/07/2026"
  static String dataBr(DateTime d) =>
      '${two(d.day)}/${two(d.month)}/${d.year}';

  /// Formata `DateTime` como `yyyy-MM-dd` (padrão de payload da API).
  ///
  ///     DateFmt.apiDate(DateTime(2026, 7, 15)) → "2026-07-15"
  static String apiDate(DateTime d) =>
      '${d.year}-${two(d.month)}-${two(d.day)}';

  /// Formata um valor cru vindo da API (string ISO ou "yyyy-MM-dd HH:mm:ss")
  /// como `dd/MM HH:MM` — versão compacta para listas.
  ///
  ///     DateFmt.dtCompact('2026-01-03T07:00:00') → "03/01 07:00"
  ///
  /// Devolve string vazia se o valor for null/vazio; devolve o próprio valor
  /// se não conseguir parsear (fallback seguro).
  static String dtCompact(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';
    final dt = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (dt == null) return s;
    return '${two(dt.day)}/${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  /// Extrai só a hora `HH:MM` de um valor cru.
  ///
  ///     DateFmt.hora('2026-01-03 07:00:00') → "07:00"
  ///     DateFmt.hora('07:00')               → "07:00"
  static String hora(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';

    if (RegExp(r'^\d{2}:\d{2}$').hasMatch(s)) return s;

    final dt = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (dt != null) return '${two(dt.hour)}:${two(dt.minute)}';

    // fallback: tenta extrair HH:MM de "YYYY-MM-DD HH:MM:SS"
    final m = RegExp(r'(\d{2}):(\d{2})').firstMatch(s);
    if (m != null) return '${m.group(1)}:${m.group(2)}';

    return s;
  }

  /// "2026-05-13 14:30:00" → "13/05/2026 14:30". Também aceita ISO
  /// com "T". Usada para exibir timestamps completos (ex.: marcos da jornada).
  static String dataHoraBr(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';
    final dt = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (dt == null) return s;
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}
