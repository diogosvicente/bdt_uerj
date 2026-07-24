import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'foto_documento_thumb.dart';

/// Sprint 18 W+M — seção "Fotos" reusável pras sheets do BDT.
///
/// Usada por Abastecimento (5 subtipos + Nota Fiscal em destaque) e
/// Manutenção (2 fases: Antes / Depois). Também poderia ser plugada
/// em Ocorrência no futuro, se quiser padronização visual total.
///
/// # Design
///
/// - **Botoeira por tipo** (recomendação aprovada pelo Diogo): cada
///   chip abre camera/galeria já com o tipo pré-selecionado. Reduz
///   erro humano ("qual foto era pra ser essa mesmo?") sem exigir
///   classificação depois.
/// - **Chip de destaque** opcional (ex.: Nota Fiscal) — botão maior,
///   destacado visualmente, semanticamente crítico.
/// - **Miniaturas com badge do tipo**: existentes (bytes via fetcher
///   do servidor) e pendentes (bytes do arquivo local) num único grid
///   pra o condutor ter noção total do estado antes de salvar.
///
/// # Contrato com o caller
///
/// - Estado das listas ([pendentes], [existentes]) vive no CALLSITE
///   — este widget é stateless. Isso permite que o botão "Salvar" do
///   form leia as `pendentes` pra fazer upload em sequência.
/// - Callbacks: [onAdicionar] recebe o chip escolhido e é responsável
///   por abrir camera/galeria, gerar o [FotoPendente] e chamar setState;
///   [onRemoverPendente] / [onExcluirExistente] fazem o mesmo caminho
///   inverso.
class FotosBdtSection extends StatelessWidget {
  final String titulo;

  /// Chips normais (Odômetro, Bomba, Antes, Depois…).
  final List<FotoTipoChip> chips;

  /// Chip destacado (opcional). Ex.: Nota Fiscal do Abastecimento.
  final FotoTipoChip? chipDestaque;

  /// Fotos escolhidas em memória (ainda não subidas).
  final List<FotoPendente> pendentes;

  /// Fotos já persistidas no backend (só em edição).
  final List<FotoExistente> existentes;

  /// Toca num chip → caller abre camera/galeria e adiciona à `pendentes`.
  final Future<void> Function(FotoTipoChip chip) onAdicionar;

  /// Remove uma foto pendente da lista (só limpa memória).
  final void Function(int index) onRemoverPendente;

  /// Exclui uma foto existente no backend + limpa cache.
  final Future<void> Function(FotoExistente foto) onExcluirExistente;

  final bool busy;

  const FotosBdtSection({
    super.key,
    required this.titulo,
    required this.chips,
    this.chipDestaque,
    required this.pendentes,
    required this.existentes,
    required this.onAdicionar,
    required this.onRemoverPendente,
    required this.onExcluirExistente,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in chips) _chipButton(context, c, destaque: false),
            if (chipDestaque != null)
              _chipButton(context, chipDestaque!, destaque: true),
          ],
        ),
        if (existentes.isEmpty && pendentes.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Nenhuma foto anexada.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ] else ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in existentes) _tileExistente(context, e),
              for (int i = 0; i < pendentes.length; i++)
                _tilePendente(context, pendentes[i], i),
            ],
          ),
        ],
      ],
    );
  }

  Widget _chipButton(BuildContext ctx, FotoTipoChip c, {required bool destaque}) {
    final onPressed = busy ? null : () => onAdicionar(c);
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(c.icone, size: 16),
        const SizedBox(width: 6),
        Text(c.label),
      ],
    );
    if (destaque) {
      return FilledButton(onPressed: onPressed, child: label);
    }
    return OutlinedButton(onPressed: onPressed, child: label);
  }

  Widget _tilePendente(BuildContext ctx, FotoPendente p, int index) {
    return _tileWrapper(
      preview: _PendentePreview(file: p.file),
      badge: p.tipo.label,
      badgeColor: p.tipo.isNotaFiscal
          ? Theme.of(ctx).colorScheme.primary
          : Colors.black87,
      onDelete: busy ? null : () => onRemoverPendente(index),
      deleteTooltip: 'Remover (ainda não enviada)',
    );
  }

  Widget _tileExistente(BuildContext ctx, FotoExistente e) {
    return _tileWrapper(
      preview: FotoDocumentoThumb(
        docId: e.docId,
        fetcher: e.fetcher,
        cacheNamespace: e.cacheNamespace,
        size: 88,
      ),
      badge: e.label,
      badgeColor: Colors.green.shade700,
      onDelete: busy ? null : () => onExcluirExistente(e),
      deleteTooltip: 'Excluir do servidor',
    );
  }

  Widget _tileWrapper({
    required Widget preview,
    required String badge,
    required Color badgeColor,
    required VoidCallback? onDelete,
    required String deleteTooltip,
  }) {
    return SizedBox(
      width: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: preview,
          ),
          // Badge do tipo no rodapé
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.85),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: Text(
                badge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 9,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          // Botão X no canto sup direito
          if (onDelete != null)
            Positioned(
              top: -8,
              right: -8,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 2,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onDelete,
                  child: Tooltip(
                    message: deleteTooltip,
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.close, size: 14),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Chip de tipo — clicar abre camera/galeria e adiciona uma foto do tipo.
class FotoTipoChip {
  /// Id do subtipo no catálogo do backend (ex: 1 = Odômetro). Nulo pra
  /// chips que não usam catálogo (ex: Nota Fiscal usa flag `isNotaFiscal`).
  final int? tipoId;

  /// Fase da manutenção — usado só nos chips de Manutenção. `antes|depois`.
  final String? fase;

  /// Marca este chip como "Nota Fiscal" (backend rota pra
  /// `salvarNotaFiscal`, gravando descricao fixa).
  final bool isNotaFiscal;

  final String label;
  final IconData icone;

  const FotoTipoChip({
    this.tipoId,
    this.fase,
    this.isNotaFiscal = false,
    required this.label,
    required this.icone,
  });
}

/// Foto ainda em memória (não subiu).
class FotoPendente {
  final XFile file;
  final FotoTipoChip tipo;
  const FotoPendente({required this.file, required this.tipo});
}

/// Foto já persistida no backend — a thumb baixa via fetcher.
class FotoExistente {
  final int docId;
  final String label;
  final Future<List<int>?> Function(int docId) fetcher;
  final String cacheNamespace;

  const FotoExistente({
    required this.docId,
    required this.label,
    required this.fetcher,
    required this.cacheNamespace,
  });
}

/// Preview de uma foto local (XFile) — usa FileImage no Android/iOS
/// e NetworkImage em web (path é URL blob).
class _PendentePreview extends StatelessWidget {
  final XFile file;
  const _PendentePreview({required this.file});

  @override
  Widget build(BuildContext context) {
    // Em Android/iOS, XFile.path é caminho de sistema — dá pra FileImage.
    // Em web, o path é URI blob:… — Image.network resolve.
    return SizedBox(
      width: 88,
      height: 88,
      child: Image(
        image: FileImage(File(file.path)),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: const Color(0xFFEEEEEE),
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image, color: Colors.black38),
        ),
      ),
    );
  }
}
