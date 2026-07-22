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

## Pré-requisitos (antes de começar mobile) — todos ✅ resolvidos

| | Requisito | Estado atual |
|---|---|---|
| ✅ | Repo Flutter clonado e rodando local | `C:\Users\Diogo\Documents\bdt_uerj` — em uso desde M0 |
| ✅ | Versão do Flutter conhecida | **Flutter 3.41.9 · Dart 3.11.5** (stable). Detalhes em `docs/ARCHITECTURE.md §1` |
| ✅ | Endpoints da API e-Prefeitura mapeados | Todos sob `transporte/api/*` em `e-prefeitura/app/Config/Routes.php` (grupo mobile). Já em uso ativo pelas sprints M1-M5. |
| ✅ | Sprint 0 do plano original (papéis novos) aplicada | Entregue como **W0** do plano web (`SPRINTS_WEB.md`). Migration `2026-05-26-100000_InsertTransporteBdtRoles.php` + `App\Constants\TransporteRoles` + `PapeisSeeder`. Papel `Abrir BDT no App Mobile` disponível. |
| ✅ | Decisão sobre estado de gerenciamento | **StatefulWidget + setState nativo** — decisão por omissão desde M1, consolidada nas 5 sprints seguintes. Provou-se suficiente para o MVP (estado local por tela, sem estado global compartilhado). Migrar pra Provider/Riverpod/Bloc só se surgir necessidade real (ex.: estado compartilhado entre 3+ pages), o que não aconteceu ainda. |

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

## Sprint MSEC 🔒 — Hardening de segurança pré-piloto (~11h) — ⏳ planejada

**Origem:** análise de segurança pedida pelo usuário em **2026-07-21**
("como o app está lidando com rotas / usa CSRF / está tudo certo?").
A análise identificou 3 gaps críticos e 1 melhoria barata — não
estavam no plano original das sprints M0-M5 porque foram descobertos
depois, no exercício de auditoria do que já existia. Documentados
aqui como sprint dedicada porque o conjunto é coerente ("preparar
o app pra piloto real com condutores") e cabe em um bloco.

**Contexto do que **JÁ está OK** (não faz parte desta sprint):**
- HTTPS em produção com CA custom RNP ICPEdu no truststore
- CSRF corretamente desabilitado no grupo `transporte/api/*` (padrão
  pra API REST com Bearer — CSRF é pra sessão via cookie)
- Senha do usuário em `flutter_secure_storage` (Android Keystore)
- Guard de ownership nos endpoints críticos (`assertBdtPertence`,
  `findMeuPendente`, etc.)
- Captcha no login (opcional via env `MOBILE_LOGIN_CAPTCHA_ENABLED`)
- Release build força produção mesmo com `--dart-define=APP_ENV=...`

**Objetivo:** fechar os 4 gaps antes de rodar o app com condutores
reais em campo.

- ✅ **MSEC.1 — Token no `flutter_secure_storage`** (2026-07-21)
  - Novo `lib/services/token_storage.dart` (STORAGE) espelhando
    `CredentialsStorage`: `read/write/clear` + `_migrateLegacyIfNeeded`
    executado 1x na primeira leitura (copia `SharedPreferences.'token'`
    → secure storage e marca `auth_token_migrado_secure=true` para
    não repetir). Namespace novo `auth_token_secure` pra deixar óbvio
    que é local diferente.
  - 4 pontos de uso atualizados: `ApiClient.post()` (leitura por
    request), `AuthService.login` (grava após login OK),
    `AuthService.logout` (apaga junto com os demais prefs do usuário),
    `AuthService.verifyToken` (leitura no bootstrap), `LoginPage._bootstrap`
    (auto-login manter-conectado) e `BackgroundLocationService._drainQueue`
    (isolate do foreground service — `secure_storage` funciona porque
    `_onServiceStart` já inicializa binding + SSL). Import de
    `shared_preferences` removido do `login_page.dart` (não usava mais).
  - **Efeito:** token não fica mais legível em backup do device nem
    em dumps de storage plaintext. Complementa a senha (que já vivia
    no Keystore desde M1).

- 🟡 **MSEC.2 — Deprecar fallback `usuario_id` no body** (2 fases)
  - ✅ **Fase 1 (2026-07-21) — log WARN**: `BdtApiController::resolveUserId`
    agora loga `warning` sempre que cai no fallback do body, incluindo
    endpoint, IP e motivo (`tinha_token` = "token presente mas
    inválido/expirado" vs "sem Authorization header"). Mensagem
    prefixada com `[MSEC.2]` pra facilitar grep. Testado via curl:
    `WARNING - [MSEC.2] fallback usuario_id=46 usado em
    /transporte/api/bdt/dia (IP=..., motivo=sem Authorization header)`.
  - ⏳ **Fase 2 (após ~1 sprint sem WARN no log)**: retornar 401
    quando não houver token válido, ignorando `usuario_id` do body
    por completo. Decisão de bloquear vem da análise do log da
    fase 1 — se algum caminho mobile ainda depende do fallback,
    corrigir esse caminho antes de bloquear.
  - **Como observar em dev**: `docker compose exec apache
    tail -f /var/www/html/e-prefeitura/writable/logs/log-YYYY-MM-DD.log
    | grep MSEC.2`. Em produção, adicionar filtro no dashboard de
    logs (Sentry/CloudWatch/etc.) por prefixo `[MSEC.2]`.
  - **Efeito da fase 1:** zero mudança de comportamento observável
    pelo usuário; ganha-se rastreabilidade completa do uso do
    fallback antes de bloquear.

- ✅ **MSEC.3 — Rate limit no `POST /transporte/api/login`** (2026-07-21)
  - **Backend** (`AuthApiController::login`): `Services::throttler()`
    aplicado ANTES do captcha check e ANTES de qualquer query no
    banco. Regra: **10 tentativas por CPF por minuto**. Se estourar,
    retorna `429 TOO_MANY_REQUESTS` com header `Retry-After` e body
    `{status: 'TOO_MANY_REQUESTS', retry_after_seconds: N,
    message: 'Aguarde N segundos...'}`. Testado via curl (12 requests
    em sequência → 10 respondem CAPTCHA_ERROR, 11-12 respondem 429).
    Rate limit **só por CPF** (não por IP) — condutores da UERJ
    provavelmente compartilham NAT e limitar por IP bloquearia todos
    juntos. Chave de cache `login_cpf_<cpf>` (underscore em vez de `:`
    por causa dos reserved chars do CI4 CacheHandler).
  - **Mobile** (`AuthService` + `LoginPage`):
    - `LoginResult.throttledFailure(msg, retryAfter)` — novo caso.
    - `AuthService.login` detecta `status=TOO_MANY_REQUESTS` e converte.
    - `LoginPage`: novo state `_throttleSecondsLeft` + `Timer.periodic`
      decrementa 1s. Botão "Entrar" desabilitado (label vira
      "Aguarde Ns"). Banner vermelho com ícone timer + contagem
      regressiva acima do botão. Timer cancela no `dispose`.
    - Snackbar breve no início da penalidade + banner permanente.
  - **Efeito:** brute force de senha via CPF conhecido fica limitado
    a 10 tentativas/min (600/hora), inviável na prática. Captcha
    continua ativo como camada extra quando `MOBILE_LOGIN_CAPTCHA_ENABLED`.

- ✅ **MSEC.4 — Expiração + refresh do token** (2026-07-21)
  - **Backend** (`27b4d09d` no `feature/027-mobile-support`):
    - `TokenModel::gerarTokenComTTL(userId, tipo, ttlMinutos)` —
      variante aditiva do `gerarToken()` (que continua fazendo 2 dias
      fixo pra fluxo web). `revogar(token)` idempotente pra logout.
    - `AuthApiController::login` emite par `access` (15min) +
      `refresh` (24h se sem manter_conectado, 30d se marcado).
      Response tem `access_token` + `refresh_token` + `*_expires_in`;
      mantém chave legacy `token` = access, pra retrocompat.
    - `POST bdt/token/refresh` — rotação (revoga o refresh usado e
      emite par novo). Se refresh vazar e for usado, o legítimo é
      deslogado no próximo refresh.
    - `POST bdt/token/revogar` — best-effort logout server-side.
    - `BdtApiController::resolveUserId` valida `expira_em > NOW()`
      **em UTC** (bug encontrado no teste: MySQL grava UTC, PHP
      estava em BRT — comparação ficava incorreta).
    - `error(401, ...)` promove pra `status=TOKEN_EXPIRED` quando
      o motivo é token expirado (não confunde com 401 genérico).
    - Testado via curl: access válido = 200; expirado = 401
      TOKEN_EXPIRED; refresh válido = par novo; refresh já usado =
      401 REFRESH_INVALID.
  - **Mobile** (repo `bdt_uerj`):
    - `TokenStorage` ampliado com `readAccess/writeAccess/readRefresh/
      writeRefresh/writePair/clear` — access e refresh separados no
      Keystore. Migração transparente 1x mantida (v1 → v2).
    - `AuthService.login` recebe/guarda ambos + passa
      `manter_conectado` no payload pro backend decidir TTL do refresh.
    - `AuthService.logout` chama `bdt/token/revogar` best-effort
      ANTES de limpar local (falha silenciosa se sem rede).
    - `ApiClient.post` — se recebe `401 TOKEN_EXPIRED`, chama
      `_refreshTokens()` (dedupado via `Completer` — N requests
      concorrentes esperam 1 refresh), grava par novo, retenta a
      request original UMA VEZ. Se refresh também falhar, devolve
      a resposta 401 original (AuthService trata como sessão morta).
    - `LoginPage` passa `_manterConectado` na chamada.
  - **Efeito**: token de sessão nunca fica válido "pra sempre".
    Access curto (15min) limita janela de abuso se vazar; refresh
    rotacionado detecta uso concorrente por atacante.

- ✅ **MSEC.6 — Foto do condutor no avatar (LGPD-safe)** (2026-07-21)
  - **Origem:** feedback do usuário em 2026-07-21 sobre o avatar da
    AppBar. As iniciais do nome (v1) geram combinações
    constrangedoras (`CU` para Cláudio Ulisses, `PP`, `VD`, etc.).
    Correção **imediata** já feita: trocado por ícone `account_circle`
    genérico em ambos os avatares (trigger + card do menu). Esta
    tarefa MSEC.6 é a **entrega completa**: mostrar a foto real do
    condutor quando existir.
  - **Contexto do backend:** a foto vive em `doc_documentos` +
    `doc_referencias` (`tabela='condutores', id_referencia=condutor_id`),
    exposta hoje via `DocumentoService::getDocumentosByReferencia`.
    URL retornada pelo `driver->url()` é resolvida pelo storage
    driver do CI4 — não é uma URL pública "aberta". Foto é
    **dado pessoal (LGPD)** — precisa endpoint autenticado.
  - **Fazer no backend** (aditivo, wrapper do web):
    - Novo endpoint `POST /transporte/api/usuario/foto` (Bearer
      obrigatório, IGNORA `usuario_id` do body — condutor só pega
      a própria foto). Retorna `200 image/jpeg` (binário) OU
      `204 No Content` se sem foto cadastrada.
    - Header `ETag` = hash do arquivo, `Cache-Control: private, max-age=86400`.
    - Rota fora do padrão JSON — precisa de novo método helper
      no `BdtApiController` que devolva `Response` com bytes.
  - **Fazer no mobile**:
    - Novo `UsuarioFotoStorage` (categoria STORAGE): salva a foto
      em `getApplicationDocumentsDirectory()` (privado ao app no
      Android — não acessível por outros apps). Nunca em
      SharedPreferences. Guarda ETag ao lado.
    - `FotoService.obterFotoLocal(userId)` retorna `File?`;
      atualiza em background quando expira TTL (24h).
    - `AppNavbar` — o `Icon(Icons.account_circle)` do trigger
      vira `FutureBuilder<File?>` que, quando resolve, mostra
      `CircleAvatar(backgroundImage: FileImage(...))`; senão
      mantém o ícone genérico.
    - `AuthService.logout()` limpa o arquivo cached (senão
      próximo condutor logando vê foto do anterior por 1 seg).
  - **Segurança / LGPD checklist**:
    - [ ] Endpoint só via Bearer, NUNCA aceita `usuario_id` no body
    - [ ] `userId` sempre resolvido do token (defesa de ownership)
    - [ ] Retorna `204` (não `404 com erro descritivo`) se sem foto
      — não vazar "existe mas você não pode ver"
    - [ ] Cache em local privado do app; nunca `external_storage`
    - [ ] Foto NÃO entra em backups do device (Android:
      `allowBackup=false` já é o padrão de projeto)
    - [ ] Logout apaga arquivo local
  - **Risco:** baixo — endpoint aditivo, cache local isolado, se
    algo falhar cai no ícone genérico.
  - **Entregue**: backend `72a361a1` + mobile no próximo commit.
    Endpoint reusa `DocumentoService::getDocumentosByReferencia('condutores', condutorId)`
    (mesma fonte que a tela web do condutor usa — zero duplicação).
    Bearer only; userId sempre do token (ignora `usuario_id` do body).
    ETag/If-None-Match: 304 evita rebaixar bytes; 200 com mime real +
    `Cache-Control: private, max-age=86400`; 204 quando não tem foto.
    Mobile: `UsuarioFotoStorage` grava em `getApplicationDocumentsDirectory`
    (privado ao app no Android), `UsuarioFotoService` faz refetch com
    TTL 24h + revalidação por ETag + retry 1x se receber 401
    TOKEN_EXPIRED (integração com refresh do MSEC.4). AppNavbar
    renderiza `FileImage` quando cache existe, fallback pra
    `Icons.account_circle` senão. `AuthService.logout` chama
    `UsuarioFotoStorage.clear()` — próximo condutor logando não vê
    foto do anterior.

- ⏸️ **MSEC.5 — Certificate pinning** (opcional, adiado)
  - **Ganho:** protege contra MITM via CA maliciosa instalada no
    device (usuário confuso com Wi-Fi corporativo, atacante com
    acesso físico, etc.).
  - **Custo:** rotação de cert quebra o app até novo build+deploy
    na loja. **Não recomendado nesta fase** — priorizar MSEC.1-4.
    Reavaliar após o piloto.

> **Escopo técnico:** mudanças mobile no repo `bdt_uerj` (branch
> `main`) e backend no `e-prefeitura` (branch
> `feature/027-mobile-support`). **Não impacta a web em produção:**
> throttler no `/transporte/api/login` só atinge esse endpoint
> mobile; migration de `expires_at` é aditiva e default-nula (não
> muda comportamento web); novos endpoints `token/refresh` e
> `token/revogar` são novos.

---

## Sprint MUX 🎨 — Refinos UX pós-piloto (rolling) — 🟢 em andamento

**Origem:** conforme fui usando o app no meu Pixel (dogfooding), fui
achando pontos de UX que "funcionavam" mas incomodavam, e bugs que
passaram pelas M0-M5 mas só apareceram no uso real. Diferente da MSEC
(segurança) e das W+M (features do plano geral), aqui vive tudo que é
**refino contínuo** — pequenas mudanças pontuais, alinhamento com
comportamento do web, correções descobertas no meio do caminho.

Não tem "estimativa total" — vai crescendo. Sempre que fizer um
refino desses, registrar aqui em vez de deixar só no commit
(regra [[bdt_uerj_registrar_fora_de_escopo]]).

- ✅ **Bugfix MSEC.4 TZ mismatch** (2026-07-21, commit web `c7533ded`)
  — `TokenModel::gerarTokenComTTL` gravava `criado_em`/`expira_em`
  com `new DateTime()` (TZ do PHP = BRT no container) mas
  `BdtApiController::resolveUserId` lia como UTC. Resultado: tokens
  novos nasciam "3h no passado" e todo request retornava
  `401 TOKEN_EXPIRED`. Fix: `gmdate()` (UTC) na inserção. O
  `gerarToken()` legado do web não foi tocado — usa +2 dias, margem
  cobre o offset.

- ✅ **Bugfix MSEC.6 first-run** (2026-07-21, commit `867f46d`)
  — `UsuarioFotoService.obterCached()` chamava `refetch()` em
  background quando o cache estava vazio e retornava null imediato.
  O `AppNavbar` não tinha como saber quando o bg terminava — a foto
  só aparecia no segundo abrir da tela. Fix: `obterCached()` faz
  refetch em **foreground** quando cache vazio (aguarda); em bg
  só quando cache existe mas expirou TTL.

- ✅ **UI web `/admin/bdt/pre-bdt`** (2026-07-21, commit web `2b4e7704`)
  — a coluna "BDT" mostrava `<strong>ANO/NUMERO</strong>` + linha
  extra `ID #<n>` do id interno. `ID #N` é ruído — a chave humana
  é o `ano/numero` (e o protocolo `TRN-BDT-...`). Removida.

- ✅ **Refactor BDT — "Trechos do dia"** (2026-07-21, commit `8b606b6`)
  — a tela do BDT no mobile renderizava cada agenda como
  `ExpansionTile` separado ("Agenda das 00:00" — bug latente:
  `MIN(sd.data)` é DATE, sem hora, `_fmtTimeOnly` extraía
  `00:00`). Como um BDT é sempre 1 dia e o condutor quer a lista
  direta, achatamos: **lista única "Trechos do dia"** ordenada por
  hora (real se iniciou, senão prevista) com badge de status
  colorido (Pendente/Em andamento/Finalizado). Extraído helper
  `_trechoCard()` reutilizável — antes o mesmo bloco de ~130 linhas
  estava copiado em 2 loops. Total: -243 linhas líquido.

- ✅ **Backend `bdt/trechos/create` refatorado como wrapper**
  (2026-07-21, commit web `5db6ebd5`) — o `BdtApiService::criarTrechoExtra`
  reimplementava a criação com um insert que saía sem `fk_dia`
  (NOT NULL na tabela) — passava só porque o `allowedFields`
  filtrava campos silenciosamente. Agora é wrapper fino de
  `BdtViagemService::adicionarTrechoAvulso` (mesmo service que a
  `folha.php` do web usa) — cria solicitação avulsa + designação +
  dia corretamente. Aplicando [[bdt_uerj_reusar_codigo_web]].

- 🟡 **Bug reportado: "trecho do mobile some ao adicionar outro pela web"**
  (2026-07-21) — usuário relatou que ao aprovar Pré-BDT e depois
  clicar "Adicionar trecho avulso" na `folha.php`, o trecho do
  Pré-BDT some. Investiguei via script PHP reproduzindo o fluxo
  exato: **não reproduzi** — os 3 trechos coexistem no banco, no
  `bdt/detalhes` mobile e no sync. Aguardando `ano/numero` do BDT
  que ele viu bugar + sequência exata de cliques pra reproduzir.

- ✅ **Trecho extra — erros inline em vez de SnackBar invisível**
  (2026-07-22) — usuário reportou que "clicar em Cadastrar trecho
  extra não faz nada". Causa: o sheet é `isScrollControlled: true`,
  então o SnackBar do `ScaffoldMessenger.of(context)` era mostrado
  atrás do sheet + teclado — invisível. Fix: mesmos padrões dos
  outros sheets desta página — `String? formError` renderizado em
  `errorContainer` no topo do sheet, `bool busy` bloqueia rebound
  no botão, spinner in-line, snackbar de sucesso só após `Navigator.pop`
  do sheet (aí sim é visível).

- ✅ **Alerta odômetro saída < KM inicial** (2026-07-22) — validação
  client-side no sheet "Iniciar trecho": se o `odometro_saida` digitado
  for menor que a KM inicial efetiva (a que o condutor acabou de
  digitar OU a já persistida no BDT), abre um `_confirmDialog` de
  aviso. Botões: **Ajustar** (foca de volta no campo odômetro) e
  **Prosseguir assim mesmo** (segue direto pro `_confirmDialog` final
  de "Iniciar trecho?"). Filosofia: "quase tudo aqui é informativo"
  — nunca bloqueia. Se o condutor pulou a KM inicial, não valida
  (nada pra comparar).

- ✅ **Migration self-healing pro `distancia_km`** (2026-07-22, backend
  `feature/027-mobile-support`) — segunda vez esta semana que o dev DB
  ficou sem a coluna `trnsp_solicitacao_trechos.distancia_km` (bug já
  registrado no item "Iniciar/Finalizar trecho — retorno de exec
  ignorado"). A migration `2026-05-13-100000_AddDistanciaKm...` fica
  registrada como executada em `migrations` mas a coluna some em
  rollbacks/dumps parciais, e o `AgendaTrechosModel::find()` explode
  em toda request que usa. Fix: nova migration
  `2026-07-22-000001_EnsureDistanciaKmOnTrnspSolicitacaoTrechos` com
  `if (! fieldExists)` — no-op onde já existe, adiciona onde faltar.
  Idempotente, roda toda vez que `spark migrate` sobe.

- ✅ **KM inicial vira campo inline no sheet "Iniciar trecho"**
  (2026-07-22) — usuário reportou ANR ("BDT UERJ não está respondendo")
  reprodutível ao digitar no dialog "KM inicial" que abria por cima do
  `showModalBottomSheet` do iniciar-trecho. Padrão dialog-em-cima-de-sheet
  com autofocus + teclado numérico em Android é fonte conhecida de
  freeze da main thread. Fix: remove o dialog; se o backend informar
  `precisaPerguntarKmInicial=true`, o sheet mostra um `TextField`
  inline "KM inicial do BDT" **antes** dos campos de hora/odômetro,
  **obrigatório por padrão** (vazio bloqueia o botão Iniciar com
  erro no campo) — preserva a proteção do dialog antigo contra
  "passar batido". Escape-hatch: botão "Pular KM inicial (não sei o
  valor)" toggla um flag que desabilita o campo, mostra label
  "(pulada)" e libera o Iniciar mandando `null` pro backend. Alinha
  com o web, que também pede a KM na mesma tela sem popup.
  `_askKmInicialSePreciso` fica disponível pro `_openTrechoEditor`
  (outro sheet) até refatorar.

- ✅ **Iniciar/Finalizar trecho — retorno de exec ignorado + spinner
  travado** (2026-07-21) — usuário reportou "aqui sempre trava, não
  avança" no dialog KM inicial. Achei **três bugs sobrepostos** no
  `bdt_page`:
  1. `isBusyThis` era declarado no **outer builder** do
     `showModalBottomSheet` (só roda 1x), fora do `StatefulBuilder`.
     Chamadas de `setLocal(() => showProgress = true)` não
     reavaliavam a expressão — botão "Iniciar"/"Finalizar" continuava
     clicável durante o processamento e sem spinner. Movido pra
     dentro do `StatefulBuilder.builder`.
  2. Retorno de `BdtService.atualizarTrechoExecucao(...)` era
     ignorado nos dois sheets. Se o backend retornasse erro (ex:
     coluna faltante no dev DB — ver item abaixo), o app fingia
     sucesso: iniciava o tracking, fechava o sheet, mostrava
     "Trecho iniciado" — mas hora/odômetro nunca chegavam ao
     banco. Agora captura `okExec`; falso ⇒ mostra `formError`
     no próprio sheet e aborta antes de fechar.
  3. Causa raiz da manifestação "aqui sempre trava": este dev DB
     estava sem a coluna `trnsp_solicitacao_trechos.distancia_km`
     (migration `2026-05-13-100000_AddDistanciaKmToTrnspSolicitacaoTrechos`
     estava registrada como `batch=1` em `migrations` mas a coluna
     não existia — provavelmente restaurada de dump antigo). O
     `AgendaTrechosModel::find()` fazia `SELECT ..., st.distancia_km, ...`
     e falhava. Fix local: `ALTER TABLE ... ADD COLUMN distancia_km`.
     Sem impacto pra outros ambientes (migration existente cobre
     do zero).

---

## 🔀 Trabalho complementar (Web+Mobile) — encaixa nas sprints acima

Os 13 itens Web+Mobile precisam de implementação parcial no app. O esforço já está contado no plano web (sprint do "lado web") — aqui vai a **lista do que toca no Flutter**, organizada pela sprint web correspondente:

> ⚠️ **Redefinição do BDT (nova W7 web):** o web passou a tratar o **BDT como uma VIAGEM** (veículo+condutor, dia/período) que atende **uma ou mais solicitações** (M:N), com **local de embarque + assinatura por solicitação** dentro do BDT e o **local de embarque definido pelo admin**. A consolidação fica no **Painel de BDTs** (filtros + folha de despacho em PDF) — **não** há entidade "Programação" separada. Isso muda o modelo que o app consome: a **criação de BDT/Pré-BDT (M3)** e o **"BDT sem solicitação"** (abaixo) seguem o **BDT = viagem**. As referências "**Sprint N web**" abaixo usam a **numeração do plano original** — **não** mudam com a renumeração dos W-labels no web (a antiga W7 virou W8, …, W15 → W16; foi inserida a nova W7 = Redefinição do BDT).

### Da Sprint 1 web (Pré-BDT)
- ✅ Modal de informações de segurança no BDT — entregue como
  wrapper do serviço web existente (aplicando o princípio
  arquitetural). Botão "Informações de segurança" no
  `_openBdtActionsSheet` abre `SegurancaBdtDialog`, que consome
  `POST /transporte/api/bdt/seguranca/textos` — endpoint mobile
  novo que chama diretamente `SegurancaTextoService::getAtivosParaModal()`
  (mesma fonte do modal web `_modal_seguranca.php`, dos mesmos
  textos institucionais editáveis pelo admin em
  `/transporte/admin/seguranca/textos`). Widget preserva quebras
  de linha (`Text` já faz `pre-wrap` por padrão). Zero duplicação
  de conteúdo.

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
- ✅ Viagens avulsas no BDT (UX de adicionar) — base já existia
  (`_openTrechoExtraSheet` + `POST bdt/trechos/create`); o arquivo
  `trecho_extra_form_page.dart` estava vazio (deletado, sheet cobre).
- ✅ Refinar adição de trechos (gaps de UX) — **2026-07-21**
  - **Bug arqueológico**: o `BdtApiService::criarTrechoExtra`
    reimplementava a criação do trecho, mas o insert saía sem
    `fk_dia` (NOT NULL na tabela) — passava porque o
    `allowedFields` filtrava campos silenciosamente. Ao alterar
    a assinatura pra passar horários eu descobri que o insert
    nunca gravava nada de verdade nesses casos.
  - **Fix (aplicando [[bdt_uerj_reusar_codigo_web]])**: refatorado
    como **wrapper fino** de `BdtViagemService::adicionarTrechoAvulso`
    (mesmo método que o form web `folha.php` usa). Cria solicitação
    avulsa + designação + dia se necessário, insere trecho com ordem
    sequencial + saida/chegada/obs, anexa designação ao BDT.
    Guards mobile mantidos (`condutorIdOrFail` + `assertBdtPertence`).
  - **Backend**: `criarTrechoExtra` ganhou params opcionais
    `?string $horaSaida, $horaChegada, $obs` que viram
    `hora_saida/hora_chegada/obs` no array passado pro service web.
    Controller `BdtApiController::criarTrechoExtra` extrai esses
    campos do JSON e passa adiante.
  - **Mobile**: `BdtService.criarTrechoExtra` aceita 3 params opcionais.
    Sheet `_openTrechoExtraSheet` reescrito com StatefulBuilder:
    origem*, destino*, hora saída (TimePicker 24h), hora chegada
    (TimePicker 24h), observação — todos com labels/hints inspirados
    no form web. Valida "os dois horários ou nenhum" pra não gravar
    trecho meia-boca. Botão mais alto (48px), scroll pra caber teclado.

### Da Sprint 11 web (Anexo carga)
- ⏳ Anexo obrigatório de fotos para carga (validação no app)
  — depende do fluxo web de "carga" (Sprint 11 web)

### Da Sprint 15 web (BDT sem solicitação)
- ✅ Veículo/condutor reais ≠ agendados (UX de checkup no app) — 2026-07-21
  - Backend: novo endpoint `POST transporte/api/bdt/checkup`,
    wrapper fino de `BdtSemSolicitacaoService::checkup()` do web
    (mesmo service que o admin usa em "Criar BDT sem solicitação").
    Auth Bearer + `assertBdtPertence(bdtId, condutorId)` — só o
    próprio condutor do BDT pode consultar. Retorna
    `{ok, avisos, veiculo, condutor}` — não bloqueia (200 sempre).
  - Flutter: `CheckupBdt` model + `BdtService.checkup(bdtId)`
    chamado em paralelo com `detalhes(bdtId)` no `_load()`.
    Banner amarelo `_cardCheckupAvisos` no topo da `bdt_page`
    quando `avisos.isNotEmpty` (veículo em manutenção/inativo,
    CNH vencida). Falha de rede = banner some, BDT segue normal.
  - Aplica [[bdt_uerj_reusar_codigo_web]] — 0 lógica de negócio
    reimplementada, só embrulhada com auth mobile.

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
| MSEC | Hardening de segurança pré-piloto (nova, planejada) | 11 |
| MUX | Refinos UX pós-piloto (rolling, sem estimativa fixa) | — |
| **TOTAL mobile only** | | **301h** |
| Complementar Web+Mobile (estimativa) | | ~80-100h |
| **TOTAL Flutter** | | **~381-401h** |

> A diferença em relação aos 306h "Mobile" + 228h "Web+Mobile" do total geral é porque o esforço Web+Mobile é dividido entre os 2 repos: aprox. 50-60% no web (APIs, regras), 40-50% no mobile (UX).

---

## Como ler

- **Cada Sprint M é independente** das outras (exceto M0 e M1 que destravam estado de login).
- Podem ser executadas **em paralelo** com as sprints do web — desde que as dependências de backend estejam prontas.
- Sequência natural: **M0 → M1 → M2 → M3 → M4 → M5** (paralelizando quando o web já entregou as APIs necessárias).
- Sprint M2 (GPS) é a mais arriscada — começar com POC antes de comprometer prazo.

Quando começar uma sprint mobile, abrirei uma sessão dedicada no repo Flutter com o contexto desta documentação.
