import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/bdt_km_estado.dart';
import '../models/bdt_resumo.dart';
import '../models/checkup_bdt.dart';
import '../models/feedback_condutor.dart';
import '../models/passageiro.dart';
import '../models/pre_bdt_pendente.dart';
import '../models/seguranca_texto.dart';
import 'foto_documento_client.dart';
import 'ocorrencia_service.dart'
    show OcorrenciaFotoRef; // shape {id, mimeType, createdAt} reusada
import '../models/veiculo.dart';
import '../utils/logger.dart';
import 'location_service.dart';

class BdtService {
  static const _log = Logger('BDT-SVC');

  static Future<int> _userId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('usuario_id') ?? 0;
  }

  /// Lista BDTs do dia
  static Future<List<BdtResumo>> listarDoDia({String? data}) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/dia", {
      if (data != null) "data": data,
      // ✅ backend já resolve via token, mas esse fallback ajuda enquanto você ajusta tudo
      "usuario_id": usuarioId,
    });

    if (res['success'] != true) return [];

    final list = (res['data'] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => BdtResumo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Detalhes completos do BDT.
  /// Sempre retorna Map (o ApiClient padroniza erros como Map com
  /// `success:false`).
  static Future<Map<String, dynamic>> detalhes(int bdtId) async {
    final usuarioId = await _userId();

    return await ApiClient.post("transporte/api/bdt/detalhes", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
    });
  }

  /// Inicia trecho (agendaId opcional => trecho extra).
  ///
  /// Sprint M4 (patch) — [kmInicial] é opcional. Se != null e o BDT
  /// ainda não tinha KM inicial, o backend salva. Se == null, nada
  /// acontece com a KM (não sobrescreve). Independente disso, o backend
  /// AUTO-ABRE o BDT se estava `EM_ABERTO` — o condutor não fica preso
  /// porque esqueceu de "iniciar BDT" antes (mesma regra do web).
  static Future<bool> iniciarTrecho({
    required int bdtId,
    int? agendaId,
    required int trechoId,
    double? kmInicial,
  }) async {
    final usuarioId = await _userId();

    final loc = await LocationService.getLocPayload();

    final payload = <String, dynamic>{
      "bdt_id": bdtId,
      "trecho_id": trechoId,
      "usuario_id": usuarioId,
      if (agendaId != null && agendaId > 0) "agenda_id": agendaId,
      if (loc != null) "loc": loc,
      if (kmInicial != null && kmInicial > 0) "km_inicial": kmInicial,
    };

    final res = await ApiClient.post(
      "transporte/api/bdt/trecho/iniciar",
      payload,
    );
    return res["success"] == true;
  }

  /// Sprint M4 (patch) — consulta rápida do estado da KM do BDT.
  /// Retorna null em falha de rede (o app deve tratar como "não sei",
  /// e nesse caso melhor pular o dialog para não bloquear o condutor).
  static Future<BdtKmEstado?> obterEstadoKm(int bdtId) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post('transporte/api/bdt/km/estado', {
      'usuario_id': usuarioId,
      'bdt_id': bdtId,
    });
    if (res['success'] != true) {
      _log.warn('obterEstadoKm#$bdtId FALHOU: ${res['message']}');
      return null;
    }
    final data = res['data'];
    if (data is! Map) return null;
    return BdtKmEstado.fromJson(Map<String, dynamic>.from(data));
  }

  /// Sprint W+M (Sprint 15 web) — checkup INFORMATIVO do BDT.
  /// Mesma lógica de `BdtSemSolicitacaoService::checkup()` do web —
  /// veículo em manutenção, veículo inativo, CNH vencida.
  ///
  /// NÃO bloqueia: o app só usa os avisos pra mostrar um banner amarelo
  /// no topo do BDT. Retorna `null` em falha de rede (banner some).
  static Future<CheckupBdt?> checkup(int bdtId) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post('transporte/api/bdt/checkup', {
      'usuario_id': usuarioId,
      'bdt_id': bdtId,
    });
    if (res['success'] != true) {
      _log.warn('checkup#$bdtId FALHOU: ${res['message']}');
      return null;
    }
    final data = res['data'];
    if (data is! Map) return null;
    return CheckupBdt.fromJson(Map<String, dynamic>.from(data));
  }

  /// Sprint M6 (Web+Mobile / Sprint 1 web) — textos institucionais de
  /// segurança exibidos no dialog do BDT. Fonte: `SegurancaTextoService`
  /// do web — mesma que alimenta o modal web `_modal_seguranca.php`.
  /// Editável pelo admin sem redeploy.
  ///
  /// Retorna lista vazia em qualquer falha — o dialog trata como "não
  /// há informações cadastradas" (mesmo fallback do modal web).
  static Future<List<SegurancaTexto>> listarSegurancaTextos() async {
    final usuarioId = await _userId();
    final res = await ApiClient.post(
      'transporte/api/bdt/seguranca/textos',
      {'usuario_id': usuarioId},
    );
    if (res['success'] != true) {
      _log.warn('listarSegurancaTextos FALHOU: ${res['message']}');
      return const [];
    }
    final list = (res['data'] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => SegurancaTexto.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Finaliza trecho (envia loc junto se tiver)
  static Future<bool> finalizarTrecho({
    required int bdtId,
    required int trechoId,
  }) async {
    final usuarioId = await _userId();

    final loc = await LocationService.getLocPayload();

    final payload = <String, dynamic>{
      "bdt_id": bdtId,
      "trecho_id": trechoId,
      "usuario_id": usuarioId,
      if (loc != null) "loc": loc,
    };

    final res = await ApiClient.post(
      "transporte/api/bdt/trecho/finalizar",
      payload,
    );
    return res["success"] == true;
  }

  /// Envia 1 ponto de localização (tracking)
  static Future<bool> enviarLocalizacao({
    required int bdtId,
    int? agendaId,
    int? trechoId,
    Map<String, dynamic>? loc, // se vier null, ele tenta pegar do GPS agora
  }) async {
    final usuarioId = await _userId();

    final Map<String, dynamic>? resolvedLoc =
        loc ?? await LocationService.getLocPayload();
    if (resolvedLoc == null) {
      _log.warn('enviarLocalizacao: SEM POSIÇÃO (loc=null)');
      return false;
    }

    if (usuarioId <= 0) {
      _log.warn('enviarLocalizacao: usuario_id inválido ($usuarioId) — sem login?');
    }

    final payload = <String, dynamic>{
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      if (agendaId != null) "agenda_id": agendaId,
      if (trechoId != null) "trecho_id": trechoId,
      "loc": resolvedLoc,
    };

    final res = await ApiClient.post("transporte/api/bdt/localizacao", payload);
    final ok = res["success"] == true;
    final httpStatus = res["http_status"];
    final msg = res["message"] ?? res["status"];
    _log.info(
      'enviarLocalizacao: ${ok ? "OK" : "FALHA"} '
      'http=$httpStatus bdt=$bdtId trecho=$trechoId msg=$msg',
    );
    return ok;
  }

  // ==========================================================
  // MARCOS DA JORNADA (substitui o antigo bdt/salvar)
  // Marcos válidos no backend: partida | apresentacao | embarque_passageiro
  // ==========================================================

  /// Marcos válidos aceitos pelo backend (BdtJornadaService::ORDEM).
  /// Ordem cronológica — o backend recusa registro fora de ordem.
  static const List<String> marcosValidos = <String>[
    "partida",
    "apresentacao",
    "embarque_passageiro",
    // Sprint 5 W+M — 4º marco: saída efetiva do veículo (após embarque).
    "hora_saida",
  ];

  /// Registra um marco da jornada. O backend grava origem="mobile"
  /// automaticamente — não enviar campo "origem".
  static Future<Map<String, dynamic>> registrarMarcoJornada({
    required int bdtId,
    required String marco,
    String? observacao,
  }) async {
    final usuarioId = await _userId();

    final payload = <String, dynamic>{
      "bdt_id": bdtId,
      "marco": marco,
      "usuario_id": usuarioId,
      if (observacao != null && observacao.trim().isNotEmpty)
        "observacao": observacao.trim(),
    };

    final res = await ApiClient.post(
      "transporte/api/bdt/jornada/marco",
      payload,
    );

    return Map<String, dynamic>.from(res);
  }

  /// Retorna o estado dos três marcos + histórico de assinaturas.
  /// Estrutura esperada:
  ///   {
  ///     "marcos": {
  ///       "partida":             {"datahora": "...", "assinatura": {...} | null},
  ///       "apresentacao":        {"datahora": "...", "assinatura": {...} | null},
  ///       "embarque_passageiro": {"datahora": "...", "assinatura": {...} | null}
  ///     },
  ///     "historico": [...]
  ///   }
  static Future<Map<String, dynamic>?> estadoJornada(int bdtId) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/jornada/estado", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
    });

    if (res["success"] != true) return null;
    return res;
  }

  // =========================
  // TRECHOS (CRUD)
  // =========================

  static Future<bool> criarTrechoExtra({
    required int bdtId,
    required String origem,
    required String destino,
    int? agendaId, // opcional (ignorado pelo backend refatorado)
    // Refino trecho extra (2026-07-21): campos opcionais que trazem
    // paridade com o form web (folha.php). O backend recém-refatorado
    // é um wrapper de BdtViagemService::adicionarTrechoAvulso, que
    // aceita hora_saida/hora_chegada em "HH:MM" e obs texto livre.
    String? horaSaida,
    String? horaChegada,
    String? obs,
  }) async {
    final usuarioId = await _userId();

    // Rota canônica do backend atual: transporte/api/bdt/trechos/create
    final res = await ApiClient.post("transporte/api/bdt/trechos/create", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      "fk_agenda": agendaId, // null => extra
      "origem": origem,
      "destino": destino,
      if (horaSaida != null && horaSaida.trim().isNotEmpty)
        "hora_saida": horaSaida.trim(),
      if (horaChegada != null && horaChegada.trim().isNotEmpty)
        "hora_chegada": horaChegada.trim(),
      if (obs != null && obs.trim().isNotEmpty) "obs": obs.trim(),
    });

    return res["success"] == true;
  }

  static Future<bool> atualizarTrecho({
    required int bdtId,
    required int trechoId,
    required String origem,
    required String destino,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/trechos/update", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      "trecho_id": trechoId,
      "origem": origem,
      "destino": destino,
    });

    return res["success"] == true;
  }

  static Future<bool> atualizarTrechoExecucao({
    required int bdtId,
    required int trechoId,
    required Map<String, dynamic> data,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post(
      "transporte/api/bdt/trecho/execucao/update",
      {
        "bdt_id": bdtId,
        "trecho_id": trechoId,
        "usuario_id": usuarioId, // fallback (token ideal)
        ...data, // datahora_saida, odometro_saida, datahora_chegada, odometro_chegada
      },
    );

    return res["success"] == true;
  }

  static Future<bool> excluirTrecho({
    required int bdtId,
    required int trechoId,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/trechos/delete", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      "trecho_id": trechoId,
    });

    return res["success"] == true;
  }

  // =========================
  // ABASTECIMENTOS (CRUD)
  // =========================

  static Future<List<Map<String, dynamic>>> listarAbastecimentos({
    required int bdtId,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/abastecimentos/list", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
    });

    if (res["success"] != true) return [];
    final list = (res["data"] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Fallback local do vocabulário `App\Constants\CombustivelTipo` do web.
  /// Espelho manual (case-sensitive) que garante o dropdown NUNCA vazio
  /// se a rede/token falhar. Se o admin adicionar um tipo novo lá, ele só
  /// aparece quando a chamada online funciona — o offline mostra os 6
  /// canônicos, que cobrem 100% da frota atual.
  static const List<String> _tiposCombustivelFallback = [
    'Gasolina comum',
    'Gasolina aditivada',
    'Etanol',
    'Diesel S10',
    'Diesel S500',
    'GNV',
  ];

  /// Sprint W+M — vocabulário fechado do web (`App\Constants\CombustivelTipo`).
  /// Antes o mobile tinha ["gasolina", "etanol", …] (minúsculo) e o
  /// backend recusava com `in_list`. Agora buscamos do web pra manter
  /// sincronia (se o admin adicionar tipo novo, aparece sozinho).
  ///
  /// Retorna lista de strings — o próprio valor é o rótulo (a coluna
  /// no banco é `varchar` que grava o texto).
  ///
  /// Fallback: se a chamada falhar (rede, token expirado sem refresh,
  /// endpoint 500), devolve [_tiposCombustivelFallback] — nunca vazio.
  /// Assim o condutor consegue lançar abastecimento mesmo sem cobertura.
  static Future<List<String>> listarTiposCombustivel() async {
    final usuarioId = await _userId();
    final res = await ApiClient.post(
      "transporte/api/bdt/abastecimentos/tipos",
      {"usuario_id": usuarioId},
    );
    if (res['success'] != true) {
      _log.warn(
        'listarTiposCombustivel FALHOU (usando fallback local): '
        'http=${res['http_status']} status=${res['status']} '
        'msg=${res['message']}',
      );
      return _tiposCombustivelFallback;
    }
    final list = (res['data'] as List<dynamic>? ?? const []);
    final tipos = list
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList();
    // Backend pode responder success:true com data vazia (edge case);
    // ainda assim garante ao dropdown pelo menos os canônicos.
    return tipos.isEmpty ? _tiposCombustivelFallback : tipos;
  }

  /// Retorna o Map cru do backend — a UI extrai `success` + `message`
  /// pra mostrar erro específico. Antes era `Future<bool>` e o app
  /// só mostrava "Não foi possível salvar…" genérico.
  static Future<Map<String, dynamic>> criarAbastecimento({
    required int bdtId,
    required Map<String, dynamic> data,
  }) async {
    final usuarioId = await _userId();
    return ApiClient.post(
      "transporte/api/bdt/abastecimentos/create",
      {"bdt_id": bdtId, "usuario_id": usuarioId, ...data},
    );
  }

  /// Sprint MUX — Apólice + seguradora do veículo do BDT.
  ///
  /// Usado pelo modal "Informações de segurança" pra oferecer ao condutor
  /// os contatos da seguradora (ligar / WhatsApp / e-mail / site) em caso
  /// de sinistro. Retorna `null` se o BDT/veículo não tem apólice ativa,
  /// ou se a chamada falhou (sem fallback local — sem dados a mostrar,
  /// a UI simplesmente oculta a seção).
  static Future<Map<String, dynamic>?> getSeguroDoBdt(int bdtId) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post(
      "transporte/api/bdt/seguro",
      {"bdt_id": bdtId, "usuario_id": usuarioId},
    );
    if (res['success'] != true) {
      _log.warn(
        'getSeguroDoBdt#$bdtId FALHOU: '
        'http=${res['http_status']} status=${res['status']} '
        'msg=${res['message']}',
      );
      return null;
    }
    final data = res['data'];
    if (data is! Map) return null;
    return Map<String, dynamic>.from(data);
  }

  static Future<Map<String, dynamic>> atualizarAbastecimento({
    required int bdtId,
    required int abastecimentoId,
    required Map<String, dynamic> data,
  }) async {
    final usuarioId = await _userId();
    return ApiClient.post("transporte/api/bdt/abastecimentos/update", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      "abastecimento_id": abastecimentoId,
      ...data,
    });
  }

  static Future<bool> excluirAbastecimento({
    required int bdtId,
    required int abastecimentoId,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post(
      "transporte/api/bdt/abastecimentos/delete",
      {
        "bdt_id": bdtId,
        "usuario_id": usuarioId,
        "abastecimento_id": abastecimentoId,
      },
    );

    return res["success"] == true;
  }

  // =========================
  // MANUTENÇÕES (CRUD)
  // =========================

  static Future<List<Map<String, dynamic>>> listarManutencoes({
    required int bdtId,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/manutencoes/list", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
    });

    if (res["success"] != true) return [];
    final list = (res["data"] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Sprint 18 W+M — retorna o Map cru do backend (padrão de
  /// [criarAbastecimento]), pra caller ler `data.manutencao_id` e
  /// subir fotos em seguida. Antes retornava `bool`.
  static Future<Map<String, dynamic>> criarManutencao({
    required int bdtId,
    required Map<String, dynamic> data,
  }) async {
    final usuarioId = await _userId();
    return ApiClient.post("transporte/api/bdt/manutencoes/create", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      ...data,
    });
  }

  static Future<Map<String, dynamic>> atualizarManutencao({
    required int bdtId,
    required int manutencaoId,
    required Map<String, dynamic> data,
  }) async {
    final usuarioId = await _userId();
    return ApiClient.post("transporte/api/bdt/manutencoes/update", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      "manutencao_id": manutencaoId,
      ...data,
    });
  }

  static Future<bool> excluirManutencao({
    required int bdtId,
    required int manutencaoId,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/manutencoes/delete", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      "manutencao_id": manutencaoId,
    });

    return res["success"] == true;
  }

  static Future<bool> excluirTrechoExtra({
    required int bdtId,
    required int trechoId,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/trechos/delete", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      "trecho_id": trechoId,
    });

    return res["success"] == true;
  }

  // ==========================================================
  // Reabertura de BDT
  // Backend: POST transporte/api/bdt/reabrir
  // Regras:
  //   - Só BDTs com status Encerrado (3) ou Cancelado (4)
  //   - Justificativa obrigatória (mínimo 10 caracteres)
  //   - Origem gravada como "mobile" no histórico (o backend força)
  //
  // Retorna um Map com { "success": bool, "message": String?, payload... }
  // para que a UI mostre o motivo da falha (permissão, status inválido, etc).
  // ==========================================================
  static Future<Map<String, dynamic>> reabrirBdt({
    required int bdtId,
    required String justificativa,
  }) async {
    final usuarioId = await _userId();

    final res = await ApiClient.post("transporte/api/bdt/reabrir", {
      "bdt_id": bdtId,
      "usuario_id": usuarioId,
      "justificativa": justificativa.trim(),
    });
    // ApiClient já padroniza a resposta com success/message
    return Map<String, dynamic>.from(res);
  }

  // ==========================================================
  // Sprint M3 — Pré-BDT (condutor pré-cria um BDT via app)
  //
  // Envia:
  //   {
  //     fk_veiculo: int,
  //     data_referencia: 'YYYY-MM-DD' (opcional),
  //     observacoes_gerais: string?,
  //     trechos: [
  //       { origem, destino, saida?, chegada?, obs? }
  //     ]
  //   }
  //
  // Retorna: { success, message, bdt_id?, protocolo? }
  // ==========================================================

  /// Lista os Pré-BDTs do usuário logado que ainda estão aguardando
  /// aprovação do admin (Sprint M3, tela inicial do app).
  static Future<List<PreBdtPendente>> listarMeusPreBdtsPendentes() async {
    final usuarioId = await _userId();
    final res = await ApiClient.post(
      'transporte/api/bdt/pre-bdt/meus-pendentes',
      {'usuario_id': usuarioId},
    );
    if (res['success'] != true) {
      _log.warn('listarMeusPreBdtsPendentes FALHOU: ${res['message']}');
      return const [];
    }
    final list = (res['data'] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => PreBdtPendente.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Autocomplete de veículos (Sprint M3).
  /// `q` vazio → 12 veículos mais recentes (para o campo abrir com opções).
  /// Backend faz LIKE em placa + modelo + marca.
  static Future<List<Veiculo>> buscarVeiculos({
    String q = '',
    int limit = 12,
  }) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post('transporte/api/bdt/veiculos/buscar', {
      'usuario_id': usuarioId,
      if (q.trim().isNotEmpty) 'q': q.trim(),
      'limit': limit,
    });
    if (res['success'] != true) {
      _log.warn('buscarVeiculos FALHOU: ${res['message']}');
      return const [];
    }
    final list = (res['data'] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => Veiculo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<Map<String, dynamic>> criarPreBdt({
    required int fkVeiculo,
    String? dataReferencia,
    String? observacoesGerais,
    required List<Map<String, dynamic>> trechos,
    // Sprint 11 W+M — carga opcional. Fotos são enviadas separadamente
    // via `uploadFotoCarga` depois de criar o Pré-BDT (precisa do bdt_id).
    bool temCarga = false,
    String? carga,
    double? cargaPesoKg,
    double? cargaComprimentoM,
    double? cargaLarguraM,
    double? cargaAlturaM,
  }) async {
    final usuarioId = await _userId();

    final payload = <String, dynamic>{
      'usuario_id': usuarioId,
      'fk_veiculo': fkVeiculo,
      if (dataReferencia != null && dataReferencia.isNotEmpty)
        'data_referencia': dataReferencia,
      if (observacoesGerais != null && observacoesGerais.trim().isNotEmpty)
        'observacoes_gerais': observacoesGerais.trim(),
      'trechos': trechos,
      'tem_carga': temCarga,
      if (temCarga && carga != null && carga.trim().isNotEmpty)
        'carga': carga.trim(),
      if (temCarga && cargaPesoKg != null && cargaPesoKg > 0)
        'carga_peso_kg': cargaPesoKg,
      if (temCarga && cargaComprimentoM != null && cargaComprimentoM > 0)
        'carga_comprimento_m': cargaComprimentoM,
      if (temCarga && cargaLarguraM != null && cargaLarguraM > 0)
        'carga_largura_m': cargaLarguraM,
      if (temCarga && cargaAlturaM != null && cargaAlturaM > 0)
        'carga_altura_m': cargaAlturaM,
    };

    final res = await ApiClient.post(
      'transporte/api/bdt/pre-bdt/criar',
      payload,
    );

    return Map<String, dynamic>.from(res);
  }

  /// Sprint M3 — carrega 1 Pré-BDT pendente do usuário logado pra
  /// pré-preencher o form de edição. Retorna `null` se o backend
  /// responder 404 (BDT não existe / já foi decidido / é de outro
  /// user) — a UI deve tratar isso mostrando um snackbar.
  static Future<PreBdtPendente?> obterPreBdt(int bdtId) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post('transporte/api/bdt/pre-bdt/obter', {
      'usuario_id': usuarioId,
      'bdt_id': bdtId,
    });
    if (res['success'] != true) {
      _log.warn('obterPreBdt#$bdtId FALHOU: ${res['message']}');
      return null;
    }
    final raw = res['data'];
    if (raw is! Map) return null;
    return PreBdtPendente.fromJson(Map<String, dynamic>.from(raw));
  }

  /// Sprint M3 — atualiza um Pré-BDT do próprio usuário enquanto
  /// ainda está pendente. Backend rejeita se: já foi aprovado/recusado,
  /// se pertence a outro usuário, ou se algum trecho tem origem/destino
  /// em branco. Retorna o Map bruto {success, message, bdt_id, protocolo}
  /// pra a UI decidir o fluxo (snackbar + volta pra home).
  static Future<Map<String, dynamic>> atualizarPreBdt({
    required int bdtId,
    required int fkVeiculo,
    String? dataReferencia,
    String? observacoesGerais,
    required List<Map<String, dynamic>> trechos,
    bool temCarga = false,
    String? carga,
    double? cargaPesoKg,
    double? cargaComprimentoM,
    double? cargaLarguraM,
    double? cargaAlturaM,
  }) async {
    final usuarioId = await _userId();
    final payload = <String, dynamic>{
      'usuario_id': usuarioId,
      'bdt_id': bdtId,
      'fk_veiculo': fkVeiculo,
      if (dataReferencia != null && dataReferencia.isNotEmpty)
        'data_referencia': dataReferencia,
      'observacoes_gerais':
          (observacoesGerais ?? '').trim().isEmpty ? '' : observacoesGerais!.trim(),
      'trechos': trechos,
      'tem_carga': temCarga,
      if (temCarga && carga != null && carga.trim().isNotEmpty)
        'carga': carga.trim(),
      if (temCarga && cargaPesoKg != null && cargaPesoKg > 0)
        'carga_peso_kg': cargaPesoKg,
      if (temCarga && cargaComprimentoM != null && cargaComprimentoM > 0)
        'carga_comprimento_m': cargaComprimentoM,
      if (temCarga && cargaLarguraM != null && cargaLarguraM > 0)
        'carga_largura_m': cargaLarguraM,
      if (temCarga && cargaAlturaM != null && cargaAlturaM > 0)
        'carga_altura_m': cargaAlturaM,
    };
    final res = await ApiClient.post(
      'transporte/api/bdt/pre-bdt/atualizar',
      payload,
    );
    return Map<String, dynamic>.from(res);
  }

  // ==========================================================
  // Sprint 11 W+M — Fotos de CARGA no Pré-BDT
  // Sprint 18 refactor: delegado ao FotoDocumentoClient (mesmo padrão
  // de ocorrência/abastecimento/manutenção).
  // Ownership: bdt->criado_por == usuário logado.
  // ==========================================================

  static const _fotoCargaClient = FotoDocumentoClient(
    uploadPath:  'transporte/api/bdt/pre-bdt/fotos-carga/upload',
    listarPath:  'transporte/api/bdt/pre-bdt/fotos-carga/listar',
    obterPath:   'transporte/api/bdt/pre-bdt/fotos-carga/obter',
    excluirPath: 'transporte/api/bdt/pre-bdt/fotos-carga/excluir',
    refField: 'bdt_id',
  );

  static Future<List<OcorrenciaFotoRef>> listarFotosCarga(int bdtId) async {
    final refs = await _fotoCargaClient.listar(bdtId);
    return refs
        .map((r) => OcorrenciaFotoRef(
              id: r.id,
              mimeType: r.mimeType,
              createdAt: r.createdAt,
            ))
        .toList();
  }

  static Future<List<int>?> obterFotoCarga(int docId) =>
      _fotoCargaClient.obter(docId);

  /// Retorna docId (>0 sucesso, 0 falha).
  static Future<int> uploadFotoCarga({
    required int bdtId,
    required List<int> bytes,
    required String filename,
  }) {
    return _fotoCargaClient.upload(
      refId: bdtId,
      bytes: bytes,
      filename: filename,
    );
  }

  static Future<bool> excluirFotoCarga(int docId) =>
      _fotoCargaClient.excluir(docId);

  // ==========================================================
  // Sprint M4 — Validação de atendimento
  // ==========================================================

  /// Registra um marco da jornada COM assinatura opcional (M4).
  /// Reusa o endpoint bdt/jornada/marco que já suporta os campos novos.
  static Future<Map<String, dynamic>> registrarMarcoComAssinatura({
    required int bdtId,
    required String marco, // partida|apresentacao|embarque_passageiro
    String? observacao,
    String? assinaturaSvg,
    String? signatarioNome,
    String? signatarioTipo, // condutor|passageiro|outro
  }) async {
    final usuarioId = await _userId();

    final payload = <String, dynamic>{
      'bdt_id': bdtId,
      'marco': marco,
      'usuario_id': usuarioId,
      if (observacao != null && observacao.trim().isNotEmpty)
        'observacao': observacao.trim(),
      if (assinaturaSvg != null && assinaturaSvg.trim().isNotEmpty)
        'assinatura_svg': assinaturaSvg,
      if (signatarioNome != null && signatarioNome.trim().isNotEmpty)
        'signatario_nome': signatarioNome.trim(),
      if (signatarioTipo != null && signatarioTipo.trim().isNotEmpty)
        'signatario_tipo': signatarioTipo,
    };

    final res = await ApiClient.post(
      'transporte/api/bdt/jornada/marco',
      payload,
    );
    _log.info('registrarMarcoComAssinatura marco=$marco ok=${res["success"]}');
    return Map<String, dynamic>.from(res);
  }

  /// Lista passageiros previstos do BDT (M4.1).
  static Future<List<Passageiro>> listarPassageiros(int bdtId) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post('transporte/api/bdt/passageiros/listar', {
      'bdt_id': bdtId,
      'usuario_id': usuarioId,
    });
    if (res['success'] != true) {
      _log.warn('listarPassageiros FALHOU: ${res['message']}');
      return const [];
    }
    final list = (res['data'] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => Passageiro.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Envia bulk update de presença/embarque_extra dos passageiros (M4.1).
  static Future<bool> marcarPresencaPassageiros({
    required int bdtId,
    required List<Map<String, dynamic>> updates,
  }) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post(
      'transporte/api/bdt/passageiros/marcar-presenca',
      {
        'bdt_id': bdtId,
        'usuario_id': usuarioId,
        'updates': updates,
      },
    );
    final ok = res['success'] == true;
    _log.info('marcarPresencaPassageiros ok=$ok updated=${res['atualizados']}');
    return ok;
  }

  /// Encerra o BDT (M4.3). Mudança para status ENCERRADO=3.
  static Future<Map<String, dynamic>> encerrarBdt({
    required int bdtId,
    String? observacao,
  }) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post('transporte/api/bdt/encerrar', {
      'bdt_id': bdtId,
      'usuario_id': usuarioId,
      if (observacao != null && observacao.trim().isNotEmpty)
        'observacao': observacao.trim(),
    });
    _log.info('encerrarBdt ok=${res["success"]} msg=${res["message"]}');
    return Map<String, dynamic>.from(res);
  }

  /// Registra o feedback do condutor sobre a viagem (M4.3).
  /// Upsert do lado backend: 1 feedback por BDT.
  static Future<bool> registrarFeedbackCondutor({
    required int bdtId,
    required int nota, // 1-5
    String? comentario,
  }) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post(
      'transporte/api/bdt/feedback-condutor/registrar',
      {
        'bdt_id': bdtId,
        'usuario_id': usuarioId,
        'nota': nota,
        if (comentario != null && comentario.trim().isNotEmpty)
          'comentario': comentario.trim(),
      },
    );
    final ok = res['success'] == true;
    _log.info('registrarFeedbackCondutor ok=$ok nota=$nota');
    return ok;
  }

  /// Obtém feedback existente (para a UI mostrar em modo readonly).
  static Future<FeedbackCondutor?> obterFeedbackCondutor(int bdtId) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post(
      'transporte/api/bdt/feedback-condutor/obter',
      {'bdt_id': bdtId, 'usuario_id': usuarioId},
    );
    if (res['success'] != true) return null;
    final j = res['feedback'];
    if (j is! Map) return null;
    return FeedbackCondutor.fromJson(Map<String, dynamic>.from(j));
  }
}
