import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../utils/logger.dart';

/// Sprint 6 W+M — carga declarada nas solicitações vinculadas ao BDT.
///
/// SOMENTE LEITURA — o upload da carga é feito no fluxo do Pré-BDT
/// (Sprint 11 W+M, `PreBdtFormPage` + `BdtService.uploadFotoCarga`).
/// Depois do admin aprovar o Pré-BDT, `PreBdtService::materializar
/// Solicitacao` migra as fotos de `tabela=trnsp_bdt` para
/// `tabela=trnsp_solicitacoes` — daí este service consumir um
/// endpoint separado (`bdt/carga/foto/obter`) que aponta pra tabela
/// materializada.
///
/// Consumido pelo card "Carga declarada" do BdtFormPage — condutor
/// consulta o que foi PROMETIDO antes de chegar no destino; se der
/// divergência, registra pelo card "Divergências de carga" (mesmo BDT).
class CargaService {
  static const _log = Logger('CARGA-SVC');

  static Future<int> _userId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('usuario_id') ?? 0;
  }

  /// Lista todas as cargas declaradas nas solicitações do BDT (pode ter
  /// mais de uma se o BDT atende múltiplas solicitações — modelo W7).
  /// Retorna lista vazia se nada foi declarado (BDT sem carga).
  static Future<List<CargaDoBdt>> listar(int bdtId) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post(
      'transporte/api/bdt/carga',
      {'usuario_id': usuarioId, 'bdt_id': bdtId},
    );
    if (res['success'] != true) {
      _log.warn('listar#$bdtId FALHOU: ${res['message']}');
      return const [];
    }
    final list = (res['data'] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => CargaDoBdt.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Baixa binário de uma foto de carga do BDT. Bearer + ETag no backend.
  ///
  /// [origem] diz de onde a foto vem — `'solicitacao'` (carga prometida no
  /// pedido, ou Pré-BDT já aprovado) ou `'bdt'` (carga declarada direto no
  /// BDT: Pré-BDT pendente e BDT criado direto pelo app). O backend usa esse
  /// valor pra escolher a tabela de referência; a autorização é sempre por
  /// condutor do BDT.
  static Future<List<int>?> obterFoto(
    int docId, {
    required int bdtId,
    String origem = 'solicitacao',
  }) async {
    final usuarioId = await _userId();
    return ApiClient.postForBytes(
      'transporte/api/bdt/carga/foto/obter',
      {
        'usuario_id': usuarioId,
        'doc_id': docId,
        'bdt_id': bdtId,
        'origem': origem,
      },
    );
  }
}

/// Uma carga declarada em uma solicitação vinculada ao BDT.
/// `fotos` traz metadata (id/mime/desc/criado) — bytes vêm sob demanda
/// via [CargaService.obterFoto].
class CargaDoBdt {
  final int solicitacaoId;
  final int ano;
  final int numeroAno;

  /// Texto livre descrevendo a carga ("2 mesas + 1 impressora", etc.).
  final String? descricao;

  final double? pesoKg;
  final double? comprimentoM;
  final double? larguraM;
  final double? alturaM;

  final String? pessoalApoio;
  final List<CargaFotoRef> fotos;

  /// Onde a carga (e as fotos) estão guardadas — `'solicitacao'` ou `'bdt'`.
  /// Repassado ao backend em [CargaService.obterFoto] pra ele saber a tabela
  /// de referência. Ver doc do método.
  final String origem;

  /// Estado do Pré-BDT quando a carga é do próprio BDT (`'pendente'`,
  /// `'aprovado'`, `'recusado'`) — null no BDT criado direto.
  ///
  /// É o que separa carga DEFINITIVA de PROVISÓRIA: a recusa de um Pré-BDT
  /// **não apaga** a carga de `trnsp_bdt`, então sem isso o app mostraria
  /// como carga real algo de uma viagem que não vai acontecer.
  final String? preBdtStatus;

  const CargaDoBdt({
    required this.solicitacaoId,
    required this.ano,
    required this.numeroAno,
    this.descricao,
    this.pesoKg,
    this.comprimentoM,
    this.larguraM,
    this.alturaM,
    this.pessoalApoio,
    this.fotos = const [],
    this.origem = 'solicitacao',
    this.preBdtStatus,
  });

  /// True quando a carga foi declarada no próprio BDT (BDT criado direto pelo
  /// app, ou Pré-BDT ainda não aprovado) em vez de numa solicitação.
  bool get declaradaNoBdt => origem == 'bdt';

  /// True quando a viagem desta carga foi RECUSADA — a carga fica no
  /// histórico mas não deve ser conferida.
  bool get viagemRecusada => declaradaNoBdt && preBdtStatus == 'recusado';

  /// True quando a carga ainda depende de aprovação do Pré-BDT.
  bool get aguardandoAprovacao =>
      declaradaNoBdt && preBdtStatus == 'pendente';

  /// Rótulo da origem, ou null quando a carga vem de solicitação (aí o
  /// próprio protocolo TRN- já diz tudo).
  ///
  /// Mesmas regras do `BDTController::rotuloOrigemCarga` no backend.
  String? get rotuloOrigem {
    if (!declaradaNoBdt) return null;
    switch (preBdtStatus) {
      case 'pendente':
        return 'declarada no Pré-BDT · aguardando aprovação';
      case 'recusado':
        return 'Pré-BDT recusado · carga não se realiza';
      case 'aprovado':
        return 'declarada no Pré-BDT (aprovado)';
      default:
        // Sem preBdtStatus = BDT criado direto: definitivo.
        return 'declarada no BDT';
    }
  }

  /// Aviso a exibir junto do rótulo, quando a carga não é definitiva.
  String? get avisoOrigem {
    if (aguardandoAprovacao) {
      return 'Carga provisória: se o Pré-BDT for recusado, esta viagem não '
          'acontece.';
    }
    if (viagemRecusada) {
      return 'O Pré-BDT foi recusado. Esta carga fica no histórico, mas não '
          'deve ser conferida.';
    }
    return null;
  }

  /// Protocolo formatado. `TRN-BDT-` quando a carga é do próprio BDT (a
  /// numeração vem de `trnsp_bdt`, sequência distinta da de solicitações);
  /// `TRN-` quando vem de uma solicitação.
  String get protocolo {
    final a = ano.toString().padLeft(4, '0');
    final n = numeroAno.toString().padLeft(4, '0');
    return declaradaNoBdt ? 'TRN-BDT-$a-$n' : 'TRN-$a-$n';
  }

  /// True se ao menos um campo de carga foi preenchido (peso, dimensão,
  /// texto ou apoio) — se todos vazios, a solicitação nem entra no
  /// resultado do backend, mas defensivo aqui pra futuro.
  bool get temCargaReal =>
      pesoKg != null ||
      comprimentoM != null ||
      larguraM != null ||
      alturaM != null ||
      (descricao?.trim().isNotEmpty ?? false);

  factory CargaDoBdt.fromJson(Map<String, dynamic> j) {
    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }
    double? asDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().replaceAll(',', '.'));
    }

    final rawFotos = j['fotos'];
    final fotos = rawFotos is List
        ? rawFotos
            .whereType<Map>()
            .map((e) => CargaFotoRef.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : const <CargaFotoRef>[];

    return CargaDoBdt(
      solicitacaoId: asInt(j['solicitacao_id']) ?? 0,
      ano: asInt(j['ano']) ?? 0,
      numeroAno: asInt(j['numero_ano']) ?? 0,
      descricao: j['descricao']?.toString(),
      pesoKg: asDouble(j['peso_kg']),
      comprimentoM: asDouble(j['comprimento_m']),
      larguraM: asDouble(j['largura_m']),
      alturaM: asDouble(j['altura_m']),
      pessoalApoio: j['pessoal_apoio']?.toString(),
      fotos: fotos,
      origem: (j['origem']?.toString().trim().isNotEmpty ?? false)
          ? j['origem'].toString()
          : 'solicitacao',
      preBdtStatus: (j['pre_bdt_status']?.toString().trim().isNotEmpty ?? false)
          ? j['pre_bdt_status'].toString()
          : null,
    );
  }
}

class CargaFotoRef {
  final int id;
  final String? mimeType;
  final String? descricao;
  final String? createdAt;

  const CargaFotoRef({
    required this.id,
    this.mimeType,
    this.descricao,
    this.createdAt,
  });

  factory CargaFotoRef.fromJson(Map<String, dynamic> j) {
    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }
    return CargaFotoRef(
      id: asInt(j['id']) ?? 0,
      mimeType: j['mime_type']?.toString(),
      descricao: j['descricao']?.toString(),
      createdAt: j['created_at']?.toString(),
    );
  }
}
