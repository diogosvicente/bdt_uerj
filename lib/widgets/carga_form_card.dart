import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/bdt_service.dart';
import '../services/ocorrencia_service.dart' show OcorrenciaFotoRef;
import 'foto_documento_thumb.dart';

/// Card "Vai levar carga?" — compartilhado entre o **Pré-BDT** e o
/// **BDT direto**.
///
/// Extraído do `PreBdtFormPage` (Sprint 11 W+M) em 2026-07-29, quando o BDT
/// direto passou a aceitar carga também. É uma extração de UI **pura**: as
/// regras seguem idênticas e o estado continua morando na Page, que é quem
/// valida e envia — este widget só desenha e avisa das interações.
///
/// Regras preservadas (mesmas do `folha.php` do web):
/// - Switch controla a exibição dos campos.
/// - Com carga ligada, **descrição** e **pelo menos 1 foto** são obrigatórias
///   (a validação em si é da Page; aqui os labels levam `*`).
/// - Peso e dimensões são opcionais, e aceitam vírgula como separador decimal.
///
/// Segue ARCHITECTURE §4.8: `StatelessWidget`, recebe dados prontos, não chama
/// Service para buscar estado (a única exceção é o `fetcher` das thumbs, que é
/// download binário sob demanda por `docId` — mesmo arranjo já usado no
/// Pré-BDT).
class CargaFormCard extends StatelessWidget {
  /// Switch ligado?
  final bool temCarga;
  final ValueChanged<bool> onTemCargaChanged;

  /// `false` enquanto o form está enviando — desabilita tudo.
  final bool enabled;

  /// Erro de nível de card (descrição vazia, nenhuma foto). Renderizado no
  /// padrão `errorContainer` da casa.
  final String? erro;

  final TextEditingController descCtrl;
  final TextEditingController pesoCtrl;
  final TextEditingController comprCtrl;
  final TextEditingController largCtrl;
  final TextEditingController altCtrl;

  /// Chamado a cada tecla na descrição — a Page usa pra limpar [erro].
  final VoidCallback onDescricaoChanged;

  /// Fotos escolhidas e ainda não enviadas.
  final List<XFile> fotosPendentes;

  /// Fotos já persistidas (só faz sentido em modo edição).
  final List<OcorrenciaFotoRef> fotosExistentes;

  final VoidCallback onAdicionarFoto;

  /// Índice em [fotosPendentes].
  final ValueChanged<int> onRemoverPendente;

  /// `docId` em [fotosExistentes].
  final ValueChanged<int> onRemoverExistente;

  const CargaFormCard({
    super.key,
    required this.temCarga,
    required this.onTemCargaChanged,
    required this.enabled,
    required this.descCtrl,
    required this.pesoCtrl,
    required this.comprCtrl,
    required this.largCtrl,
    required this.altCtrl,
    required this.onDescricaoChanged,
    required this.fotosPendentes,
    required this.onAdicionarFoto,
    required this.onRemoverPendente,
    required this.onRemoverExistente,
    this.erro,
    this.fotosExistentes = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: temCarga,
              onChanged: enabled ? onTemCargaChanged : null,
              title: const Text(
                'Vai levar carga?',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Materiais, equipamentos, animais, cargas de campo…',
                style: TextStyle(fontSize: 12),
              ),
            ),
            if (erro != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  erro!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (temCarga) ...[
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                enabled: enabled,
                maxLines: 3,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => onDescricaoChanged(),
                decoration: const InputDecoration(
                  labelText: 'Descrição da carga *',
                  helperText: 'Ex.: "5 caixas de material didático + notebook"',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _campoDecimal(
                      ctrl: pesoCtrl,
                      label: 'Peso (kg)',
                      helper: 'Opcional',
                      casas: 3,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _campoDecimal(
                      ctrl: comprCtrl,
                      label: 'Comp. (m)',
                      helper: ' ',
                      casas: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _campoDecimal(
                      ctrl: largCtrl,
                      label: 'Larg. (m)',
                      helper: 'Opcional',
                      casas: 2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _campoDecimal(
                      ctrl: altCtrl,
                      label: 'Alt. (m)',
                      helper: ' ',
                      casas: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _blocoFotos(),
            ],
          ],
        ),
      ),
    );
  }

  /// Campo numérico com vírgula OU ponto e limite de casas decimais.
  Widget _campoDecimal({
    required TextEditingController ctrl,
    required String label,
    required String helper,
    required int casas,
  }) {
    return TextField(
      controller: ctrl,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp('^\\d*[.,]?\\d{0,$casas}')),
      ],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        helperText: helper,
      ),
    );
  }

  Widget _blocoFotos() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Fotos da carga *',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: enabled ? onAdicionarFoto : null,
                icon: const Icon(Icons.add_a_photo, size: 18),
                label: const Text('Adicionar'),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Anexe pelo menos 1 foto — comprova a carga real embarcada.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Já persistidas (só em edição). Baixa pelo endpoint de CARGA.
              for (final f in fotosExistentes)
                _thumb(
                  child: FotoDocumentoThumb(
                    docId: f.id,
                    fetcher: BdtService.obterFotoCarga,
                    cacheNamespace: 'carga',
                    size: 84,
                  ),
                  onRemove: () => onRemoverExistente(f.id),
                ),
              // Pendentes (ainda não subiram).
              for (var i = 0; i < fotosPendentes.length; i++)
                _thumb(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(fotosPendentes[i].path),
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                    ),
                  ),
                  onRemove: () => onRemoverPendente(i),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumb({required Widget child, required VoidCallback onRemove}) {
    return Stack(
      children: [
        child,
        Positioned(
          right: 2,
          top: 2,
          child: InkWell(
            onTap: enabled ? onRemove : null,
            child: const CircleAvatar(
              radius: 12,
              backgroundColor: Colors.black54,
              child: Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
