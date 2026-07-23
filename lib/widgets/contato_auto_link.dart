import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Widget que renderiza um texto (`conteudo`) preservando quebras de
/// linha E transformando **telefones, WhatsApps, emails e URLs em
/// links clicáveis**.
///
/// Sprint W+M — antes o "Informações de segurança" mostrava o telefone
/// só como texto ("Ligue (21) 99999-9999"), o condutor precisava
/// copiar/discar. Agora o parser identifica os padrões e cada um vira
/// um chip com ação apropriada:
///   - `whatsapp: +5521999999999` ou "WhatsApp (21) 99999-9999" →
///     abre `https://wa.me/5521999999999` (WhatsApp trata via schema).
///   - Telefone `(DD) NNNNN-NNNN` / `(DD) NNNN-NNNN` → `tel:` (discador).
///   - `algo@dominio` → `mailto:`.
///   - `http(s)://…` → abre no navegador.
///
/// O parser é heurístico (regex sequencial). Trechos não reconhecidos
/// ficam como `Text` cru. Não é XSS-friendly porque nada é HTML — só
/// [TextSpan] + [InkWell].
class ContatoAutoLink extends StatelessWidget {
  final String texto;
  final TextStyle? style;

  const ContatoAutoLink({
    super.key,
    required this.texto,
    this.style,
  });

  /// WhatsApp: rótulo antes do número (case-insensitive) OU emoji 💬 no início.
  /// Ex.: "WhatsApp: (21) 99999-9999" / "Zap 21 99999-9999".
  static final _reWhats = RegExp(
    r'(?:whatsapp|whats\.?app|zap)[:\s\-]*(?:\+?55\s?)?(\(?\d{2}\)?[\s\-]?\d{4,5}[\s\-]?\d{4})',
    caseSensitive: false,
  );
  static final _reTel = RegExp(
    r'\(?\d{2}\)?[\s\-]?\d{4,5}[\s\-]?\d{4}',
  );
  static final _reEmail = RegExp(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
  );
  static final _reUrl = RegExp(
    r'https?://[^\s\)]+',
    caseSensitive: false,
  );

  Future<void> _open(BuildContext context, Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir: ${uri.toString()}')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao abrir: $e')),
      );
    }
  }

  /// Normaliza um telefone brasileiro em digits puros com DDI 55.
  /// "(21) 99999-9999" → "5521999999999". Retorna null se não faz sentido.
  static String? _digitsBr(String raw) {
    final only = raw.replaceAll(RegExp(r'\D'), '');
    if (only.length < 10 || only.length > 13) return null;
    // Se veio sem DDI (10 ou 11 dígitos), adiciona +55.
    if (only.length == 10 || only.length == 11) return '55$only';
    if (only.startsWith('55')) return only;
    return only;
  }

  @override
  Widget build(BuildContext context) {
    final base = style ?? const TextStyle(fontSize: 13, height: 1.4);
    final linkStyle = TextStyle(
      fontSize: base.fontSize,
      height: base.height,
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      fontWeight: FontWeight.w600,
    );

    // Concatena os spans varrendo o texto com múltiplas regex.
    // Ordem: WhatsApp > telefone > email > URL. Cada match consome
    // seu intervalo — o restante fica como texto simples.
    final spans = <InlineSpan>[];
    final segmentos = _tokenizar(texto);
    for (final seg in segmentos) {
      if (seg.tipo == _Tipo.texto) {
        spans.add(TextSpan(text: seg.raw, style: base));
        continue;
      }
      final label = seg.raw;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: InkWell(
          onTap: () {
            final uri = seg.uri;
            if (uri == null) return;
            _open(context, uri);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(seg.icone, size: 14, color: linkStyle.color),
                const SizedBox(width: 3),
                Text(label, style: linkStyle),
              ],
            ),
          ),
        ),
      ));
    }
    return SelectableText.rich(TextSpan(children: spans));
  }

  /// Quebra o texto em segmentos (raw + tipo + uri).
  /// Faz uma varredura por regex em cascata, priorizando WhatsApp > tel > email > url.
  List<_Segmento> _tokenizar(String texto) {
    final matches = <_Match>[];
    for (final m in _reWhats.allMatches(texto)) {
      matches.add(_Match(m.start, m.end, _Tipo.whatsapp, m.group(0)!, m.group(1)));
    }
    for (final m in _reTel.allMatches(texto)) {
      matches.add(_Match(m.start, m.end, _Tipo.tel, m.group(0)!, null));
    }
    for (final m in _reEmail.allMatches(texto)) {
      matches.add(_Match(m.start, m.end, _Tipo.email, m.group(0)!, null));
    }
    for (final m in _reUrl.allMatches(texto)) {
      matches.add(_Match(m.start, m.end, _Tipo.url, m.group(0)!, null));
    }
    // Ordena por posição; se overlap, mantém a MAIS ESPECÍFICA
    // (whatsapp > tel > email > url — respeita ordem de prioridade).
    matches.sort((a, b) {
      final c = a.start.compareTo(b.start);
      if (c != 0) return c;
      return a.tipo.index.compareTo(b.tipo.index);
    });
    final filtrados = <_Match>[];
    int cursor = 0;
    for (final m in matches) {
      if (m.start < cursor) continue; // overlap — pula o menos prioritário
      filtrados.add(m);
      cursor = m.end;
    }

    // Constrói segmentos: intercala texto solto com matches.
    final out = <_Segmento>[];
    int pos = 0;
    for (final m in filtrados) {
      if (m.start > pos) {
        out.add(_Segmento(_Tipo.texto, texto.substring(pos, m.start), null, Icons.circle));
      }
      Uri? uri;
      IconData icone = Icons.link;
      switch (m.tipo) {
        case _Tipo.whatsapp:
          final digits = _digitsBr(m.captura1 ?? '');
          if (digits != null) uri = Uri.parse('https://wa.me/$digits');
          icone = Icons.chat; // reserva o WhatsApp icon
          break;
        case _Tipo.tel:
          final digits = _digitsBr(m.raw);
          if (digits != null) uri = Uri.parse('tel:+$digits');
          icone = Icons.call;
          break;
        case _Tipo.email:
          uri = Uri.parse('mailto:${m.raw}');
          icone = Icons.mail_outline;
          break;
        case _Tipo.url:
          uri = Uri.tryParse(m.raw);
          icone = Icons.open_in_new;
          break;
        case _Tipo.texto:
          break;
      }
      out.add(_Segmento(m.tipo, m.raw, uri, icone));
      pos = m.end;
    }
    if (pos < texto.length) {
      out.add(_Segmento(_Tipo.texto, texto.substring(pos), null, Icons.circle));
    }
    return out;
  }
}

enum _Tipo { whatsapp, tel, email, url, texto }

class _Segmento {
  final _Tipo tipo;
  final String raw;
  final Uri? uri;
  final IconData icone;
  const _Segmento(this.tipo, this.raw, this.uri, this.icone);
}

class _Match {
  final int start;
  final int end;
  final _Tipo tipo;
  final String raw;
  final String? captura1;
  const _Match(this.start, this.end, this.tipo, this.raw, this.captura1);
}
