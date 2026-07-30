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

## Sprint MSEC 🔒 — Hardening de segurança pré-piloto (~11h) — ✅ concluída (1 pendência)

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

> **Status (2026-07-30):** os 4 gaps originais fecharam, e a sprint
> **cresceu de 4 para 8 itens** — MSEC.5 (pinning), MSEC.6 (foto no
> avatar), MSEC.7 (fuso horário) e MSEC.8 (esqueci senha) nasceram
> depois, no uso real. Todos ✅. Resta **uma** pendência, no fim de
> MSEC.8: o `login()` ainda distingue "Usuário não encontrado." de
> "CPF ou senha inválidos.", o que permite enumerar CPFs. Fechar exige
> alinhar a mensagem com o time do web — é mudança de UX de uma tela
> que não é minha.

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

- ✅ **MSEC.2 — Deprecar fallback `usuario_id` no body** (2 fases)
  - ✅ **Fase 1 (2026-07-21) — log WARN**: `BdtApiController::resolveUserId`
    agora loga `warning` sempre que cai no fallback do body, incluindo
    endpoint, IP e motivo (`tinha_token` = "token presente mas
    inválido/expirado" vs "sem Authorization header"). Mensagem
    prefixada com `[MSEC.2]` pra facilitar grep. Testado via curl:
    `WARNING - [MSEC.2] fallback usuario_id=46 usado em
    /transporte/api/bdt/dia (IP=..., motivo=sem Authorization header)`.
  - ✅ **Fase 2 (2026-07-25)** — fallback REMOVIDO. `resolveUserId`
    retorna 0 quando não tem Bearer válido; caller devolve 401 via
    `error()`. Análise dos logs da Fase 1: todos os WARN vieram dos
    meus próprios testes via curl (o `ApiClient` do mobile sempre
    manda `Authorization: Bearer` via `TokenStorage.readAccess()`).
    Nenhum call site mobile depende do fallback — bloqueio seguro.
    - **Novo status distinguível**: `error(401,...)` agora retorna
      `TOKEN_EXPIRED` se `$this->tokenExpired` estava setado
      (mobile faz refresh via `ApiClient.refreshTokens`),
      ou `INVALID_TOKEN` caso contrário (mobile deve mandar pra
      login — `AuthService.verifyToken` já chama `logout()` em
      `httpStatus == 401`).
    - **Tentativa de fallback**: se veio `usuario_id` no body sem
      Bearer válido, loga `info` `[MSEC.2 F2] tentativa … RECUSADA`
      pra facilitar diagnóstico se algum caminho novo aparecer.
    - **Impacto em curl de dev**: `curl` PRECISA agora mandar
      `-H "Authorization: Bearer <token>"`. Pra pegar token dev:
      `docker exec -i mariadb mysql -u root -proot -sN eprefeitura -e 'SELECT token FROM tokens WHERE id_usuario=X AND expira_em > NOW() LIMIT 1;'`.
    - **Zero mudança no mobile** — o `ApiClient` já anexava Bearer
      em toda chamada; `verifyToken()` já tratava 401 corretamente.

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

- ✅ **MSEC.5 — Certificate pinning** (2026-07-28) — estava adiado por
  medo de a rotação de certificado brickar o app; **destravado** ao
  pinar a CADEIA em vez do certificado folha. Detalhes completos na
  seção "Da Sprint 15 web". Resumo:
  - `SecurityContext(withTrustedRoots: false)` com apenas a cadeia da
    RNP (intermediária + raiz GlobalSign R46) — remove as ~150 CAs do
    sistema, que era o vetor real de MITM. Validação no handshake, antes
    de qualquer byte sair do aparelho.
  - Pinar a cadeia (não a folha) faz a renovação anual do certificado
    passar sem release novo — que era exatamente o custo que motivou o
    adiamento. Intermediária vale até **19/11/2030**.
  - Escape hatch `--dart-define=SSL_PINNING=off` cobre o cenário
    remanescente (RNP migrar de CA sem aviso).
  - Verificado com openssl: produção OK, CA de fora recusada.

- ✅ **MSEC.8 — "Esqueci minha senha" no app** (2026-07-28) — o condutor
  não tinha como recuperar acesso pelo celular; dependia de alguém
  redefinir pelo admin web. Agora existe a tela `/esqueci-senha`
  (link no rodapé do login).
  - **Escopo deliberado**: o app **só dispara o e-mail**. A troca da
    senha continua no navegador, pelo link recebido — mesmo
    `LoginController::validateAccess` / `resetPassword` do web. Não
    replicamos a tela de redefinição no Flutter porque isso espalharia
    regra sensível (validação/expiração/consumo do token, política de
    senha) em dois lugares ([[bdt_uerj_reusar_codigo_web]]). O link abre
    no navegador do próprio celular, então o condutor resolve tudo sem
    trocar de aparelho.
  - **Backend**: `POST transporte/api/esqueci-senha` no
    `AuthApiController` — espelho do `forgotPasswordValidate` do web,
    trocando só a camada de entrada (hCaptcha → `SimpleCaptchaService`,
    HTML/CSRF → JSON). Gera token `reset_password` e chama o MESMO
    helper `enviar_email_reset_senha`, então o e-mail sai idêntico ao do
    fluxo web. Rota isenta de CSRF (cliente nativo não tem sessão) —
    a proteção é captcha + rate limit.
  - **Anti-enumeração**: o fluxo web responde "Usuário não encontrado."
    quando o CPF não existe, o que permite **enumerar CPFs** de
    servidores. O endpoint novo já nasce sem esse vazamento — existindo
    ou não o usuário, a resposta é byte a byte a mesma; os motivos reais
    (inexistente, cadastro incompleto, e-mail que não saiu) vão só pro
    log. Verificado: CPF real e CPF fake retornam resposta idêntica,
    mas só o real gera token no banco.
  - **Rate limit** 5/hora por CPF (mais apertado que os 10/min do login,
    porque aqui cada acerto dispara um e-mail — sem isso o endpoint vira
    ferramenta de flood na caixa de terceiros). Por CPF e não por IP,
    mesma justificativa do login (NAT compartilhado da UERJ).
  - **Mobile**: `AuthService.esqueciSenha()` reusando `LoginResult`
    (mesmos modos de falha: captcha e throttle) + `EsqueciSenhaPage`
    reusando o `CaptchaField` do login. Validação inline no padrão da
    casa. A tela **nunca afirma "e-mail enviado"** — repete a frase
    condicional do backend, senão anularia a proteção anti-enumeração.
  - ⚠️ **Pendência**: o `login()` ainda distingue "Usuário não
    encontrado." de "CPF ou senha inválidos.", então a enumeração
    continua possível por lá. Corrigir exige alinhar a mensagem com o
    time do web — fica como próximo item de MSEC.

- ✅ **MSEC.7 — Convenção de fuso horário end-to-end** (2026-07-24)
  — **Origem:** o app estava exibindo hora errada (~3h à frente do
  esperado) em marcos da jornada, listas de abastecimento e histórico
  de trechos. **Causa raiz** identificada por auditoria fim-a-fim:
  MariaDB armazena UTC; PHP CI4 rodava em BRT e usava `date('Y-m-d
  H:i:s')` (BRT wall-clock) pra gravar `datahora_*`; NOW() do banco
  respondia em UTC; e o Dart `DateTime.parse` de string sem TZ
  interpretava como local do device. O drift de 3h aparecia em
  qualquer comparação PHP↔SQL e em qualquer exibição no mobile.
  - **Backend (`e-prefeitura` — branch `feature/027-mobile-support`):**
    - Novo helper `app/Helpers/api_datetime_helper.php` com duas
      funções: `api_parse_datetime_utc($raw)` (aceita ISO com Z,
      ISO com offset, ou naive BRT — sempre devolve `Y-m-d H:i:s`
      UTC) e `api_now_utc()` (wrapper de `gmdate`).
    - `BdtApiService`, `PreBdtService`, `BdtJornadaService`
      carregam o helper no `__construct` via `helper('api_datetime')`.
      Todas as gravações de `data_hora`/`data_registro`/`updated_at`/
      `datahora_marco` passaram de `date()` para `api_now_utc()` ou
      `api_parse_datetime_utc()`.
    - `AbastecimentoBdtService` e `ManutencaoBdtService` NÃO
      reprocessam mais a string entregue pelo caller (`strtotime`
      + `date` no fuso do servidor desconvertia UTC para BRT).
      Docstring inline explica.
    - `TokenModel` do e_Transporte: `getNow()` retorna
      `new DateTime('now', new DateTimeZone('UTC'))`; leitura de
      `expira_em` também usa `DateTimeZone('UTC')`. Mesmo padrão
      já adotado pelo `TokenModel` genérico no bugfix MSEC.4
      (2026-07-21) — agora replicado no módulo Transporte.
    - Migration one-off
      `2026-07-24-160000_ConvertTrnspBdtTimestampsBrtToUtc.php`
      soma +3h nas colunas operacionais históricas do módulo BDT
      (marcos do BDT, execução de trechos, abastecimento/manutenção/
      ocorrência/localização, assinaturas). Idempotente via tabela
      `trnsp_tz_migration_applied` (nunca dobra). Escopo deliberadamente
      mínimo — NÃO toca `created_at`/`updated_at` (auditoria, não é
      exibida ao usuário e o desvio de 3h não afeta o UX).
  - **Mobile (`bdt_uerj` — branch `main`):**
    - `DateFmt` (`lib/utils/date_fmt.dart`) ganhou `apiIsoUtc(DateTime)`
      que devolve `YYYY-MM-DDTHH:MM:SSZ` — formato canônico para
      todo payload de datetime que sai do app.
    - `DateFmt.dtCompact`, `hora`, `dataHoraBr` passaram a interpretar
      naive strings da API como UTC (adicionam `Z` antes do parse) e
      converter pra local do device com `toLocal()`. Assim `17:30 UTC`
      no banco aparece como `14:30` na tela em BRT.
    - `LocationService.getLocPayload` e `BackgroundLocationService`
      gravam `captured_at` como `.toUtc().toIso8601String()`.
    - `bdt_page._apiDateTimeFromHm`, `bdt_form_page._fmtApiDateTime`,
      `pre_bdt_form_page._apiHora` refatoradas para emitir ISO UTC
      via `DateFmt.apiIsoUtc`.
    - `BdtResumo.fromJson.parseDt` interpreta ISO da API como UTC.
    - Listas de abastecimento e manutenção no BDT form passam
      `data_hora`/`data_hora_inicio` por `DateFmt.dataHoraBr`
      antes de exibir (antes: subtitle era `Text(dh)` bruto).
  - **Preservação de compatibilidade web:** o helper `api_parse_datetime_utc`
    aceita input naive BRT como fallback, então clientes web antigos
    (formulários admin CI4 que enviam wall-clock BRT) continuam
    funcionando sem mudança. A migration one-off só ajusta
    dados históricos; escritas novas do web via CRUD admin
    continuam BRT wall-clock — o AbastecimentoBdtService/ManutencaoBdtService
    passam a string direta pro DB sem reprocessar (não mais
    desconverte UTC↔BRT). Regra [[bdt_uerj_mobile_nao_quebra_web]].
  - **Convenção documentada em memória** [[bdt_uerj_convencao_tz]] para
    guiar futuros services/pages sem repetir a análise.

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

- ✅ **Remove card duplicado de Marcos do BdtFormPage** (2026-07-24)
  — O Formulário do BDT tinha um card "Marcos da Jornada" duplicado, com:
  (a) só 3 dos 4 marcos (faltava "Hora de saída" adicionado na Sprint 5
  W+M), (b) dialog simplificado que só pedia observação e gravava
  sem assinatura, (c) versão anterior aos ajustes de UX das últimas
  sprints. A versão CANÔNICA vive em `ValidacaoInicioPage` (rota
  `/validacao/inicio`, acessível pelo sheet "Ações" do BdtPage) —
  4 marcos completos + fluxo M4 com assinatura via `AssinaturaMarcoPage`.
  Removidos: `_cardMarcosJornada`, `_rowMarco`, `_registrarMarco`,
  `_reassinarMarco`, `_bdtPermiteMarcos`, `_proximoMarcoIniciaBdt`,
  `_marcoLiberado`, `_marcoPodeRegistrar`, `_fmtDatahoraBr`, todos
  os maps de state (`_marcoDatahora`, `_marcoAutor`, `_marcoAssinaturaSvg`,
  `_marcoSignatarioTipo`, `_marcoObservacao`, `_registrandoMarco`,
  `_bdtStatus`) e os labels/ícones estáticos. O `_load` deixou de
  chamar `BdtService.estadoJornada` (só usado por esse card). Zero
  regressão — se um dia quiser reintroduzir, é diff limpo pra
  reverter. `AssinaturaMarcoPage` e `AssinaturaPreview` seguem
  registrados (usados pela `ValidacaoInicioPage`).

- ✅ **Sprint 18 W+M — Fotos de Abastecimento & Manutenção no mobile** (2026-07-24)
  — **Origem:** completar a paridade web↔mobile de anexos do BDT. Ocorrência já
  tinha upload de foto desde a Sprint 17; Abastecimento e Manutenção só tinham
  os campos textuais. Auditoria pré-execução também revelou 2 bugs latentes.
  - **Reuso máximo do módulo de documentos web:** todo upload no backend passa
    por `DocumentoService::saveDocumentoComReferencia` (fonte única) — os
    arquivos ficam em `doc_documentos` + `doc_referencias` + naming pattern
    padrão de `WRITEPATH/uploads/documentos/`. Os services específicos por
    fluxo (`AbastecimentoFotoService`, `ManutencaoFotoService`) já existiam pro
    web — a API mobile virou wrapper fino em cima deles, sem re-implementar.
  - **Backend — trait pra eliminar boilerplate:** novo
    `App\Controllers\e_Transporte\Api\Traits\FotoDocumentoTrait` com 3
    helpers: `respondUploadFoto` (valida UploadedFile + delega ao service +
    JSON padronizado), `streamFotoDocumento` (binário + ETag +
    `If-None-Match`/304), `excluirFotoDocumento` (ownership check + delete).
    Cada endpoint específico fica com ~10 linhas (guard de ownership + qual
    service chamar). Endpoints novos:
    - `POST bdt/abastecimentos/fotos/{upload,listar,obter,excluir}` +
      `bdt/abastecimentos/tipos-fotos` (catálogo dos 5 subtipos, sem Nota
      Fiscal que tem input próprio).
    - `POST bdt/manutencoes/fotos/{upload,listar,obter,excluir}` — upload
      aceita `fase=antes|depois` que roteia pra `salvarAntes`/`salvarDepois`.
    - Upload de abastecimento aceita `is_nota_fiscal=1` (roteia para
      `salvarNotaFiscal`) ou `fk_tipo_foto` (subtipo do catálogo).
  - **Backend — guards no BdtApiService:** `assertAbastecimentoDoCondutor` +
    `assertManutencaoDoCondutor` — resolvem registro → BDT → condutor, evitam
    id forjado no payload (mesmo padrão de `assertBdtPertence`).
  - **Mobile — cliente genérico:** novo `lib/services/foto_documento_client.dart`
    parametrizado por endpoint + refField. `OcorrenciaService` (fotos),
    `BdtService` (fotos de carga), `AbastecimentoFotoService` e
    `ManutencaoFotoService` viraram thin wrappers que instanciam o cliente
    com os endpoints corretos. Zero código HTTP/multipart/parse duplicado.
    `AbastecimentoFotoService.listarTiposFoto()` tem fallback local (5
    subtipos canônicos) se a chamada falhar — igual ao dos tipos de
    combustível (dropdown nunca vazio).
  - **Mobile — widgets generalizados:** `FotoOcorrenciaThumb` (Sprint 17)
    virou shim sobre novo `FotoDocumentoThumb(docId, fetcher, cacheNamespace)`.
    Cache por `(cacheNamespace, docId)` evita colisão entre fluxos.
    `FotoViewerPage` aceita agora `FotoViewerArgs` (docId + fetcher) ou `int
    docId` (retrocompat). Conserta bug latente em `pre_bdt_form_page` onde as
    fotos de carga baixavam via endpoint de ocorrência (funcionava só porque
    o listar retornava metadata correta, mas obter/excluir travariam).
  - **Mobile — UI "botoeira por tipo":** novo widget reusável
    `lib/widgets/fotos_bdt_section.dart` com chips (Odômetro / Bomba /
    Tanque / Cartão / Outros + botão destacado "Nota Fiscal" no
    Abastecimento; Antes / Depois na Manutenção). Cada chip pré-seleciona o
    tipo antes de abrir a câmera → reduz erro humano no dia a dia sem exigir
    classificação pós-captura. Miniaturas com badge do tipo. Existentes
    (do backend) e pendentes (memória) num único grid.
  - **`nota_fiscal` do Abastecimento:** manteve como campo texto (número/série,
    paridade com web) e ganhou botão destacado "Nota Fiscal" na seção de
    fotos que rota pro endpoint `salvarNotaFiscal` (aceita imagem no mobile;
    PDF só via web, decisão MVP).
  - **Bugs pré-existentes corrigidos como parte do escopo:** os endpoints
    `obter`/`excluir` de foto de Ocorrência (Sprint 17) e Carga (Sprint 11)
    usavam `where('tabela', ...)` / `->referencia_id`, mas as colunas reais
    de `doc_referencias` são `tabela_referencia` / `id_referencia`. Falha
    silente — como o fluxo comum era upload+listar (que usa outra query),
    passou despercebido. Corrigido nos 4 call sites junto com este commit
    (mesmo bug que travou o "aprovar Pré-BDT" há pouco — commit
    `5aacffdc5`).
  - **Sem migration nova.** Todo o schema (`trnsp_abastecimento_tipo_foto`,
    `doc_tipos.FOTO_*`, `doc_documentos`, `doc_referencias`) já existia.

- ✅ **Sprint 18.1 e 18.2 — editar ocorrência, galeria e telas de detalhe**
  (2026-07-23/24, commits `68a7119`, `071cfd3`, `f2c1c15`) — desdobramentos
  da 18 que só apareceram no teste com o emulador.
  - **Crash ao editar ocorrência** (18.1): `DropdownButtonFormField`
    assertava *"Either zero or 2 or more DropdownMenuItems were detected
    with the same value: 4"*. No primeiro frame o `FutureBuilder` ainda
    não tinha os tipos, então `items` só continha o placeholder e o
    `initialValue=4` não casava com item nenhum. Fix: quando `_tipoId`
    está setado mas fora do catálogo atual, injeta um item invisível
    `Tipo #N (fora do catálogo)`; o `setState` reconcilia quando o Future
    resolve e o placeholder some.
  - **`FotoGaleriaPage`** (18.2, rota `/foto/galeria`) substitui a
    `FotoViewerPage` de foto única pelo caso comum: `PageView` horizontal,
    contador `N/M · Título` no header, legenda com o subtipo da foto atual
    (Hodômetro / Antes / Nota Fiscal…), chevrons pra navegar e
    pinch-to-zoom via `InteractiveViewer`. Carrega sob demanda.
  - **Cards do BDT perdem a tira de miniaturas** — no teste real ficou
    poluído. Trocada por trailing padronizado `[n fotos] [Ver] [Editar]
    [Excluir]`, reusado nos 3 cards via `_acoesDoRegistro`. Daí nasceram
    `AbastecimentoDetalhePage` e `ManutencaoDetalhePage`, irmãs da
    `OcorrenciaDetalhePage`.
  - **`AssinaturaMarcoPage` no padrão dos outros forms**: o SnackBar
    genérico *"Falha ao registrar marco."* mascarava o erro real do
    backend (coluna faltando, ordem inválida, BDT que não aceita marco).
    Agora banner `errorContainer` no topo + `errorText` inline no nome, e
    a mensagem real chega ao usuário — que pode agir (ex.: rodar
    `php spark migrate` se aparecer coluna faltando).

- ✅ **"Odômetro" → "Hodômetro" nas strings visíveis** (2026-07-24, commit
  `ec2d29e`) — preferência da equipe pela grafia dicionarizada. Trocado nos
  labels, dialogs, snackbars e resumos de `bdt_page` e `bdt_form_page`.
  **Deliberadamente NÃO trocado**: identificadores de código (`odoCtrl`,
  `_asOdo`), chaves de payload da API (`odometro_km`, `odometro_saida`) e o
  subtipo `"Odometro"` do catálogo `trnsp_abastecimento_tipo_foto` — este
  último exigiria seed migration + update das descrições já gravadas em
  `doc_documentos`, custo desproporcional pra um rótulo.
  - ⚠️ **Este documento ainda escreve "odômetro"** nas entradas anteriores
    a esta data. Não reescrevi o histórico: as entradas descrevem o que
    era verdade quando foram escritas. Da UI, vale "hodômetro".

- ✅ **Select de combustível nunca vazio** (2026-07-24, commit `fd0676f`) —
  o dropdown "Tipo combustível" abria vazio no emulador, por **duas** causas
  independentes: (a) o `DropdownButtonFormField` não remonta só porque
  `items` mudou, então ficava preso ao estado inicial `items=[]` do loading
  — resolvido com `key` derivada de `items.length`; (b) se
  `POST /bdt/abastecimentos/tipos` falhasse (rede instável, token expirado,
  404), o condutor ficava sem opção nenhuma — agora há fallback local com os
  6 tipos canônicos espelhando `App\Constants\CombustivelTipo`. Tipo novo
  cadastrado pelo admin só aparece online; offline mostra os 6 que cobrem a
  frota. O log de warn passou a incluir `http_status` pra diagnosticar por
  que caiu no fallback.

- ✅ **Alinhamento de Hodômetro e Litros na mesma linha** (2026-07-24, commit
  `cd2cde6`) — os dois campos da `Row` ficavam com bases desalinhadas porque
  só o Hodômetro tinha `helperText: 'Opcional'` (reserva ~18px). Fix:
  `helperText: ' '` no Litros — reserva a mesma altura sem texto visível.

- ✅ **Limpeza de warnings pré-existentes** (2026-07-25, commit `b77f926`) —
  campos guardados e nunca lidos poluíam o `flutter analyze` desde sprints
  anteriores: `_two` do `BdtFormPage` (morto após a migração pro `DateFmt`),
  `_bdtId`/`_trechoId` do `GpsLiveService` (só `_agendaId` é lido no callback
  do timer) e a atribuição `_fotosCargaLoader` do `PreBdtFormPage`. Zero
  mudança de comportamento. Comentário no `GpsLiveService` registra o que
  eram, pra ressuscitar rápido se um dia `status()` precisar expor BDT/trecho
  ativo.

- ✅ **`.gitattributes` + normalização pra LF** (2026-07-24, commit `b06d8a8`)
  — sem `.gitattributes`, o mesmo diretório era visto de forma diferente pelo
  Git-for-Windows (`autocrlf=true`) e pelo Git dentro do WSL (`autocrlf`
  vazio): o WSL enxergava **todos** os `.dart` como modificados, impedindo
  commit limpo de lá. Fix: `* text=auto eol=lf` — repo sempre em LF, checkout
  respeitando o `autocrlf` local (Windows continua com CRLF no disco, sem
  mudança visível). Exceções explícitas: `*.bat/.cmd/.ps1` sempre CRLF,
  binários marcados `binary`, `*.pem` forçado LF (o bootstrap SSL espera),
  `gradlew` LF e `gradlew.bat` CRLF. O `--renormalize` reescreveu 46 arquivos
  no índice (4749 inserções / 4749 remoções, zero mudança de conteúdo).
  - Este é o episódio que originou a regra [[bdt_uerj_git_backend_pelo_wsl]]:
    no **backend** o problema é pior (não tem `.gitattributes` equivalente),
    então git de lá roda sempre por dentro do WSL.

- ✅ **Migrations: trait de bypass do cache de metadados do CI4** (2026-07-24,
  backend `bd6571d0` + `7a2e0056`) — dois `migrate:refresh` seguidos
  quebraram, primeiro com `Unknown column 'datahora_hora_saida'`, depois com
  `Duplicate column name 'distancia_km'`. **Mesma causa**: no `refresh` todas
  as migrations rodam no MESMO processo PHP e na mesma conexão, e o
  `fieldExists`/`tableExists` do CI4 memoiza metadados em `dataCache`. Se uma
  migration anterior consultou a tabela antes de a coluna existir, o cache
  congela — e a migration seguinte ou pula o trabalho (false-negative) ou
  tenta recriar o que já existe (true stale). Fix generalizado no trait
  `App\Database\MigrationSchemaTrait` (`columnExistsSafe`, `tableExistsSafe`,
  `indexExistsSafe` consultando `INFORMATION_SCHEMA` direto, mais
  `resetSchemaCache`). Duas migrations refatoradas pra usá-lo.

- ✅ **`AgendaTrechosModel::find()` resiliente a `distancia_km` ausente**
  (2026-07-22, backend `7150cbb2`) — o **fix definitivo** do sintoma
  registrado acima em "Iniciar/Finalizar trecho — retorno de exec ignorado".
  Mesmo com a migration self-healing, o dev DB perdeu a coluna duas vezes na
  mesma semana, e todo fluxo que passa pelo `find()` explodia — incluindo
  `atualizarTrechoExecucao`, que produzia o sintoma confuso "Trecho iniciado,
  mas hora/hodômetro não foram salvos". Agora o `find()` checa `fieldExists`
  antes de selecionar e, faltando, devolve `NULL AS distancia_km` —
  indistinguível de valor nulo no banco, que o consumidor já trata. Zero
  impacto quando a coluna existe; testado nos dois cenários.

- ✅ **Padronização UX pós-teste — 3 ajustes** (2026-07-24)
  - **Dashboard sem "Histórico de ocorrências"** — o card
    "Ferramentas" do home ganhava um único atalho para o histórico
    institucional, mas isso criava pressão de simetria (por que só
    ocorrências e não abastecimentos/manutenções?). Como os três
    históricos já são acessíveis pelo Formulário do BDT, o card
    inteiro foi removido do dashboard (`_cardFerramentas` deletado).
    A rota `/ocorrencias/historico` e a `HistoricoOcorrenciasPage`
    ficam registradas — reintroduzível quando a decisão sobre
    histórico institucional for revisitada.
  - **Botão "Adicionar" em todas as seções do BDT** — Abastecimentos
    e Manutenções usavam "Adicionar", Ocorrências usava "Registrar".
    Unificado como "Adicionar" (o rótulo dominante). Remove o
    texto "O histórico completo fica em Menu → Ferramentas → …"
    que apontava pro card recém-removido do dashboard.
  - **Botão de contato da Seguradora no modal "Informações de
    segurança"** — em sinistro o condutor precisa acionar rápido
    a seguradora. Novo endpoint aditivo `POST bdt/seguro` retorna
    a apólice mais recente do veículo do BDT + dados da seguradora
    (nome, apólice, vigência, telefone1-3, whatsapp1-2, email, site).
    Reusa `VeiculoApoliceModel::getByVeiculo` + `SeguradorasModel::getById`
    do web — zero duplicação. `SegurancaBdtDialog.show(context, bdtId:)`
    passa a mostrar seção "Seguradora / Apólice" no TOPO do modal
    (contatos via `ContatoAutoLink` já parseiam tel/wa/email virando
    link clicável). Se o veículo não tem apólice, a seção não é
    renderizada (silent absence).

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

- ✅ **Odômetro saída/chegada opcional com alerta** (2026-07-22) — os
  sheets "Iniciar trecho" e "Finalizar trecho" **bloqueavam** o botão
  quando o campo odômetro estava vazio (erro `odoError` inline).
  Trocado por `_confirmDialog` — se vazio, mostra "Sem odômetro de
  saída/chegada", explicando que é importante pro cálculo de KM, com
  botões **Informar agora** (foca no campo) e **Iniciar/Finalizar sem
  odômetro** (segue). O `_confirmDialog` de resumo mostra "Odômetro:
  (não informado)" nesse caso. No `atualizarTrechoExecucao`, o campo
  `odometro_*` só é enviado se preenchido — vazio ⇒ nem manda ⇒
  backend deixa NULL sem exceção. Filosofia "informar, não bloquear".

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
- ✅ **Marco HORA DE SAÍDA** (2026-07-22) — 4º marco adicional, saída
  efetiva do veículo após o embarque do passageiro. Implementado como
  extensão do padrão já existente (partida / apresentacao /
  embarque_passageiro) — nenhum arquivo novo, só extensão dos 3 pontos
  já parametrizados por constante.
  - **Backend** (`feature/027-mobile-support`):
    - Migration idempotente `AddDatahoraHoraSaidaToTrnspBdt` adiciona
      `trnsp_bdt.datahora_hora_saida DATETIME NULL` (segue nomenclatura
      `datahora_<slug>` das outras 3 colunas de marco).
    - `BdtModel::$allowedFields` — inclui a coluna nova.
    - `BdtJornadaService`: constante `MARCO_HORA_SAIDA = 'hora_saida'`
      + entrada em `COLUNA_POR_MARCO` + entrada em `ORDEM` (última).
      A `validarOrdem()` genérica já garante que o 4º só pode ser
      registrado depois do 3º.
  - **Mobile**:
    - `BdtService.marcosValidos` — inclui `'hora_saida'`.
    - `ValidacaoInicioPage._cardMarcos` — 4ª linha `('hora_saida',
      'Hora de saída')`. `AssinaturaMarcoPage` já é agnóstica de marco
      (recebe o slug via route arguments), sem alterações.
  - Endpoint `POST bdt/jornada/estado` agora devolve `hora_saida` no
    map de marcos — testado via curl (`{"marcos":{...,"hora_saida":
    {"datahora":null,"assinatura":null}}}`).

### Da Sprint 6 web (Cargas)
- ✅ **Cancelar/redirecionar BDT por divergência de carga** (2026-07-25) —
  condutor no destino descobre que a carga real não bate com o declarado
  → REGISTRA divergência pelo mobile → admin decide no web
  (`cancelar` reabre solicitação pra reagendamento; `prosseguir` mantém).
  100% wrapper thin sobre o motor W10 (`MotorDivergenciasService`) que
  já rodava no web — zero migration, zero service novo.
  - **Backend** (feature/027-mobile-support):
    - Novos endpoints em `BdtApiController`:
      - `POST bdt/divergencias/registrar` — chama
        `MotorDivergenciasService::registrarCarga`. Backend classifica
        `carga` vs `carga_nao_prevista` sozinho. Regra
        [[bdt_uerj_sem_travas_so_alertas]]: se já tem divergência
        pendente do mesmo tipo, devolve a existente com
        `ja_existia=true` (não é erro — cliente mostra alerta e
        permite anexar fotos novas).
      - `POST bdt/divergencias/listar` — wrapper de
        `DivergenciaRepository::getByBdt` + subquery de `qtd_fotos` em
        `doc_referencias` (evita N+1 no mobile).
      - `POST bdt/divergencias/fotos/{upload,listar,obter,excluir}` —
        reusa `FotoDocumentoTrait` + `DocumentoService`; grava em
        `doc_documentos` + `doc_referencias` com
        `tabela_referencia='trnsp_divergencias'`.
    - Novo guard `BdtApiService::assertDivergenciaDoCondutor` — resolve
      divergência → BDT → condutor (mesmo padrão de abastecimento/manutenção).
    - **Bug pré-existente corrigido junto:**
      `BdtApiController::encerrarBdt` **não** disparava
      `MotorDivergenciasService::detectarSeguro` (o web dispara). Deixava
      divergências auto-detectáveis (passageiros faltando) passarem batido
      quando o condutor encerrava pelo app. Corrigido com try/catch
      defensivo (não bloqueia o encerramento se o detector falhar).
  - **Mobile** (main):
    - Novo `DivergenciaService` (categoria API) + `DivergenciaResumo` + `RegistrarDivergenciaResult`.
    - Nova `RegistrarDivergenciaPage` (`/bdt/divergencia/nova`): campo
      descrição obrigatório, medidas reais opcionais (peso, comprimento,
      largura, altura), fotos-prova opcionais. Se backend responde
      `ja_existia`, mostra banner amarelo (alerta, não trava) e sobe
      as fotos pra divergência existente.
    - Novo card "Divergências de carga" em `BdtFormPage`: lista com
      ícone colorido por decisão (amarelo=pendente, verde=prosseguido
      pelo admin, vermelho=cancelou BDT). Tap abre a page detalhe
      compartilhada `/registro/detalhe` — sem botões Editar/Excluir
      (só admin decide via web).
    - Foto da divergência entra no fluxo genérico da `FotoGaleriaPage`
      (swipe + legenda).
  - **Regra aplicada:** [[bdt_uerj_sem_travas_so_alertas]] — condutor
    consegue registrar SEMPRE, alertas quando há situação incomum, sem
    bloqueios de fluxo.



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
- ✅ **Anexo obrigatório de fotos para carga no Pré-BDT** (2026-07-24) —
  o condutor agora declara carga (com fotos obrigatórias) direto no
  Pré-BDT do mobile. Antes só o form web (`folha.php` / `requests`)
  tinha essa capacidade. Alinhado com ARCHITECTURE.md §0 (aditivo),
  §4.7 (Page), §4.8 (Widget reuso — `FotoOcorrenciaThumb` compartilhado).
  - **Desafio arquitetural**: web grava carga em `trnsp_solicitacoes`
    + fotos em `documentos` com `tabela=trnsp_solicitacoes`. Mobile
    vai direto pra `trnsp_bdt` (a solicitação só materializa quando
    admin aprova). Solução aditiva:
    - Migration `AddCargaColumnsToTrnspBdt` — 6 colunas nullable em
      `trnsp_bdt` (`tem_carga`, `carga`, `carga_peso_kg`,
      `carga_comprimento_m`, `carga_largura_m`, `carga_altura_m`).
      Idempotente (checa `fieldExists`).
    - `PreBdtService::criarPeloCondutor` / `atualizarPeloCondutor`
      aceitam e persistem os campos.
    - `PreBdtService::materializarSolicitacao` (aprovação): copia
      carga* pro `trnsp_solicitacoes` E faz `UPDATE doc_referencias
      SET tabela=trnsp_solicitacoes, referencia_id=solId WHERE
      tabela=trnsp_bdt AND referencia_id=bdtId` — migra as fotos pro
      caminho canônico web sem duplicar.
  - **4 endpoints mobile** (padrão fotos ocorrência, tipo `CARGA`):
    - `POST bdt/pre-bdt/fotos-carga/upload` (multipart)
    - `POST bdt/pre-bdt/fotos-carga/listar`
    - `POST bdt/pre-bdt/fotos-carga/obter` (Bearer + ETag)
    - `POST bdt/pre-bdt/fotos-carga/excluir`
    Ownership: `bdt->criado_por == user do token`.
  - **`BdtService`** — 4 métodos novos (`listar/obter/upload/excluir
    FotoCarga`) + `criarPreBdt/atualizarPreBdt` ganharam parâmetros
    opcionais `temCarga`, `carga`, `cargaPesoKg`, etc.
  - **`PreBdtFormPage`** — novo card "Vai levar carga?" com switch;
    quando ligado, expõe descrição (required *), peso/dimensões
    opcionais, e o `_blocoFotosCarga` com bottom sheet
    câmera/galeria + preview em grid (fotos pending + fotos já
    persistidas na edição, com X pra remover). Validação inline
    obrigatória: descrição não-vazia + ≥1 foto (mesma regra do
    `TransporteTrait::validarFotosCargaObrigatorias` do web).
    Upload em batch DEPOIS de criar/atualizar (precisa do
    `bdt_id`); falha em uma foto não invalida o Pré-BDT — snackbar
    avisa "X ok, Y falhou". `PreBdtPendente` model ganha os
    campos de carga pra pré-preencher no modo edição.

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

- ✅ **Criar BDT direto pelo app** (2026-07-25) — condutor pode
  agora criar BDT AVULSO no mobile (sem passar por Pré-BDT +
  aprovação), pra casos de emergência ou tarefa pontual.
  - **Backend**: 2 endpoints novos no `BdtApiController`,
    ambos wrappers finos do `BdtSemSolicitacaoService` do web
    ([[bdt_uerj_reusar_codigo_web]] — 0 lógica reimplementada):
    - `POST bdt/checkup-veiculo` — variante do `checkup(bdtId)` que
      recebe `veiculo_id` (+ `condutor_id` opcional, forçado ao próprio
      se enviado), pra rodar o checkup ANTES de existir BDT. Reusa
      `BdtSemSolicitacaoService::checkup($veiculoId, $condutorId)`.
    - `POST bdt/criar-sem-solicitacao` — recebe `veiculo_id` e
      opcional `data_referencia` (default: hoje). Força
      `condutor_id = próprio` (guard via `condutorIdOrFailPublic`);
      chama `BdtSemSolicitacaoService::criar()` do web — mesma
      transação (solicitação sintética + BDT já em EM_ABERTO +
      designação + auditoria `CRIAR_BDT_SEM_SOLICITACAO`). Retorna
      `{bdt_id, protocolo, avisos}`. Nova rota `bdt/criar-sem-solicitacao`
      no `Routes.php` (aditivo, [[bdt_uerj_mobile_nao_quebra_web]]).
  - **Mobile**: `BdtService.checkupVeiculo(veiculoId, condutorId?)` +
    `criarBdtSemSolicitacao(veiculoId, dataReferencia?)`. Nova
    `CriarBdtPage` (`lib/pages/criar_bdt_page.dart`, rota
    `/bdt/criar-direto`) — form com `VeiculoAutocomplete` (reuso
    do widget existente) + `DatePicker` (default hoje) + card com
    checkup em background. Banner AMARELO com avisos aparece se
    houver, mas botão "Criar BDT" fica sempre habilitado —
    [[bdt_uerj_sem_travas_so_alertas]] (sistema alerta, não bloqueia).
    Sucesso → `pushReplacementNamed('/bdt', arg: bdtId)`, condutor
    já pode iniciar trecho. `HomePage` ganha bottom sheet com 2
    opções — "Novo Pré-BDT" (padrão, passa por aprovação) e
    "Criar BDT direto" (emergência) — disparado pelo FAB genérico
    "Criar" (antes só existia FAB direto pro Pré-BDT).

- ✅ **Criar BDT direto — gate RBAC + seleção de condutor** (2026-07-26)
  — segunda passada no fluxo, alinhando o mobile com o web.
  - **Regra de acesso**: só admin do módulo Transporte OU usuário
    com o papel `Criar BDT sem Solicitação` (`TransporteRoles::CRIAR_BDT_SEM_SOLICITACAO`)
    pode usar. Reproduz o padrão do web (o `RoleFilter` do CI4 é
    session-based e não serve pro Bearer — o gate mora no
    controller mobile, `podeCriarBdtSemSolicitacao($userId) =
    isDiretorOuAdmin || usuarioTemPapel`).
  - **Backend**: gate 403 em `checkupVeiculo` e `criarBdtSemSolicitacao`;
    removida a restrição "condutor_id === próprio" (agora quem tem o
    gate pode abrir BDT em nome de qualquer condutor ativo, paridade
    com o painel web). 2 endpoints novos:
    - `POST bdt/permissoes-mobile` → `{criar_bdt_sem_solicitacao: bool}`
      (mais chaves entram sem mudança de shape).
    - `POST bdt/condutores-ativos` → lista `{id, nome, sou_eu}`
      ordenada por nome (mesmo gate). Query direta em `trnsp_condutores`.
  - **Mobile**:
    - Novo `PermissoesService` (`lib/services/permissoes_service.dart`)
      com cache em SharedPreferences (chave `permissoes_cache`).
      `reload()` no login e no reload da Home; `pode(chave)` só lê o
      cache (nunca faz rede — evita piscar na tela). Limpado no logout.
    - `HomePage` esconde o item "Criar BDT direto" do bottom sheet se
      `!pode('criar_bdt_sem_solicitacao')` — condutor comum vê só
      "Novo Pré-BDT" (e o FAB vira diretão sem menu, sem sheet inútil).
    - `CriarBdtPage` ganha `SegmentedButton` "Para mim / Outro" +
      `DropdownButtonFormField<CondutorLite>` (só carrega no modo
      "outro"). Se o usuário logado NÃO é condutor (admin puro),
      o botão "Para mim" fica desabilitado e o modo default é "outro".
      Envia `condutor_id` no POST. Checkup re-dispara quando muda
      veículo OU condutor.
    - Model novo `CondutorLite` (`{id, nome, souEu}`) só pro dropdown.
  - **UX**: quando só a opção "Novo Pré-BDT" está disponível, o FAB
    vai direto pro form (sem abrir bottom sheet com um único item).
    Rótulo do FAB muda entre "Criar" (com gate) e "Novo Pré-BDT" (sem).

- ✅ **Ajustes finais de UX + solicitante na casca** (2026-07-30)
  - **"Vai levar carga?" → "Haverá transporte de carga?"** no
    `CargaFormCard` (as duas telas de uma vez).
  - **Captcha em maiúsculas**: `textCapitalization.characters` é só uma
    *dica* ao teclado — teclado físico e alguns apps de teclado ignoram, e
    o texto chegava minúsculo. O desafio é gerado/comparado em maiúsculas
    no `SimpleCaptchaService`, então o usuário era recusado por caixa,
    vendo letra maiúscula na imagem. Novo `_UpperCaseFormatter` força de
    fato. Vale no login e no esqueci-senha (widget compartilhado).
  - **CPF com máscara no esqueci-senha**, igual ao login
    (`FilteringTextInputFormatter.digitsOnly` + `CpfInputFormatter`,
    hint `000.000.000-00`). O envio já limpava a pontuação.
  - **Solicitante na casca do BDT direto**: `fk_solicitante` vinha NULL e
    a lista mostrava "—", enquanto o Pré-BDT trazia o nome. Agora
    `fk_solicitante` = **condutor** (para quem é a viagem, o nome que faz
    sentido na lista) e `fk_usuario_cadastro` = **quem registrou** — é o
    par que preserva a autoria quando um admin abre BDT para outro
    condutor. Quando é a mesma pessoa, ambas recebem o mesmo id, e isso é
    necessário: é o que distingue "abri para mim" de "abriram para mim".
    Novo helper `usuarioIdDoCondutor()` traduz
    `trnsp_condutores.id` → `usuarios.id` (a designação guarda um,
    `fk_solicitante` aponta pro outro).
  - **Unidade do solicitante na casca** (2026-07-30): faltava
    `fk_unidade_solicitante`, então o card Solicitante do acompanhamento
    exibia "Unidade: —" mesmo com o nome já correto. A unidade acompanha o
    **solicitante**, não quem registrou — a viagem pertence à lotação de
    quem vai rodar. Reusa `UsuarioModel::getUnidadeIdByUserId()` (já
    existia), sem novo helper. `nome_unidade_solicitante` fica NULL de
    propósito: é texto livre para solicitante EXTERNO, e casca é sempre de
    usuário interno.
    - Os **três** criadores de casca tinham o mesmo buraco, não só o BDT
      direto: `PreBdtService::materializarSolicitacao` (Pré-BDT aprovado) e
      `BdtViagemService::getOrCreateSolicitacaoAvulsa` (trecho extra, feature
      da web) também. Corrigidos juntos — deixar dois com o defeito só
      geraria o mesmo relato de bug de outro ângulo.
    - Migration `BackfillSolicitanteEUnidadeCascasBdt` cuida do histórico:
      preenche `fk_solicitante` (condutor designado → `fk_usuario_cadastro`
      como fallback) e depois a unidade. As 14 cascas antigas estavam com
      **as duas** colunas NULL — o fix de solicitante acima só valia pra
      registros novos. Idempotente, só preenche coluna vazia, não move dado
      de lugar (nada do episódio de 2026-07-29, em que mudar onde o trecho
      morava quebrou os JOINs de `tipo_solicitante = 'avulso'`).
    - Verificado chamando `criarEntradaAgenda` em transação com rollback:
      admin (unid 20) abrindo para condutora de unidade 4 grava **unidade
      4** — a dela, não a de quem registrou.
  - **E-mail do esqueci-senha confirmado**: usa o helper
    `enviar_email_reset_senha` — o MESMO do
    `LoginController::forgotPasswordValidate` do web, com o mesmo
    `Services::email(true)` e `config('Email')`. Assunto, template e link
    saem idênticos ao fluxo pelo navegador; nada foi reimplementado.

- 🟡 **Pendência: apagar um BDT direto deixa a solicitação-casca para trás**
  (2026-07-30) — descoberto ao limpar o dev DB depois dos testes de
  Sprint 15. A casca é criada por `criarEntradaAgenda` como registro
  independente; excluir o BDT **não** a remove. Sobra uma solicitação
  "Agendado" na lista, apontando para um BDT que não existe mais.
  - **No dev**: 14 cascas, várias de BDTs já apagados. Não deletei —
    não dá pra distinguir com segurança as minhas de teste das do
    usuário (uma delas é a `TRN-2026-0018` dele), e apagar solicitação
    alheia é pior que deixar lixo visível.
  - **Em produção o efeito é recorrente**: todo BDT direto excluído vai
    deixar uma. O mesmo vale pra casca de Pré-BDT e pra `avulso`.
  - **Não decidido** qual é o comportamento certo: cascatear o
    soft-delete do BDT para a casca, ou manter a casca como registro
    histórico (o BDT existiu, foi agendado, e a solicitação documenta
    isso). A segunda opção combina com a decisão de manter a casca
    visível, mas aí a lista precisa marcar "BDT excluído" — hoje não
    marca nada. **Precisa da chamada do usuário antes de codar.**

- ✅ **Carga do BDT × carga do Pré-BDT: rótulo por situação** (2026-07-30) —
  **erro de premissa meu**: eu rotulava toda carga guardada em `trnsp_bdt`
  como "declarada no BDT", tratando como um caso só o que são quatro.
  - Carga em `trnsp_bdt` pode ser **definitiva** (BDT criado direto — a
    viagem existe) ou **provisória** (Pré-BDT pendente — ainda depende de
    aprovação). E `PreBdtService::recusar` **não apaga** a carga: um
    Pré-BDT recusado mantém a carga ali, então o rótulo antigo mostrava
    como carga real algo de uma viagem que não vai acontecer.
  - Novo `BDTController::rotuloOrigemCarga($origem, $preBdtStatus)`
    centraliza a regra pra folha e PDF; o mobile tem os getters
    equivalentes (`rotuloOrigem` / `avisoOrigem` / `viagemRecusada` /
    `aguardandoAprovacao`) em `CargaDoBdt`. Estados:
    - sem `pre_bdt_status` → "declarada no BDT" (definitiva, sem aviso)
    - `pendente` → "declarada no Pré-BDT · aguardando aprovação" + aviso
      de que a viagem pode não acontecer (âmbar)
    - `recusado` → "Pré-BDT recusado · carga não se realiza" + aviso de
      não conferir (vermelho)
    - `aprovado` → só chega aqui se a materialização ficou incompleta
      (normalmente a origem viraria `solicitacao`); rotula como aprovado
      em vez de mentir "declarada no BDT"
  - O texto de apoio do card também deixou de mandar "conferir" quando há
    item cuja viagem não foi confirmada — nesse caso a carga é declaração,
    não fato da viagem. Vale no mobile, na folha e no PDF.
  - `bdt/carga` passou a enviar `pre_bdt_status`. Verificado nos 4 estados.

- ✅ **Status "Agendado" + Pré-BDT alinhado ao BDT direto** (2026-07-30) —
  duas correções que fecham o tratamento das cascas.
  - **Status vazio**: `criarEntradaAgenda` e `materializarSolicitacao`
    definiam `fk_status_atual = 5` (Agendado) na tabela de solicitações, mas
    nunca inseriam linha em `trnsp_solicitacoes_status`. A listagem e o
    acompanhamento leem o **histórico** (join `ss`), não a coluna — daí o
    badge de status vazio e o "Indefinido". Nos dois casos a viagem já
    **está** agendada quando a casca nasce (no BDT direto veículo e condutor
    saem definidos; no Pré-BDT, aprovar é o ato de agendar), então registrar
    "Agendado" descreve o que aconteceu. Migration
    `BackfillStatusHistoricoCascasBdt` cuida do que já existe (idempotente).
  - **Pré-BDT visível como o BDT direto**: `PRE_BDT` saiu de `sinteticos()`,
    que fica só com `AVULSO` — este último não é viagem, é o balde interno
    dos trechos avulsos, e segue invisível. Um Pré-BDT aprovado é, para
    todos os efeitos, um BDT agendado; ter um visível e o outro oculto eram
    dois tratamentos pro mesmo fim.
  - ⚠️ **Pré-BDT pendente continua fora da lista** — não por filtro, mas
    porque só ganha solicitação na aprovação (`fk_solicitacao` NULL antes).
    São dois mecanismos distintos; a nota ficou no docblock pra não
    confundirem um com o outro ao investigar.
  - Docblocks e os comentários das duas consultas do `SolicitacaoModel`
    atualizados: diziam "oculta cascas de Pré-BDT", o que ficou falso.

- ✅ **Solicitação-casca do BDT direto: origem explícita** (2026-07-29) — a
  solicitação criada para o BDT direto aparecia na lista e no
  acompanhamento com Solicitante, Responsável, Aprovador e Unidade todos
  "—" e status vazio, parecendo cadastro corrompido; e "Transporte de
  Carga: Não" mesmo havendo carga.
  - **Por que o Pré-BDT não aparecia e o BDT direto sim** — duas causas
    somadas, herança da evolução do código: (a) `sinteticos()` lista
    `['pre_bdt','avulso']` e a listagem faz `NOT IN sinteticos()`, então
    `bdt_sem_solicitacao` passa pelo filtro; (b) o Pré-BDT **pendente** nem
    tem solicitação (`fk_solicitacao` NULL) — ela só nasce na aprovação.
  - **Decisão (revista com o usuário): manter visível.** O motivo original
    de esconder cascas era justamente o cadastro parecer quebrado — e isso
    foi resolvido na raiz. Ocultar tiraria do radar um registro que
    sustenta o fluxo da Agenda e serve à auditoria. A assimetria com o
    Pré-BDT fica registrada como deliberada no docblock de
    `TransporteSolicitanteTipos::BDT_SEM_SOLICITACAO`, com aviso pra não
    "consertarem" adicionando o tipo a `sinteticos()`.
  - Aviso de origem no topo do acompanhamento: rótulo de como surgiu, link
    pra folha do BDT, **quem criou**, e **quem aprovou + quando** (Pré-BDT)
    ou "sem etapa de aprovação" (BDT direto — quem cria já tem o papel que
    autoriza; dizer isso evita a leitura de que ficou faltando aprovar).
  - Carga na casca: badge passa a "Sim" e as fotos aparecem, enriquecendo
    na LEITURA (as fotos só sobem depois da criação, então copiar o texto
    separaria descrição das imagens). Mesma guarda anti-duplicação.

- ✅ **Carga declarada no PDF da folha** (2026-07-29) — antes a carga só
  aparecia no PDF como coluna "Declarado" **dentro** das divergências: sem
  divergência registrada o documento não dizia nada sobre a carga, e para
  BDT direto / Pré-BDT não dizia nunca (`$cargasDeclaradas` cobre apenas
  solicitações).
  - Seção própria "Carga declarada" antes de Divergências (mesma ordem da
    folha). Tabela com origem/protocolo, descrição, peso, C×L×A e contagem
    de fotos; linha extra pra pessoal de apoio. Placeholder "Sem carga
    declarada" no padrão `$vazio()` das outras seções.
  - **Sem miniaturas, de propósito**: este PDF não embute imagem em seção
    nenhuma (abastecimento, manutenção e ocorrência também não). Mostra a
    contagem e aponta onde ver — documento coerente e paginação previsível.
  - Extraído `montarCargasDoBdt()` no `BDTController`, agora compartilhado
    por `folha()` e `folhaPdf()`. A regra das três origens + guarda
    anti-duplicação estava inline na folha; deixar as duas actions com
    cópias era convite pra divergirem — exatamente o descasamento que
    gerou o bug da carga duplicada.

- ✅ **Carga duplicada no card do mobile** (2026-07-29) — **regressão do item
  anterior**: um Pré-BDT aprovado passou a aparecer DUAS vezes no card
  "Carga declarada" — uma pela solicitação (com as fotos) e outra pelo BDT
  (sem nenhuma). Causa: na aprovação, `materializarSolicitacao` copia a
  carga para `trnsp_solicitacoes` **e migra as fotos** para lá, mas
  `trnsp_bdt.tem_carga` permanece `1` — então o fallback que eu havia
  adicionado criava uma segunda entrada já órfã de fotos. Corrigido com a
  guarda `empty($out)`: a entrada do BDT só entra quando a carga NÃO foi
  materializada (Pré-BDT pendente, BDT criado direto pelo app).
  Verificado nos três estados: BDT direto → 1 item `TRN-BDT-` com foto;
  Pré-BDT pendente → 1 item `TRN-BDT-` com foto; Pré-BDT aprovado → 1 item
  `TRN-` com foto.

- ✅ **Fotos da carga na WEB, dentro do BDT** (2026-07-29) — as fotos
  existiam desde a Sprint 11 W+M, mas na web só apareciam na tela da
  **solicitação do solicitante**. Na Agenda e no BDT não havia nada — e
  para BDT direto / Pré-BDT não havia lugar NENHUM, já que esses não têm
  solicitação de usuário por trás.
  - Novo partial `_carga.php` na folha do BDT, incluído **antes** do card
    de Divergências (a carga é o previsto; a divergência é a reação a ela).
    Auto-oculta quando não há carga declarada.
  - Cobre as **três origens** com a mesma regra anti-duplicação do mobile:
    cargas das solicitações vinculadas (pedido real e Pré-BDT aprovado) e,
    quando não materializada, a carga do próprio BDT. A de BDT ganha o
    badge "declarada no BDT" — senão o protocolo `TRN-BDT-` confunde quem
    procura o pedido de origem.
  - Miniaturas reusam o contrato `data-group` + `title` da galeria que já
    existe na folha (mesmo modal de abastecimento/manutenção/ocorrência,
    com prev/next, legenda e navegação por seta). **Zero JS novo.**
  - Sai também na impressão: a carga faz parte do registro da viagem,
    como já sai no PDF.

- ✅ **Editar Pré-BDT trazia a carga em branco** (2026-07-29) — **bug de
  leitura**: o form de edição abria com o switch "Vai levar carga?"
  DESLIGADO e os campos vazios, mesmo com carga declarada. A gravação
  sempre funcionou; a releitura estava cega.
  - Causa: `PreBdtRepository::findMeuPendente` — a query que alimenta o
    `pre-bdt/obter` — não incluía as 6 colunas de carga no SELECT. Sem
    `tem_carga` no JSON, `PreBdtPendente.fromJson` caía no default
    `false` e o card nem expandia.
  - O mobile já estava correto (`_temCarga = p.temCarga` + controllers +
    loader das fotos) — só faltava o dado chegar.
  - Verificado: `tem_carga=1`, descrição, peso `25.500` e as três
    dimensões voltando do backend.

- ✅ **Ver a foto da carga no BDT** (2026-07-29) — o card "Carga
  declarada" não mostrava nada quando a carga tinha sido declarada no
  próprio BDT (BDT criado direto pelo app, ou Pré-BDT ainda pendente):
  nesses casos ela mora em `trnsp_bdt`, com fotos referenciadas por
  `tabela='trnsp_bdt'`, e o endpoint `bdt/carga` só olhava
  `trnsp_solicitacoes`.
  - `listarCargaDoBdt` ganha a carga do próprio BDT quando
    `tem_carga=1`, com as fotos de `tabela='trnsp_bdt'`. Cada item passa
    a carregar `origem` (`'solicitacao'` | `'bdt'`).
  - `bdt/carga/foto/obter` aceita `origem` e escolhe a tabela de
    referência — **uma rota só**, em vez de o app ter que alternar entre
    dois endpoints. Isso também corrige um problema latente: o
    `obterFotoCarga` da Sprint 11 guarda por `criado_por`, o que passaria
    a barrar o condutor quando o **admin** cria o BDT para ele. Aqui a
    autorização é sempre por condutor do BDT (`assertBdtPertence`),
    igual aos outros anexos.
  - Mobile: `CargaDoBdt.origem` + `declaradaNoBdt`; protocolo sai como
    `TRN-BDT-` quando a carga é do BDT (sequência distinta da de
    solicitações) e o detalhe rotula a linha como "BDT" em vez de
    "Solicitação". Reusa o `RegistroBdtDetalhePage` →
    `FotoGaleriaPage` (swipe + zoom + contador), mesmo caminho de
    abastecimentos/manutenções/ocorrências.
  - Verificado: foto referenciada em `trnsp_bdt` aparece na listagem e o
    protocolo sai como `TRN-BDT-2026-0004`.

- ✅ **Itinerário do BDT direto no PDF e no modal "Origem"** (2026-07-29) —
  depois de corrigir a Agenda, os outros dois pontos de leitura seguiam
  vazios: o PDF de acompanhamento saía sem itinerário e o modal "Origem do
  BDT" (painel) dizia "Sem trechos cadastrados", mesmo com o trecho
  visível na folha e na Agenda. Mesma raiz — cada tela lê os trechos da
  solicitação, e nas cascas sintéticas o itinerário não mora lá.
  - `SolicitacaoModel::getWithDiasETrechos` (usado pelo PDF) ganha
    fallback quando NENHUM dia tem trecho, anexando ao primeiro dia
    (a casca tem exatamente um) para o template não precisar diferenciar.
    Também passou a trazer `s.tipo_solicitante` no select, que faltava.
  - `BdtRepository::getOrigemBdt` ganha o fallback de `bdt_sem_solicitacao`
    ao lado do que já existia para `pre_bdt`.
  - **Pré-BDT (o que foi pedido pra conferir)**: o fallback do PDF cobre
    `pre_bdt` também, lendo `trnsp_bdt_trechos_previstos`. Isso conserta um
    caso que já existia antes deste trabalho e passava batido — quando a
    aprovação reaproveita uma agenda existente, os trechos NÃO são
    materializados em `trnsp_solicitacao_trechos` e o PDF saía sem
    itinerário. O `getOrigemBdt` já tratava isso; o PDF não.
    Pré-BDT **pendente** não tem solicitação (`fk_solicitacao` NULL), logo
    não tem PDF de acompanhamento — só depois de aprovado.
  - Verificado nos 3 pontos (Agenda / PDF / modal) para BDT direto, mais o
    modal do Pré-BDT pendente, e as 7 solicitações normais seguem com
    itinerário no PDF (o fallback só entra quando a própria solicitação
    está sem trecho).

- ✅ **BDT direto — declarar carga** (2026-07-29) — o BDT criado direto pelo
  app passa a aceitar carga, que antes só existia no Pré-BDT.
  - **Mesmo destino, mesma regra**: grava nas MESMAS 6 colunas de
    `trnsp_bdt` (`tem_carga`, `carga`, `carga_peso_kg`,
    `carga_comprimento_m`, `carga_largura_m`, `carga_altura_m`) e reusa a
    normalização do `PreBdtService` — inclusive o parse que aceita vírgula
    decimal. Divergir aí faria o mesmo input virar dado diferente
    dependendo da tela.
  - **Backend**: `BdtSemSolicitacaoService::criar` ganha 5º parâmetro
    `array $carga = []` (opcional no fim, então o caller do web não muda);
    `criarBdtSemSolicitacao` repassa os campos.
  - **Fotos sem endpoint novo**: o guard `assertPreBdtOwnership` só checa
    `criado_por` — não exige Pré-BDT pendente. Logo
    `bdt/pre-bdt/fotos-carga/*` (que já referencia `tabela='trnsp_bdt'`)
    aceita o BDT direto como está. Upload em batch **após** criar, porque
    precisa do `bdt_id` — igual ao Pré-BDT.
  - **UI compartilhada**: card extraído para `CargaFormCard`
    (`lib/widgets/carga_form_card.dart`, ARCHITECTURE §4.8) e usado nas
    DUAS telas. Duplicar ~200 linhas abriria espaço pra elas divergirem,
    justamente o que se quer evitar quando o destino do dado é o mesmo.
    Extração de UI pura: o estado continua na Page, que valida e envia.
  - **Validação no padrão da casa**: switch ligado exige descrição + ao
    menos 1 foto (paridade com o `folha.php` do web), com banner
    `errorContainer` no card e `*` nos labels obrigatórios. Peso e
    dimensões seguem opcionais.
  - Verificado: sem carga não grava nada; com carga o `"12,5"` do teclado
    pt-BR chega como `12.500`; guard de foto aceita o BDT direto.

- ✅ **Fix: itinerário do BDT sem solicitação na Agenda — agora pelo lado
  da LEITURA** (2026-07-29) — a primeira tentativa (mover o trecho para a
  solicitação da casca) **quebrou o BDT no web** e foi revertida: o
  `BdtRepository` casa por `tipo_solicitante = 'avulso'` em duas
  consultas, então "trecho avulso mora em solicitação 'avulso'" é
  invariante, não detalhe. Avaliei mal o alcance na primeira vez.
  - **Solução correta**: `SolicitacaoModel::getSolicitacoesCompletas`
    enriquece a casca `bdt_sem_solicitacao` com os trechos da solicitação
    'avulso' do BDT (novo `getTrechosAvulsosDoBdtPorSolicitacao`). O dado
    fica onde sempre esteve; só quem lê passou a saber olhar nos dois
    lugares.
  - Constante `BDT_SEM_SOLICITACAO` centralizada em
    `TransporteSolicitanteTipos` (o literal estava espalhado). Ela NÃO
    entra em `sinteticos()`: é sintética na origem, mas visível na Agenda
    por desenho.
  - Migration `DesfazMovimentacaoTrechosBdtSemSolicitacao` devolveu ao
    lugar os trechos que a migration anterior havia movido.
  - Verificado: trecho segue na 'avulso' (invariante intacto), Agenda
    renderiza o itinerário, `embarque`/`destino` preenchidos, token do PDF
    presente, e as 7 solicitações normais não foram afetadas.

- ✅ **Fix: itinerário do BDT sem solicitação sumia da Agenda + PDF null**
  (2026-07-29) — **reportado no teste**: trecho criado pelo app aparecia
  certinho na folha do BDT, mas a Agenda continuava dizendo "Itinerário
  a definir", o modal "Origem do BDT" dizia "Sem trechos cadastrados" e
  o botão do PDF apontava pra `/solicitacoes/pdf/acompanhar/null`.
  - **Causa**: um BDT sem solicitação ganhava **duas** solicitações
    sintéticas — (1) `tipo_solicitante='bdt_sem_solicitacao'`, criada
    junto do BDT e apontada por `trnsp_bdt.fk_solicitacao`, que é a que
    a Agenda desenha, nascendo **sem trechos**; e (2)
    `tipo_solicitante='avulso'`, criada no primeiro trecho e
    **filtrada da Agenda de propósito** por ser interna. O trecho ia
    parar na (2). A folha continuava certa porque lê
    `trnsp_bdt_trechos_execucao`, não a solicitação — daí o sintoma
    "no BDT está tudo ok, na Agenda não aparece".
  - **Fix 1** — `BdtViagemService::getOrCreateSolicitacaoAvulsa` passa a
    reusar a solicitação do PRÓPRIO BDT quando ela é do tipo
    `bdt_sem_solicitacao`. BDT vindo de solicitação REAL continua
    criando a 'avulso' separada: lá a separação é proposital, porque
    adicionar trechos no pedido original adulteraria o que o solicitante
    pediu e vê no acompanhamento.
  - **Fix 2** — `criarEntradaAgenda` passa a gerar protocolo da
    solicitação + **token de verificação**, como o
    `PreBdtService::materializarSolicitacao` (que ele espelha) já fazia.
    A falta do token era a causa direta do `/acompanhar/null` — a view
    da Agenda lê `token_verificacao` do join com `trnsp_verificacao`.
  - **Fix 3** — migration `BackfillBdtSemSolicitacaoAgenda` conserta o
    que já está no banco: gera token pras sintéticas órfãs e move os
    trechos da 'avulso' pro dia da solicitação da Agenda. Idempotente e
    restrita a BDT cuja solicitação principal é `bdt_sem_solicitacao`.
  - Verificado ponta a ponta: BDT criado → token presente → trecho cai
    na MESMA solicitação que a Agenda desenha → nenhuma 'avulso' extra →
    trecho segue reivindicado na execução (folha continua certa).
  - **Backend-only** — nenhuma mudança no app foi necessária; o mobile já
    chamava o endpoint certo.

- ✅ **GPS offline — dedup no backend** (2026-07-28) — o duplo motor
  (timer + foreground service) compartilha a mesma fila, o que abria dois
  caminhos pro mesmo ponto chegar 2×: (a) **retry após timeout enganoso**
  — o `POST bdt/localizacao` insere mas a resposta não volta nos 10s do
  worker, o ponto é marcado como falho e reenviado, gravando um gêmeo
  exato; (b) **sobreposição timer × service** no mesmo instante. Cada
  duplicata virava um vértice a mais no traçado — rota inflada no mapa e
  distância a maior. Backend: migration idempotente
  `AddUniqueToTrnspBdtLocalizacoes` (deduplica o histórico com `<=>` pro
  `fk_trecho` nullable + cria `uniq_bdt_trecho_datahora`) e
  `BdtLocalizacoesModel::registrarPonto` passa a usar `INSERT IGNORE`
  via query builder, devolvendo o id existente quando ignora — assim o
  cliente marca o ponto como enviado e tira da fila em vez de ficar
  batendo até esgotar tentativas. Caso (a) fica 100% coberto; (b)
  parcialmente (mesmo segundo colide, segundos vizinhos passam — e isso
  é correto, são leituras legítimas). Verificado localmente.

- ✅ **GPS offline — retry de ~5min para ~60min** (2026-07-28) —
  `LocationQueueDb.maxAttempts` de 10 → 120. O worker roda a cada 30s,
  então a janela de retry saiu de ~5min para ~60min. Com o valor antigo,
  uma viagem entre campi atravessando região sem cobertura descartava o
  traçado inteiro daquele trecho. O descarte continua existindo como
  backstop (se o backend recusa por regra de negócio, 120 tentativas só
  adiam o inevitável — e a fila é SQLite em disco, não RAM).

- ✅ **GPS offline — service sobe sozinho após reboot** (2026-07-28) —
  se o condutor reiniciava o celular no meio de um trecho, a coleta só
  voltava quando ele abrisse o app. O plugin `flutter_background_service`
  já registra um `BootReceiver` no manifest (BOOT_COMPLETED /
  QUICKBOOT_POWERON / MY_PACKAGE_REPLACED) — bastou ligar
  `autoStartOnBoot: true`. Como isso sobe o service INCONDICIONALMENTE
  após todo boot, o `_onServiceStart` ganhou um gate: se não havia trecho
  ativo (`_bg_gps_running != true` ou bdt/trecho zerados), drena a fila
  uma vez (aproveita o boot pra escoar backlog de um trecho anterior) e
  chama `stopSelf()` — sem notificação órfã "Aguardando início do trecho"
  logo após ligar o celular. Complementa o `resumeIfNeeded()` do
  `main()`, que cobre morte por OOM com o app fechado.

- ✅ **MSEC.5 — Certificate pinning** (2026-07-28) — antes o app usava
  `SecurityContext.defaultContext`, que **soma** a CA da RNP às ~150 CAs
  do sistema: na prática aceitava certificado de qualquer uma delas, e um
  proxy corporativo ou CA comprometida conseguiria interceptar o tráfego
  (inclusive o Bearer) numa rede pública. Agora existe um
  `SecurityContext(withTrustedRoots: false)` que confia **exclusivamente**
  na cadeia da RNP, validado no handshake TLS — ou seja, **antes de
  qualquer byte da requisição sair do aparelho**, diferente de conferir o
  certificado na resposta (quando o dado já vazou).
  - **Pinamos a cadeia (intermediária + raiz), não o certificado folha** —
    pinar a folha quebraria o app a cada renovação (~1 ano); pinar a
    cadeia sobrevive à renovação e ainda exclui as outras CAs, que é de
    onde vem o risco real.
  - Novo `SslBootstrap.client` (singleton `IOClient`, reaproveita a
    conexão pra não refazer handshake a cada ponto de GPS). Adotado em
    `ApiClient._doPost`, `postForBytes`, `postMultipart` e no worker do
    `BackgroundLocationService`.
  - `badCertificateCallback` retorna `false` explicitamente — um `true`
    ali anularia o pin inteiro.
  - Guarda contra corrida: se `client` for acessado antes do `install()`,
    devolve um client comum mas **não cacheia**, senão o app ficaria sem
    pin pelo resto da sessão.
  - Só vale em produção (HTTPS). Ambientes de dev falam HTTP puro, que
    nem passa por `SecurityContext` — proxies de debug seguem funcionando.
  - **Escape hatch**: `--dart-define=SSL_PINNING=off` (build-time, não
    desligável em runtime por atacante) pra destravar sem esperar release
    se a RNP migrar de CA sem aviso.
  - **Verificado com openssl**: produção valida contra a cadeia pinada
    (`Verify return code: 0`), CA de fora é recusada (`code 20`).
    Intermediária da RNP vale até **19/11/2030**, raiz GlobalSign R46 até
    2046 — sem risco de expiração próxima. Procedimento de atualização do
    pin documentado no cabeçalho de `ssl_bootstrap.dart`.

- ✅ **PreBdtFormPage — erros inline (veículo + trechos)** (2026-07-26)
  — os SnackBars "Escolha um veículo." e "Trecho N: preencha origem e
  destino." eram invisíveis atrás do teclado. Substituídos por
  `String? _veiculoError` (texto embaixo do `VeiculoAutocomplete`,
  cor `colorScheme.error`) + `errOrigem`/`errDestino` na classe
  `_TrechoInput` (renderizados via `errorText` nos `TextFormField`).
  Validação roda TUDO antes de retornar — condutor vê todos os
  erros de uma vez. `onChanged` limpa o erro do campo ao digitar.
  Padrão idêntico ao `AbastecimentoSheet`/`TrechoExtraSheet`/
  `CriarBdtPage`.

- ✅ **GPS offline — timer foreground também enfileira** (2026-07-26) —
  o `GpsLiveService` timer chamava `enviarLocalizacao` direto; se
  falhasse (rede caindo em tunel/área rural), o ponto era PERDIDO
  no isolate main. O único que sobrevivia era o BG service (que
  enfileira). Agora o timer também usa o `LocationQueueDb` como
  fallback — mesma fila SQLite compartilhada. O worker do BG
  service (batch de 20 a cada 30s, retry até 10×) consome ambas
  origens. Preserva o duplo motor: o timer continua sendo caminho
  preferido (baixa latência), a fila é rede de segurança.

- ✅ **GPS offline — drain final ao finalizar trecho** (2026-07-26) —
  novo `GpsLiveService.stopWithDrain(bdtId, trechoId, timeout: 5s)`.
  Antes de parar o service, aguarda até 5s pra a fila daquele
  trecho zerar. Retorna quantos pontos sobraram; a UI mostra
  snackbar "N pontos ainda serão enviados em background quando
  reconectar." Nunca trava — se sobrar, o BG service continua
  drenando após stop ([[bdt_uerj_sem_travas_so_alertas]]).
  `_stopTrackingWithDrain` na `bdt_page` é usado nos dois pontos
  de "Finalizar trecho" (`_openTrechoSheet` e formulário legacy).

- ✅ **GPS offline — resumeIfNeeded no main()** (2026-07-26) —
  fabricantes agressivos (Xiaomi/Huawei/Samsung One UI) matam o
  foreground service mesmo com isenção de bateria. Novo
  `BackgroundLocationService.resumeIfNeeded()` — checa
  `_bg_gps_running` no SharedPreferences; se ele diz que devia
  estar rodando mas o service morreu (`FlutterBackgroundService()
  .isRunning()==false`), chama `startService()` de novo com o
  contexto salvo (bdt_id/trecho_id nas prefs). Chamado no `main.dart`
  logo após `BackgroundLocationService.init()`. Idempotente — se
  já está rodando ou não tem BDT/trecho salvo, é no-op.

- ✅ **Doc + memory: arquitetura GPS offline** (2026-07-26) —
  nova memory `bdt_uerj_gps_offline` documenta o duplo motor +
  fila compartilhada + retry + gaps conhecidos (dedup no backend
  ausente, sem BOOT_COMPLETED receiver). Serve de referência pra
  não simplificar removendo um dos motores acidentalmente.

- ✅ **CriarBdtPage — trechos opcionais pré-criação** (2026-07-26) —
  o condutor pode adicionar 1+ trechos junto do form de criar BDT
  (evita o vai-e-volta "cria BDT → abre BDT → adiciona trecho extra"
  que era a UX anterior). Novo card "Trechos (opcional)" com botão
  "Adicionar trecho" que abre o mesmo sheet do trecho extra (agora
  extraído pra widget compartilhado `TrechoExtraSheet` em
  `lib/widgets/trecho_extra_sheet.dart`). Lista os drafts com ícone
  `alt_route`, mostra hora saída→chegada e observação em preview,
  botão "×" pra remover. Ao criar o BDT: primeiro cria o BDT via
  `criarBdtSemSolicitacao`; se success, roda `criarTrechoExtra` pra
  cada draft em sequência; snackbar final consolidado
  ("BDT TRN-BDT-... criado com N trechos." ou "N ok, M falharam."
  vermelho). Falha de trecho NÃO invalida o BDT — condutor pode
  re-tentar os que faltaram na tela do BDT. Não trava
  ([[bdt_uerj_sem_travas_so_alertas]]).

- ✅ **TrechoExtraSheet — widget reusável extraído do bdt_page** (2026-07-26)
  — o formulário do `_openTrechoExtraSheet` (inline em `bdt_page.dart`,
  ~260 linhas) virou `TrechoExtraSheet.show(context, {titulo, botaoLabel})
  → Future<TrechoDraft?>`. O `bdt_page` (que salva no BDT já criado)
  passou a chamar `TrechoExtraSheet.show` + `criarTrechoExtra` no
  callback. A `CriarBdtPage` (que acumula pré-criação) chama o mesmo
  sheet e faz `_trechos.add(draft)`. Zero duplicação de UI.

- ✅ **CriarBdtPage — autocomplete filtrável de condutor** (2026-07-26)
  — o `DropdownButtonFormField` estático foi trocado por um
  `CondutorAutocomplete` novo (`lib/widgets/condutor_autocomplete.dart`).
  Filtro `contains` case-insensitive + sem acento em cima da lista
  IN-MEMORY (não bate no backend — a lista de ativos é pequena,
  já foi baixada no `initState`). Padrão UX igual ao
  `VeiculoAutocomplete`: card compacto depois de escolher, botão
  "Trocar", ícone dropdown na direita pra abrir o menu sem digitar.
  O item `souEu` fica destacado ("Você mesmo", ícone person cheio).

- ✅ **Android build — silencia warnings Java 8 obsolete + jvmTarget
  mismatch** (2026-07-26) — o build printava 3 warnings por plugin
  Flutter a cada `flutter run` (`source value 8 is obsolete`, etc.)
  porque muitos plugins ainda declaram `VERSION_1_8`. E o
  `image_picker_android` já subiu o Kotlin pra 17 sem subir o Java,
  quebrando com `Inconsistent JVM Target Compatibility`. Fix em
  `android/build.gradle.kts`: bloco `subprojects.afterEvaluate` que
  força TODOS os plugins Android a Java 11 (via `BaseExtension`) +
  Kotlin `compilerOptions.jvmTarget = JVM_11` (Kotlin 2.x removeu
  `kotlinOptions`). Precisa vir ANTES do `evaluationDependsOn(":app")`
  senão o Gradle recusa `afterEvaluate` em subprojetos já avaliados.

- ✅ **Trecho extra — errorText inline por campo** (2026-07-26) —
  Adiciona `errorText` no `TextField` de Origem e Destino do
  `_openTrechoExtraSheet` (bdt_page.dart), alinhando com o padrão dos
  outros forms (`AbastecimentoSheet`, `NovaOcorrenciaPage`,
  `AssinaturaMarcoPage`, `CriarBdtPage`). Antes: banner `errorContainer`
  no topo dizia "Informe origem e destino." e o condutor tinha que
  descobrir qual campo estava vazio. Agora: mensagem específica em
  cada campo (`Informe a origem.` / `Informe o destino.`). O banner
  no topo continua sendo usado para erros de nível de form
  (ambiguidade dos dois horários, falha de rede).

### Da Sprint 17 web (Ocorrências)
- ✅ **Substitui card "Acidentes" (placeholder) por "Ocorrências" real**
  (2026-07-23) — a `BdtFormPage` mostrava um card "Acidentes (Em breve)"
  com nota "Ainda não existe tabela/endpoint para acidentes, assim que
  você criar eu completo o CRUD aqui." Foi um assumed placeholder
  especulativo meu — **nunca deveria ter existido**. A estrutura
  correta do Formulário do BDT é: **Abastecimentos + Manutenções +
  Ocorrências** (acidente/sinistro é apenas UM dos tipos de ocorrência).
  Substituído pelo card real `_cardOcorrencias(bdtId)` — botão
  "Registrar" (mesmo destino do sheet Ações) + nota apontando pro
  histórico institucional (Menu → Ferramentas).

- ✅ **Forms Abastecimento/Manutenção com validação inline** (2026-07-23)
  — paridade com o web (`folha.php` `data-required`) e com o padrão da
  `NovaOcorrenciaPage`. Antes o `_openAbastecimentoSheet` **não** validava
  nada client-side (SnackBar genérico só quando o backend recusava) e o
  `_openManutencaoSheet` validava a coisa errada (`descricao` via SnackBar,
  mas nem `data_hora_inicio` que é required).
  - Padrão adotado: `String? err<Campo>` por required + `String? formError`
    (banner vermelho `errorContainer` no topo) + `bool busy` (spinner
    no botão + campos disabled). Todo textfield ganhou `onChanged` que
    limpa o próprio erro ao digitar. Helper `_bannerErro(msg)` compartilhado.
  - **Abastecimento**: valida `data_hora`, `tipo_combustivel`, `litros>0`,
    `valor_total>0` (paridade com `folha.php` L1847-1869). `fk_condutor`
    do web NÃO vai como campo — o backend mobile
    (`BdtApiService::criarAbastecimento`) já grava o condutor logado.
  - **Manutenção**: valida `data_hora_inicio` (required backend web) e
    `descricao` (required backend mobile). `fk_tipo` do web é
    deliberadamente omitido — o `criarManutencao` mobile passa
    `exigirTipo=false` (nasce "Não classificada", admin classifica depois).
  - `NovaOcorrenciaPage` já estava alinhado desde a Fase 1 — usada como
    referência de padrão pros outros dois.

- ✅ **Fotos das ocorrências (Fase 2)** (2026-07-23) — completa a
  Sprint 17 W+M. Backend: 4 endpoints no `BdtApiController`
  (`fotos/upload` multipart, `fotos/listar`, `fotos/obter` — servir
  binário no padrão MSEC.6 com Bearer + ETag + Cache-Control,
  `fotos/excluir`). Ownership em duas camadas: `doc` → `ocorrência`
  → `BDT` → `condutor`. Mobile: dep nova `image_picker ^1.1.2` +
  permissões `CAMERA`/`READ_MEDIA_IMAGES` no `AndroidManifest`.
  Novo `postMultipart`/`postForBytes` no `ApiClient`. Widget
  `FotoOcorrenciaThumb` (cache em memória por docId, baixa binário
  sob demanda). `NovaOcorrenciaPage` ganha card "Fotos" com botão
  "Adicionar" (bottom sheet camera/galeria) + preview em grid
  removível; ao salvar, cria a ocorrência primeiro e faz upload em
  batch (falha em uma foto não invalida a ocorrência). Nova
  `FotoViewerPage` com `InteractiveViewer` (pinch-to-zoom).
  `OcorrenciaDetalhePage` mostra card "Fotos" com grid clicável
  → viewer. Fix técnico no `BdtApiController::input()`: pular
  `getJSON()` em `Content-Type: multipart/form-data` (senão dispara
  `HttpException::forInvalidJSON` no boundary).

- ✅ **Registrar ocorrência do BDT — Fases 1+2 completas** (2026-07-23 e 2026-07-24) —
  condutor abre ocorrência de dentro do BDT em andamento. Segue o
  ARCHITECTURE.md mobile §4.3 (Service categoria API) + §4.7 (Page
  StatefulWidget) + §0 (aditivo, não quebra web).
  - **Backend** (`feature/027-mobile-support`):
    - Novo `App\Services\e_Transporte\OcorrenciaBdtService` — extrai
      CRUD + auditoria do inline do `BDTController::salvarOcorrencia`.
      `BDTController` refatorado pra chamar o service (mesmo
      comportamento web; sem regressão). Fotos ficam de fora
      (dependem de `request->getFile*` — Fase 2).
    - 3 endpoints wrapper thin em `BdtApiController`:
      `POST bdt/ocorrencias/criar` (ownership via
      `assertBdtPertence`; `fk_condutor` sempre gravado como o
      condutor logado — no web era opcional),
      `POST bdt/ocorrencias/excluir` (soft-delete + limpa fotos
      anexadas via `DocumentoService`),
      `POST bdt/ocorrencias/tipos` (catálogo do dropdown).
  - **Mobile** (`main`):
    - Novos métodos em `OcorrenciaService` — `tipos()`, `criar()`,
      `excluir()`. Reusam o modelo `OcorrenciaFiltroItem` já existente.
    - Nova `NovaOcorrenciaPage` — form com dropdown tipo + título +
      descrição + validação inline. Erro do backend vira `formError`
      em `errorContainer`. Ao salvar com sucesso, `Navigator.pop(true)`
      → chamador recarrega.
    - Novo item **"Registrar ocorrência"** no sheet "Ações" da
      `BdtPage` (ícone amarelo `warning_amber_rounded`) — abre a
      rota `/ocorrencia/nova` com `bdtId` como argument; ao voltar
      com `true`, chama `_load(bdtId)`.
  - ✅ **Fase 2 (2026-07-23)** — upload de fotos multipart + preview +
    câmera + galeria full-screen swipeable (Sprint 17 W+M F2). Ver
    entrada "Fotos das ocorrências (Fase 2)" acima. Também ganhou
    edit inline (Sprint 18.1) — condutor não precisa mais apagar e
    refazer se digitou errado.
- ✅ **Histórico institucional de ocorrências (visualização no app)**
  (2026-07-22) — entregue como wrapper fino do `OcorrenciaService`
  do web ([[bdt_uerj_reusar_codigo_web]]) — mesma lista/detalhe/filtros
  que o admin vê em `/transporte/admin/ocorrencias/historico`.
  - **Backend** (`feature/027-mobile-support`):
    - 3 endpoints em `BdtApiController` — wrappers thin:
      `POST bdt/ocorrencias/historico` (aceita filtros veiculo/condutor/
      tipo/de/ate; datas validadas como `YYYY-MM-DD`),
      `POST bdt/ocorrencias/detalhes` (id),
      `POST bdt/ocorrencias/filtros` (retorna as 3 listas de options
      numa chamada só — evita 3 requests da UI).
    - Auth: Bearer + `resolveUserId` (institucional; sem filtro por
      condutor logado por default).
  - **Mobile** (`main`):
    - Models `Ocorrencia` + `OcorrenciaFiltros` (imutáveis, `fromJson`
      tolerante — ver §4.1 do ARCHITECTURE mobile).
    - `OcorrenciaService` (categoria API) — 3 métodos estáticos
      espelhando os endpoints.
    - `HistoricoOcorrenciasPage` — lista com filtros expansíveis
      (dropdowns veículo/condutor/tipo + range de datas), tap abre
      detalhe. Ordem desc por data (mesmo do backend).
    - `OcorrenciaDetalhePage` — cabeçalho amarelo com tipo/título/hora,
      card descrição, card contexto (BDT/veículo/condutor).
    - Acesso pelo menu do avatar: novo callback `onHistoricoOcorrencias`
      em `AppScaffold`/`AppNavbar` → item "Histórico de ocorrências"
      no menu, com `Icons.warning_amber_rounded`. Só a `HomePage`
      passa o callback hoje.
    - Rotas: `/ocorrencias/historico` e `/ocorrencia/detalhe`
      (argument: `int id`).

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
| MSEC | Hardening de segurança pré-piloto (✅ entregue; cresceu de 4 p/ 8 itens) | 11 |
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
