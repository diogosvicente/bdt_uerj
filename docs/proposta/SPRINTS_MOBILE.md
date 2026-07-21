# Plano de Sprints — Repo BDT-Flutter (app mobile)

_Extrato do plano geral só com os itens que serão implementados no app Flutter (repo separado)._

> **📍 Fonte da verdade:** este doc **vive aqui** no repo `bdt_uerj` a partir da branch `feature/m0-m1-login-ux` (Sprint M0/M1 iniciada em 2026-07-18). A cópia no repo `e-prefeitura` (`docs/proposta/SPRINTS_MOBILE.md`) fica como referência histórica.

> Para o plano do repo `e-prefeitura` (web), ver `SPRINTS_WEB.md`.
> Para a lista de cada item com plataforma, ver `MVP_Selector.xlsx` aba **Itens** (coluna **Plataforma**: filtre por **Mobile** ou **Web+Mobile**).

---

## Princípio arquitetural — sempre reusar código web quando existir

Quando o mobile precisar implementar um comportamento que o web
(`e-prefeitura`) já implementa de alguma forma — como service,
controller, seeder ou até uma migration —, a regra é **executar o
código web direto**, não reescrever a lógica em paralelo.

**Por quê:**
- Doc de apoio (extrair a lógica web num markdown pra "copiar como
  guia") vira dupla verdade e fica desatualizado — a gente segue um
  passo-a-passo escrito, o web evolui, e o mobile diverge sem
  ninguém perceber.
- Reescrever é uma **oportunidade adicional de bug**. Exemplo real
  desta sprint: o `PreBdtService::criarPeloCondutor` fazia inserts
  extras que o seeder `PreBdtTesteSeeder` não fazia — resultado:
  Pré-BDT pendente aparecia na "lista do dia" como se fosse BDT
  operacional (bug reportado como "duplicando / BDT vazio").

**Como aplicar:**
1. Ao abrir uma nova feature mobile, procurar primeiro por
   `Seeds/`, `Services/`, `Controllers/` ou testes no
   `e-prefeitura` que já façam algo parecido.
2. Se existir: o backend mobile (rota `transporte/api/*`) deve ser
   um **wrapper fino** em cima desse service/repositório — só
   valida input do JSON, chama o método existente, formata a
   resposta pro app.
3. Se **não existir** (feature 100% nova pro mobile, como o
   "Pré-BDT criado pelo condutor"), então sim, criamos o service
   novo — mas seguindo o padrão do web (categoria, transações,
   assertivas, `allowedFields`, etc.).

Ver também [[bdt_uerj_mobile_nao_quebra_web]] — regra complementar
sobre nunca alterar contrato web ao mexer no backend pra atender
mobile.

---

## Composição

| Tipo | Itens | Horas | Onde |
|---|---:|---:|---|
| 📱 **Mobile only** | 18 | 306h | Implementação 100% no app Flutter |
| 🔀 **Web+Mobile** | 13 | 228h | Implementação no app Flutter **complementa** o que é feito no web |

**Total no Flutter**: ~31 itens / ~340h (estimativa conservadora — itens Web+Mobile geralmente consumem 30-50% do esforço total no app)

---

## Pré-requisitos (antes de começar mobile)

| | Requisito | Por quê |
|---|---|---|
| ⏳ | Repo Flutter clonado e rodando local | Sem isso não dá pra editar nada |
| ⏳ | Versão do Flutter conhecida (`flutter --version`) | Calibrar libs compatíveis (notifications, background services) |
| ⏳ | Endpoints da API e-Prefeitura mapeados | Mobile depende de APIs do web |
| ⏳ | Sprint 0 do `SPRINTS.md` aplicada na `development` | Os 8 roles novos precisam estar criados antes (mobile usa `Abrir BDT no App Mobile` etc.) |
| ⏳ | Decisão sobre estado de gerenciamento (Provider / Riverpod / Bloc) | Se vai padronizar agora ou herdar o que já existe |

---

## Sprint M0 📱 — Quick fix (~2h) — ✅ concluída

**Objetivo:** corrigir bug travado.

- ✅ Botão **Sair** no app mobile (logout funcional) — 2h
  - `AppNavbar` menu 3 pontos → "Sair"
  - `AuthService.logout()` limpa `token`, `usuario_id`, `usuario_*` e a flag `login_manter_conectado`
  - Redireciona para `/login`

> Esse item estava no escopo da Sprint 0 do plano web, mas foi movido para cá quando ficou claro que o app está em repo separado.

---

## Sprint M1 📱 — Login + UX (~64h) — ✅ concluída
**Equivalente à Sprint 2 do plano web.**

**Objetivo:** experiência de login confortável e UX clara nas listas.

> **Estado (branch `feature/m0-m1-login-ux`):** tudo entregue. Backend em `feature/027-sprint-m1-login-api` no repo `e-prefeitura` (captcha tokenizado).

- ✅ Manter sessão ativa após fechar/bloquear celular — 8h
  - Auto-login via `token`+`login_manter_conectado` no bootstrap da `LoginPage`
  - `AuthService.verifyToken()` valida o token contra o backend antes de auto-redirecionar; se 401/403 limpa o storage
- ✅ Salvar senha (Keychain/Keystore) + botão eye — 12h
  - Botão eye (`visibility` / `visibility_off`) no `TextField` da senha
  - Senha em `flutter_secure_storage` (Android Keystore / iOS Keychain) via `CredentialsStorage`
  - Migração transparente de quem já tinha senha em `SharedPreferences` (plaintext)
- ✅ Captcha no login do app (reuso do captcha web) — 12h
  - `CaptchaService.fetchNew()` consome `POST /transporte/api/captcha/new`
  - `CaptchaField` widget com imagem, refresh e campo de resposta
  - Uso único por token, recarrega automaticamente em erro
- ✅ Abrir BDT direto no app (só condutor atrelado, confirmar veículo) — 16h
  - `HomePage._maybeAutoOpen` — se hoje e a lista retornar exatamente 1 BDT, abre diálogo "Confirmar veículo" com placa/marca/modelo antes de navegar
  - Usuário pode escolher outro (fica na lista) sem loop de auto-open
- ✅ Exibir Protocolo (não ID) — agendas e trechos com nomes lógicos — 8h
  - `BdtResumo.titulo` = "BDT ano/numero"
  - `bdt_page`/`bdt_form_page` usam sempre ano/numero (nunca "#$bdtId")
- ✅ Organizar agendas/trechos sem expor IDs — 8h
  - Título da agenda: "Agenda das HH:MM" ou "Agenda N" (índice)
  - Banner de tracking: "$origem → $destino" via `_labelTrechoAtivo()`

---

## Sprint M2 📱 — GPS (~64h) — ✅ concluída
**Equivalente à Sprint 3 do plano web.**

**Objetivo:** rastreamento confiável mesmo com celular bloqueado ou sem internet.

- ✅ UI de origem/destino no app (visual melhor) — 8h
  - `bdt_page._cardTrechoAtivo`: card grande com Origem/Destino em destaque + chips `Online/Offline` (via `connectivity_plus`) e `N na fila` / `Enviado`
  - Estado atualizado a cada 10s (`_pontosTimer`) + reativo à conectividade (`Connectivity().onConnectivityChanged`)
- ✅ Corrigir saltos espúrios de GPS (filtragem de outliers) — 16h
  - `LocationOutlierFilter`: descarta pontos com accuracy > 50m, velocidade > 200 km/h ou teleporte > 500m em <5s (Haversine)
  - Filtro stateful; `reset()` ao trocar de trecho
- ✅ GPS em background + sync offline (cache local + reenvio coerente) — 40h
  - `LocationQueueDb` (sqflite): fila persistente `pending_locations` com `attempts` e `last_error`; max 10 tentativas antes de descartar
  - `BackgroundLocationService._drainQueue`: worker no isolate do foreground service consome batch de 20 pontos a cada 30s
  - Fluxo: `Geolocator → outlier filter → SQLite → worker HTTP`. Sem rede o ponto fica na fila; ao reconectar, o worker drena
  - `AndroidManifest.xml`: `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` + `LocationService.ensureBatteryOptimizationDisabled()` — pede isenção de Doze na entrada da tela do BDT (M2.4)

> ⚠️ Item de **maior risco** do MVP mobile (V=65%, R=65%). A implementação seguiu o padrão recomendado — validação real em produção (30+ min bloqueado, offline em túnel, etc.) fica para a fase de QA/piloto.

---

## Sprint M3 📱 — Pré-BDT criação (~32h) — ✅ concluída
**Paralela à Sprint 1 do plano web.**

**Objetivo:** condutor pode pré-criar BDT no app para saídas urgentes.

- ✅ Pré-BDT — criação pelo condutor — 32h
  - **Backend** (`e-prefeitura` `feature/027-mobile-support`):
    `POST /transporte/api/bdt/pre-bdt/criar` + `PreBdtService::criarPeloCondutor()`
    grava `trnsp_bdt` (status Pré-BDT pendente) + trechos previstos + histórico
    em transação, retorna `{bdt_id, protocolo}`
  - **Frontend** (`bdt_uerj` `main`):
    `PreBdtFormPage` (rota `/pre_bdt/novo`) com card de identificação
    (veículo + data), card de trechos com adicionar/remover dinâmico
    (origem/destino + horários), card de observações. FAB na `HomePage`
    ("Novo Pré-BDT") dá acesso rápido.
  - Depois de enviar, dialog mostra o protocolo gerado e volta pra home.
  - O Pré-BDT vira BDT operacional quando o admin aprovar via web
    (`PreBdtAdminController`, já existente da Sprint W1).
- ✅ Refino M3 (após dogfooding no Pixel): condutor real não sabe o
  ID interno do veículo — form ficou com um autocomplete (`GET
  /transporte/api/veiculos/buscar`, widget `VeiculoAutocomplete` com
  debounce 250ms + cache). Corrigido também insert em
  `trnsp_bdt_condutores` que faltava (Pré-BDT criado não vinculava o
  condutor à execução).
- ✅ Edição do próprio Pré-BDT enquanto pendente — o condutor pode
  corrigir veículo/data/observações/trechos até o admin aprovar ou
  recusar.
  - **Backend** (`feature/027-mobile-support`): `POST bdt/pre-bdt/obter`
    (pré-carrega o form) e `POST bdt/pre-bdt/atualizar` (salva). Guard
    em `PreBdtRepository::findMeuPendente(bdtId, userId)` — retorna null
    se o BDT é de outro usuário OU se `pre_bdt_status != pendente`.
    Trechos: soft-delete todos e recria (seguro nesta fase — ainda não
    foram materializados em `trnsp_solicitacao_trechos`). Grava
    histórico "editado pelo condutor via app mobile".
  - **Frontend**: `PreBdtFormPage` refatorada em modo criar/editar —
    lê `bdtId` via `ModalRoute.arguments`; se presente, chama
    `obterPreBdt` no `didChangeDependencies` e pré-preenche
    veículo/data/obs/trechos. Título e botão adaptativos. Se o backend
    retornar null (não pode mais editar), mostra card de erro com
    botão "Voltar". Nova rota `/pre_bdt/editar` (mesmo widget da
    `/pre_bdt/novo`). Tap no card de pendentes da HomePage navega
    pra edição; retorno com `pop(true)` recarrega o card.
- ✅ Bugfix "Pré-BDT aparece duplicado / BDT vazio" (2026-07-20) —
  quando o condutor criava Pré-BDT pelo app, ele aparecia tanto no
  card "Meus Pré-BDTs pendentes" quanto na lista "BDTs do dia".
  Causa: `BdtModel::listarDoDiaPorCondutor` (usado pela home) faz
  `INNER JOIN trnsp_bdt_condutores` sem filtrar por status, e o
  `criarPeloCondutor` cria esse vínculo (necessário pra tela admin
  ver quem abriu). Correção **aditiva**: `whereNotIn('b.id_status_atual',
  BdtStatus::PENDENTES_APROVACAO)`. Pré-BDT com status PRE_BDT (6)
  só reaparece na lista do dia depois de aprovado E aberto pelo
  admin (quando `id_status_atual` vira EM_ABERTO).
- ✅ Visibilidade dos Pré-BDTs pendentes na home — condutor precisava
  saber quais Pré-BDTs criou que ainda estão aguardando aprovação.
  - **Backend** (`feature/027-mobile-support`): `POST bdt/pre-bdt/meus-pendentes` +
    `PreBdtRepository::listarMeusPendentes()` (JOIN veículo/marca/modelo,
    filtra por `criado_por = usuário logado AND pre_bdt_status = 'pendente'`)
    + `PreBdtService` enriquece com `protocolo` e `trechos_previstos`.
  - **Frontend**: modelo `PreBdtPendente`, método
    `BdtService.listarMeusPreBdtsPendentes()` e nova seção na `HomePage`
    (card "Meus Pré-BDTs aguardando aprovação") acima da lista de BDTs
    do dia. Some do card se lista vier vazia. O botão 🔄 da AppBar
    recarrega as duas listas em paralelo (`Future.wait`), e o retorno do
    form (`pop(true)`) também dispara refresh só do card.

---

## Sprint M4 📱 — Validação atendimento (parte 1) (~88h) — ✅ concluída
**Equivalente à Sprint 10 do plano web.**

**Objetivo:** condutor formaliza início e conclusão do atendimento no app.

- ✅ Validação de INÍCIO do atendimento (embarque) — formulário no app — 40h
  - **Backend** (`feature/027-mobile-support`): `POST bdt/passageiros/listar` e `bdt/passageiros/marcar-presenca` (bulk, valida pertencimento).
  - **Frontend**: `ValidacaoInicioPage` (rota `/validacao/inicio`) mostra os 3 marcos + lista de passageiros com switch de presença; botão "Salvar presenças" faz bulk update.
- ✅ Assinatura touch no tablet/celular do condutor + identificar signatário — 24h
  - **Backend**: extensão de `POST bdt/jornada/marco` com `assinatura_svg`, `signatario_nome`, `signatario_tipo`; migration em `trnsp_bdt_assinaturas`.
  - **Frontend**: dependência `signature: ^5.5.0` + `SignaturePad` widget wrapper (`lib/widgets/signature_pad.dart`) + `AssinaturaMarcoPage` (rota `/marco/assinatura`) que casa signatário/tipo/observação com o desenho.
- ✅ Validação de CONCLUSÃO + feedback do condutor — 24h
  - **Backend**: nova tabela `trnsp_bdt_feedback_condutor` (1 por BDT) + `POST bdt/feedback-condutor/registrar` (upsert), `POST bdt/feedback-condutor/obter`, `POST bdt/encerrar` (muda `id_status_atual` para `ENCERRADO=3` com transação).
  - **Frontend**: `ConclusaoPage` (rota `/conclusao`) com estrelas 1–5 + comentário + botão "Encerrar BDT" (habilita só depois do feedback salvo, com confirmação).
  - Novos itens no `_openBdtActionsSheet` do `bdt_page.dart`: "Validar início" e "Concluir viagem".
- ✅ Duplicação de trechos extras no `bdt_page.dart` — trechos que já
  aparecem numa agenda estavam sendo listados de novo na seção
  "Trechos extras". Correção no `BdtApiService::detalhes` (mobile,
  aditivo): subtrai do array `trechos_extras` todos os ids que já
  foram listados em `agendas[N].trechos`. Card "Trechos extras"
  agora só mostra os trechos avulsos (sem agenda).
- ✅ Nova AppBar (Sprint M6/UX): logo institucional da UERJ (brasão
  circular em capsule branca) à esquerda, título + subtítulo à
  direita, fundo com gradient azul UERJ (`#0D47A1 → #002171`) e
  sombra sutil. O parâmetro `subtitle` — antes ignorado — agora
  aparece abaixo do título. `AppNavbar._toolbarHeight = 76`.
- ✅ Auto-abertura de BDT ao iniciar trecho + KM inicial opcional —
  paridade com o web, que já fazia isso automaticamente.
  - **Backend** (`feature/027-mobile-support`): `BdtApiService::iniciarTrecho`
    ganhou parâmetro `?float $kmInicial` (opcional, salva só se
    `trnsp_bdt.km_inicial` estava vazio) e um helper privado
    `iniciarBdtSeAberto()` — réplica intencional de
    `BDTController::iniciarBdtSeAberto` do web (muda status
    `EM_ABERTO → EM_ANDAMENTO`, insere histórico "BDT iniciado
    automaticamente...", com `origem = 'mobile'`). Novo endpoint
    `POST bdt/km/estado` — consulta leve `{km_inicial, km_final,
    id_status_atual}` para o app decidir se precisa perguntar KM.
  - **Frontend**: novo model `BdtKmEstado`; `BdtService.obterEstadoKm`
    e `iniciarTrecho` com `kmInicial?` opcional. Em `bdt_page.dart`,
    helper `_askKmInicialSePreciso` mostra dialog com campo numérico
    e três botões (Cancelar / Pular / Salvar e iniciar) antes das
    duas chamadas de `iniciarTrecho` existentes.

---

## Sprint M5 📱 — Alertas inteligentes (~40h) — ✅ concluída
**Equivalente à Sprint 18 do plano web.**

**Objetivo:** notificar o condutor com antecedência da saída.

- ✅ 1º Alerta — preparação (1h antes da saída programada) — 24h
- ✅ 2º Alerta — deslocamento (30min antes) — 16h
  - **Backend** (`feature/027-mobile-support`): `BdtModel::listarDoDiaPorCondutor`
    ganhou uma subquery que retorna `hora_saida_prevista =
    MIN(trnsp_solicitacao_trechos.saida)` agregando todos os trechos
    das solicitações vinculadas ao BDT via `trnsp_bdt_designacao`.
    Sem esse campo o app não teria hora pra agendar alerta.
  - **Frontend**: novo `AlertasService` (categoria PLATFORM) usando
    `flutter_local_notifications` + `timezone`. `init()` no bootstrap
    do `main.dart` (canal Android + permissão POST_NOTIFICATIONS).
    `sincronizarComBdtsDoDia(List<BdtResumo>)` faz `cancelAll` + agenda
    2 alertas por BDT com `horaSaidaPrevista` futura (IDs
    `bdtId*10+1` e `bdtId*10+2`). Chamado no `initState` da HomePage
    e depois de cada `_reload`. Payload = `bdtId` — ao tocar na
    notificação, o app abre `/bdt` via `navigatorKey`.
    `cancelarBdt(int)` chamado em `ConclusaoPage` quando o BDT é
    encerrado. Novo campo `horaSaidaPrevista` em `BdtResumo`.
  - **Android manifest**: `SCHEDULE_EXACT_ALARM` + `USE_EXACT_ALARM`
    (Android 12+). Se o usuário negar, fallback pra
    `inexactAllowWhileIdle` — alerta ainda dispara, com alguns min
    de atraso.
  - Integração opcional com WhatsApp depende da pesquisa de
    viabilidade feita na Sprint 17 do plano web — **não incluída
    nesta iteração**.

---

## 🔀 Trabalho complementar (Web+Mobile) — encaixa nas sprints acima

Os 13 itens Web+Mobile precisam de implementação parcial no app. O esforço já está contado no plano web (sprint do "lado web") — aqui vai a **lista do que toca no Flutter**, organizada pela sprint web correspondente:

> ⚠️ **Redefinição do BDT (nova W7 web):** o web passou a tratar o **BDT como uma VIAGEM** (veículo+condutor, dia/período) que atende **uma ou mais solicitações** (M:N), com **local de embarque + assinatura por solicitação** dentro do BDT e o **local de embarque definido pelo admin**. A consolidação fica no **Painel de BDTs** (filtros + folha de despacho em PDF) — **não** há entidade "Programação" separada. Isso muda o modelo que o app consome: a **criação de BDT/Pré-BDT (M3)** e o **"BDT sem solicitação"** (abaixo) seguem o **BDT = viagem**. As referências "**Sprint N web**" abaixo usam a **numeração do plano original** — **não** mudam com a renumeração dos W-labels no web (a antiga W7 virou W8, …, W15 → W16; foi inserida a nova W7 = Redefinição do BDT).

### Da Sprint 1 web (Pré-BDT)
- ⏳ Modal de informações de segurança no BDT (telas + texto)

### Da Sprint 4 web (Trabalho de campo)
- ✅ Marcar presença/ausência de passageiros — entregue na Sprint M4
  (`ValidacaoInicioPage` + `POST bdt/passageiros/marcar-presenca`)
- ⏳ Trabalho de campo — exibição do PDF parseado e confirmação
  (depende do parser web)

### Da Sprint 5 web (Marcos)
- ✅ Marcos PARTIDA / APRESENTAR-SE / PASSAGEIRO (state machine UI)
  — entregues na Sprint M4 (`validacao_inicio_page.dart` linhas
  146-148: `partida`, `apresentacao`, `embarque_passageiro`; UI de
  cada um em `_rowMarco` + `AssinaturaMarcoPage`)
- ⏳ Marco HORA DE SAÍDA (UX no app) — 4º marco adicional, ainda
  não implementado

### Da Sprint 6 web (Cargas)
- ⏳ Cancelar/redirecionar BDT por divergência de carga (UX do condutor)

### Da Sprint 9 web (Viagens avulsas)
- ✅ Viagens avulsas no BDT (UX de adicionar) — base entregue
  (`trecho_extra_form_page.dart` + `POST bdt/trecho-extra/criar`)
- ⏳ Refinar adição de trechos (gaps de UX) — polimento contínuo

### Da Sprint 11 web (Anexo carga)
- ⏳ Anexo obrigatório de fotos para carga (validação no app)
  — depende do fluxo web de "carga" (Sprint 11 web)

### Da Sprint 15 web (BDT sem solicitação)
- ⏳ Veículo/condutor reais ≠ agendados (UX de checkup no app)

### Da Sprint 17 web (Ocorrências)
- ⏳ Anexos de fotos em ocorrências/manutenção (extensão no app)
  — depende do fluxo web de anexo em ocorrência
- ⏳ Histórico institucional de ocorrências (visualização no app)
  — depende do endpoint web de histórico

---

## ⏸️ Backlog futuro do mobile (não MVP)

- 3º Alerta — status automático ao sistema (40h) — falsos positivos
- Auto-preenchimento da ocorrência (8h) — adiado
- Passageiro assinar no próprio celular (futuro) — dispositivo do passageiro, não do condutor

---

## Visão consolidada (só mobile)

| Sprint M | Foco | Horas |
|---:|---|---:|
| M0 | Quick fix botão Sair | 2 |
| M1 | Login + UX | 64 |
| M2 | GPS (background + offline) | 64 |
| M3 | Pré-BDT criação | 32 |
| M4 | Validação atendimento | 88 |
| M5 | Alertas inteligentes | 40 |
| **TOTAL mobile only** | | **290h** |
| Complementar Web+Mobile (estimativa) | | ~80-100h |
| **TOTAL Flutter** | | **~370-390h** |

> A diferença em relação aos 306h "Mobile" + 228h "Web+Mobile" do total geral é porque o esforço Web+Mobile é dividido entre os 2 repos: aprox. 50-60% no web (APIs, regras), 40-50% no mobile (UX).

---

## Como ler

- **Cada Sprint M é independente** das outras (exceto M0 e M1 que destravam estado de login).
- Podem ser executadas **em paralelo** com as sprints do web — desde que as dependências de backend estejam prontas.
- Sequência natural: **M0 → M1 → M2 → M3 → M4 → M5** (paralelizando quando o web já entregou as APIs necessárias).
- Sprint M2 (GPS) é a mais arriscada — começar com POC antes de comprometer prazo.

Quando começar uma sprint mobile, abrirei uma sessão dedicada no repo Flutter com o contexto desta documentação.
