/// Helpers centralizados de formatação de data/hora.
///
/// Antes desses helpers, `_two(int)` / `_fmtDt(v)` / `_fmtTimeOnly(v)`
/// estavam duplicados em várias pages. Ver `docs/ARCHITECTURE.md` §4.11.
///
/// # Convenção de fuso (Sprint MSEC.TZ)
///
/// - Backend grava/emite datetimes em UTC no formato `Y-m-d H:i:s` (sem
///   sufixo Z, herdando o formato nu do MariaDB).
/// - Mobile envia datetimes em ISO UTC com `Z` explícito (via [apiIsoUtc]).
///   O backend aceita ambos os formatos (helper `api_parse_datetime_utc`).
/// - Todo helper de LEITURA aqui interpreta naive `Y-m-d H:i:s` como UTC
///   e converte pro fuso local do device (BRT) na exibição, garantindo
///   que "17:30 UTC" no banco apareça como "14:30" na tela do condutor.
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

  /// Sprint MSEC.TZ — Converte um `DateTime` (local ou UTC) para o formato
  /// ISO 8601 em UTC que a API mobile aceita, ex.: `2026-07-24T17:30:00Z`.
  ///
  ///     DateFmt.apiIsoUtc(DateTime.now()) // "2026-07-24T17:30:00Z"
  ///
  /// O sufixo `Z` sinaliza ao backend que o instante já é UTC — evitando
  /// a heurística de "assume BRT porque veio naive".
  static String apiIsoUtc(DateTime d) {
    final u = d.toUtc();
    return '${u.year}-${two(u.month)}-${two(u.day)}T'
        '${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
  }

  /// Parser interno: string vinda da API → DateTime NO FUSO LOCAL do device.
  ///
  /// Regras:
  ///  - `2026-07-24T17:30:00Z`         → UTC explicito → toLocal.
  ///  - `2026-07-24T17:30:00-03:00`    → offset explicito → toLocal.
  ///  - `2026-07-24 17:30:00` (naive)  → assume UTC (novo padrao MSEC.TZ)
  ///                                     e converte pro local.
  ///  - Formatos invalidos             → null.
  static DateTime? _parseApiAsLocal(String raw) {
    if (raw.isEmpty) return null;

    final hasTz = raw.endsWith('Z')
        || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);

    // Sem TZ: garante que o Dart parseie como UTC (default seria local do
    // device — o que interpretaria o valor gravado no MariaDB 3h errado).
    final normalized = hasTz
        ? raw.replaceFirst(' ', 'T')
        : '${raw.replaceFirst(' ', 'T')}Z';

    final dt = DateTime.tryParse(normalized);
    return dt?.toLocal();
  }

  /// Formata um valor cru vindo da API (string ISO ou "yyyy-MM-dd HH:mm:ss")
  /// como `dd/MM HH:MM` — versão compacta para listas.
  ///
  ///     DateFmt.dtCompact('2026-01-03T07:00:00Z') → "03/01 04:00"  (BRT)
  ///
  /// Devolve string vazia se o valor for null/vazio; devolve o próprio valor
  /// se não conseguir parsear (fallback seguro).
  static String dtCompact(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';
    final dt = _parseApiAsLocal(s);
    if (dt == null) return s;
    return '${two(dt.day)}/${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  /// Extrai só a hora `HH:MM` de um valor cru — no fuso local do device.
  ///
  ///     DateFmt.hora('2026-01-03 07:00:00') → "04:00"   (UTC → BRT)
  ///     DateFmt.hora('07:00')               → "07:00"   (ja e HH:MM)
  static String hora(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';

    if (RegExp(r'^\d{2}:\d{2}$').hasMatch(s)) return s;

    final dt = _parseApiAsLocal(s);
    if (dt != null) return '${two(dt.hour)}:${two(dt.minute)}';

    // fallback: tenta extrair HH:MM literal (sem conversao TZ)
    final m = RegExp(r'(\d{2}):(\d{2})').firstMatch(s);
    if (m != null) return '${m.group(1)}:${m.group(2)}';

    return s;
  }

  /// "2026-05-13 14:30:00" (UTC) → "13/05/2026 11:30" (BRT). Também aceita
  /// ISO com "T" ou "Z". Usada para exibir timestamps completos (ex.: marcos
  /// da jornada).
  static String dataHoraBr(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';
    final dt = _parseApiAsLocal(s);
    if (dt == null) return s;
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }
}
