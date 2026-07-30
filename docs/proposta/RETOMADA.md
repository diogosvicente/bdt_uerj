# Retomada — o que falta no BDT Mobile

**Congelado em:** 2026-07-30 · **atualizado no mesmo dia**, depois de
executar os pontos 3 e 4.
**Motivo da parada:** o app está entregável para os primeiros testes com
condutores. **Não há mais pendência de segurança nem decisão sua em aberto**
— o que resta é backlog declarado e higiene de repositório.

Este documento existe para retomar **frio**, semanas depois, sem reler o
histórico. O detalhe técnico de cada entrega continua no
[SPRINTS_MOBILE.md](SPRINTS_MOBILE.md); aqui fica só o que **não** foi feito
e por quê.

---

## 1. Estado dos repositórios

| Repo | Branch | HEAD | Situação |
|---|---|---|---|
| `bdt_uerj` (Flutter) | `main` | `8d8f1f1` | limpo, sincronizado |
| `e-prefeitura` (CI4) | `feature/027-mobile-support` | `5d1856cb` | limpo, sincronizado |

As duas branches fecham juntas — a do backend **não** foi mergeada em
`development` ainda. Antes de rodar o app contra o servidor de dev, confira
que o backend está nessa branch: já aconteceu de estar em `development`, sem
nenhum endpoint mobile, e o sintoma foi "o app não faz mais nada".

> ⚠️ **Git do backend roda por dentro do WSL, sempre.** Pelo Windows, o git
> reescreve os arquivos em CRLF e trava o checkout. O mobile não tem esse
> problema (tem `.gitattributes`).

**Migrations do backend estão aplicadas no dev.** A última é
`2026-07-30-180000_SoftDeleteCascasBdtOrfas`. Em outro ambiente, rodar
`php spark migrate` antes de testar — várias correções recentes dependem de
backfill.

---

## 2. O que está pronto para o teste

Fluxos completos, testados manualmente pelo usuário e verificados em banco:

- **Login**, com captcha, rate limit (10/min por CPF) e "esqueci minha senha".
- **Pré-BDT** — criar, editar (traz a carga declarada), aprovar e recusar.
- **BDT direto** ("sem solicitação") — restrito a admin ou ao papel
  `Criar BDT sem Solicitação`; permite abrir para si ou para outro condutor,
  com trechos e carga na própria criação.
- **Execução do BDT** — marcos com assinatura, trechos, abastecimento,
  manutenção, ocorrência, divergência, todos com fotos.
- **GPS** — duplo motor (timer + foreground service) com fila SQLite,
  sobrevive a offline, a fechar o app e a reboot; dedup no backend.
- **Web** — o que o app grava aparece na Agenda, na folha, no PDF, no modal
  Origem e na tela de acompanhamento, com a carga e as fotos.

---

## 3 e 4. Resolvidos em 2026-07-30 — nada a retomar

As duas seções originais ("pendências que dependem de você" e "que dependem
de terceiros") foram executadas. Ficam registradas aqui só para quem lembrar
delas não procurar em vão. Detalhe técnico no `SPRINTS_MOBILE.md`.

- **MSEC.9 — Auto Backup do Android** ✅ Backup mantido ligado, com o
  sensível excluído em `backup_rules.xml` (API 24–30) **e**
  `data_extraction_rules.xml` (31+, nas seções `cloud-backup` e
  `device-transfer`). Fora do backup: token, preferências, fila de GPS e
  foto do condutor.
- **Casca órfã ao apagar BDT** ✅ — **o diagnóstico original estava errado**:
  o cascade já existia desde a W13. O que faltava era ele cobrir só um dos
  três tipos de casca e um dos dois caminhos de ligação. Corrigido, e as 10
  órfãs do banco (vindas de `DELETE` direto em teste, não do fluxo de
  exclusão) foram arquivadas por migration.
- **Enumeração de CPF no `login()`** ✅ — não precisou do time do web: o
  endpoint do app é próprio (`AuthApiController::login`), então dava para
  fechar sem tocar na tela deles. Eram **três** desfechos distinguíveis, não
  dois, e a mensagem idêntica não bastava — o caminho "CPF não existe"
  respondia 270× mais rápido, e agora tem equalização por hash descartável.
  **O `login()` da web segue vazando** — lá continua sendo conversa com eles.
- **Bug "trecho some ao adicionar outro pela web"** ✅ — confirmado resolvido
  por você. Nenhum commit fechou o item diretamente; morreu junto com as
  correções de itinerário da Sprint 15. **A causa raiz nunca foi isolada** —
  se reaparecer, começar pela relação entre a solicitação `avulso` e a casca.

---

## 5. O que NÃO foi verificado (o teste deve cobrir)

Registro para ninguém confundir "entregue" com "testado ponta a ponta":

- **O e-mail do "esqueci minha senha" nunca foi entregue.** O SMTP do dev
  não sobe aqui. Verifiquei até a geração do token no banco; a chegada na
  caixa, não. O helper é o mesmo do web (`enviar_email_reset_senha`), então
  se o web entrega, este entrega — mas confirme no primeiro teste real.
- **As telas web que mexi** (folha, PDF, modal Origem, card Solicitante)
  foram conferidas por lint, query em banco e render — não abri as páginas
  autenticadas. Quem validou de fato foi você, pelos prints.
- **Pinning de certificado em rede real.** Verifiquei com `openssl` que a
  cadeia da RNP valida e que CA de fora é recusada, mas o app não rodou
  contra produção com o pinning ativo. Se der erro de TLS no piloto, o
  escape hatch é buildar com `--dart-define=SSL_PINNING=off` — e aí o
  problema é a cadeia, não o app.
- **Restore de backup com as regras novas (MSEC.9).** As exclusões foram
  verificadas de forma indireta: o `flutter build apk` resolve as
  referências `@xml/...` (referência inexistente quebraria o build) e os
  dois arquivos saem empacotados em `res/xml/` do APK. Não consegui ler o
  manifest binário de volta — não há `aapt2` neste SDK. **O teste definitivo
  é um ciclo real**: fazer backup, restaurar num aparelho e conferir que o
  app pede login de novo e que a fila de GPS voltou vazia.

---

## 6. Higiene pendente

**Trailers `Co-Authored-By: Claude` no `e-prefeitura`**: 20 commits numa
branch e 16 noutra ainda os carregam. Te mostrei as opções e você não
escolheu; segue lá. No `bdt_uerj` já está limpo.

Relacionado: o GitHub continua listando "claude" como contribuidor na
sidebar do repo mesmo com o Insights já limpo — é cache do lado deles, e a
saída é abrir ticket no Support.

---

## 7. Backlog declarado (não é dívida)

Do `SPRINTS_MOBILE.md`, sem previsão e sem bloqueio:

- ⏳ **Trabalho de campo — exibição do PDF parseado e confirmação**, depende
  do parser do web ficar pronto.
- 3º alerta — status automático ao sistema (40h), adiado por falso-positivo.
- Auto-preenchimento da ocorrência (8h), adiado.
- Passageiro assinar no próprio celular — exige o aparelho do passageiro,
  não o do condutor.

---

## 8. Como retomar

```bash
cd C:/Users/Diogo/Documents/bdt_uerj && git pull && flutter pub get
```

Backend (**de dentro do WSL**):

```bash
cd /home/diogo/docker-php-mariadb-prefei/htdocs/e-prefeitura && git checkout feature/027-mobile-support && git pull
```

Migrations:

```bash
docker exec -w /var/www/html/e-prefeitura apache php spark migrate
```

Para bater endpoint por `curl`, o Bearer é **obrigatório** desde o MSEC.2
Fase 2 — não existe mais fallback por `usuario_id` no body. Token de dev:

```bash
docker exec -i mariadb mysql -u root -proot -sN eprefeitura -e "SELECT token FROM tokens WHERE id_usuario=46 AND expira_em > NOW() LIMIT 1;"
```

**Convenções que valem para qualquer mudança nova** — estão em memória, mas
repito porque são as que mais custam se esquecidas:

- Consultar o `ARCHITECTURE.md` do repo certo antes de criar ou refatorar
  arquivo; não inventar padrão onde já existe um.
- Backend para o mobile é **aditivo**: nunca renomear, remover ou mudar tipo
  de rota/coluna/campo que a web já usa.
- Quando a web já tem service/controller do fluxo, o backend mobile é
  **wrapper fino** em cima dele.
- Datetime: **UTC no fio, BRT só na UI** (`api_datetime_helper` no PHP,
  `DateFmt.apiIsoUtc` no Dart).
- **Sem travas, só alertas**: regra de escopo nunca bloqueia o condutor.
- Todo achado fora de escopo entra no `SPRINTS_MOBILE.md`, não só no commit.
