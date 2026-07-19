# Plano de Sprints — Repo BDT-Flutter (app mobile)

_Extrato do plano geral só com os itens que serão implementados no app Flutter (repo separado)._

> **📍 Fonte da verdade:** este doc **vive aqui** no repo `bdt_uerj` a partir da branch `feature/m0-m1-login-ux` (Sprint M0/M1 iniciada em 2026-07-18). A cópia no repo `e-prefeitura` (`docs/proposta/SPRINTS_MOBILE.md`) fica como referência histórica.

> Para o plano do repo `e-prefeitura` (web), ver `SPRINTS_WEB.md`.
> Para a lista de cada item com plataforma, ver `MVP_Selector.xlsx` aba **Itens** (coluna **Plataforma**: filtre por **Mobile** ou **Web+Mobile**).

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

## Sprint M2 📱 — GPS (~64h)
**Equivalente à Sprint 3 do plano web.**

**Objetivo:** rastreamento confiável mesmo com celular bloqueado ou sem internet.

- UI de origem/destino no app (visual melhor) — 8h
- Corrigir saltos espúrios de GPS (filtragem de outliers) — 16h
- GPS em background + sync offline (cache local + reenvio coerente) — 40h

> ⚠️ Item de **maior risco** do MVP mobile (V=65%, R=65%). Pede POC dedicada antes da implementação completa — Doze/App Standby do Android + Background Modes do iOS são notoriamente restritivos.

---

## Sprint M3 📱 — Pré-BDT criação (~32h)
**Paralela à Sprint 1 do plano web.**

**Objetivo:** condutor pode pré-criar BDT no app para saídas urgentes.

- Pré-BDT — criação pelo condutor — 32h

> Depende de:
> - Endpoint de criação de pré-BDT no web (Sprint 1 web)
> - Role `Criar Pré-BDT` ativo no usuário (Sprint 0 web — já feito)

---

## Sprint M4 📱 — Validação atendimento (parte 1) (~88h)
**Equivalente à Sprint 10 do plano web.**

**Objetivo:** condutor formaliza início e conclusão do atendimento no app.

- Validação de INÍCIO do atendimento (embarque) — formulário no app — 40h
- Assinatura touch no tablet/celular do condutor + identificar signatário — 24h
- Validação de CONCLUSÃO + feedback do condutor — 24h

---

## Sprint M5 📱 — Alertas inteligentes (~40h)
**Equivalente à Sprint 18 do plano web.**

**Objetivo:** notificar o condutor com antecedência da saída.

- 1º Alerta — preparação (1h antes da saída programada) — 24h
- 2º Alerta — deslocamento (30min antes) — 16h

> Integração opcional com WhatsApp depende da pesquisa de viabilidade feita na Sprint 17 do plano web.

---

## 🔀 Trabalho complementar (Web+Mobile) — encaixa nas sprints acima

Os 13 itens Web+Mobile precisam de implementação parcial no app. O esforço já está contado no plano web (sprint do "lado web") — aqui vai a **lista do que toca no Flutter**, organizada pela sprint web correspondente:

> ⚠️ **Redefinição do BDT (nova W7 web):** o web passou a tratar o **BDT como uma VIAGEM** (veículo+condutor, dia/período) que atende **uma ou mais solicitações** (M:N), com **local de embarque + assinatura por solicitação** dentro do BDT e o **local de embarque definido pelo admin**. A consolidação fica no **Painel de BDTs** (filtros + folha de despacho em PDF) — **não** há entidade "Programação" separada. Isso muda o modelo que o app consome: a **criação de BDT/Pré-BDT (M3)** e o **"BDT sem solicitação"** (abaixo) seguem o **BDT = viagem**. As referências "**Sprint N web**" abaixo usam a **numeração do plano original** — **não** mudam com a renumeração dos W-labels no web (a antiga W7 virou W8, …, W15 → W16; foi inserida a nova W7 = Redefinição do BDT).

### Da Sprint 1 web (Pré-BDT)
- Modal de informações de segurança no BDT (telas + texto)

### Da Sprint 4 web (Trabalho de campo)
- Marcar presença/ausência de passageiros
- Trabalho de campo — exibição do PDF parseado e confirmação

### Da Sprint 5 web (Marcos)
- Marcos PARTIDA / APRESENTAR-SE / PASSAGEIRO (state machine UI)
- Marco HORA DE SAÍDA (UX no app)

### Da Sprint 6 web (Cargas)
- Cancelar/redirecionar BDT por divergência de carga (UX do condutor)

### Da Sprint 9 web (Viagens avulsas)
- Viagens avulsas no BDT (UX de adicionar)
- Refinar adição de trechos (gaps de UX)

### Da Sprint 11 web (Anexo carga)
- Anexo obrigatório de fotos para carga (validação no app)

### Da Sprint 15 web (BDT sem solicitação)
- Veículo/condutor reais ≠ agendados (UX de checkup no app)

### Da Sprint 17 web (Ocorrências)
- Anexos de fotos em ocorrências/manutenção (extensão no app)
- Histórico institucional de ocorrências (visualização no app)

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
