# Retomada — o que falta no BDT Mobile

**Congelado em:** 2026-07-30
**Motivo da parada:** o app está entregável para os primeiros testes com
condutores. O que resta ou depende de decisão sua, ou depende de terceiros,
ou é backlog declarado — nada está pela metade.

Este documento existe para retomar **frio**, semanas depois, sem reler o
histórico. O detalhe técnico de cada entrega continua no
[SPRINTS_MOBILE.md](SPRINTS_MOBILE.md); aqui fica só o que **não** foi feito
e por quê.

---

## 1. Estado dos repositórios

| Repo | Branch | HEAD | Situação |
|---|---|---|---|
| `bdt_uerj` (Flutter) | `main` | `4435211` | limpo, sincronizado |
| `e-prefeitura` (CI4) | `feature/027-mobile-support` | `8cfa4a91` | limpo, sincronizado |

As duas branches fecham juntas — a do backend **não** foi mergeada em
`development` ainda. Antes de rodar o app contra o servidor de dev, confira
que o backend está nessa branch: já aconteceu de estar em `development`, sem
nenhum endpoint mobile, e o sintoma foi "o app não faz mais nada".

> ⚠️ **Git do backend roda por dentro do WSL, sempre.** Pelo Windows, o git
> reescreve os arquivos em CRLF e trava o checkout. O mobile não tem esse
> problema (tem `.gitattributes`).

**Migrations do backend estão aplicadas no dev.** A última é
`2026-07-30-160000_BackfillSolicitanteEUnidadeCascasBdt`. Em outro ambiente,
rodar `php spark migrate` antes de testar — várias correções recentes
dependem de backfill.

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

## 3. Pendências que dependem de você

### 3.1 MSEC.9 — Auto Backup do Android está ligado 🔴

**Recomendo tratar antes do piloto**, porque envolve dado de localização de
pessoa real.

`android:allowBackup` **não está declarado** em nenhum manifest, e o padrão
do Android é `true`. O Auto Backup do Google copia hoje, para a conta do
condutor:

- a foto dele cacheada em `getApplicationDocumentsDirectory()`;
- o `SharedPreferences` (preferências e flags de migração);
- **o SQLite da fila de GPS** (`LocationQueueDb` — trajetos);
- o `flutter_secure_storage` (`EncryptedSharedPreferences`).

O token na prática sobrevive, porque a chave de cifra fica no Keystore e não
é copiada — um restore devolve texto ilegível. Mas o ciphertext sai do
aparelho, e prefs e SQLite estão em claro.

**Duas saídas:**

1. `android:allowBackup="false"` — uma linha, resolve tudo, e o condutor
   perde backup/restore ao trocar de aparelho.
2. `dataExtractionRules` — mantém o backup e exclui só o sensível. É o
   mecanismo certo para `targetSdk = 36` (o `fullBackupContent` antigo não
   vale mais). Exige acertar `cloud-backup` e `device-transfer` em separado.

**Não implementei** porque as duas mudam comportamento visível para o
condutor ou exigem decidir arquivo a arquivo — é chamada de produto.
Estimativa da opção 2: ~30 linhas mais um teste de restore.

**Onde mexer:** `android/app/src/main/AndroidManifest.xml`.

### 3.2 Apagar um BDT direto deixa a solicitação-casca para trás 🟡

A casca é criada por `BdtSemSolicitacaoService::criarEntradaAgenda` como
registro independente. Excluir o BDT **não** a remove: sobra uma solicitação
"Agendado" apontando para um BDT que não existe mais. Vale igual para a
casca de Pré-BDT e para a `avulso`.

No dev há 14 cascas, várias de BDTs já apagados. **Não deletei**: não dá
para distinguir com segurança as minhas de teste das suas (uma é a
`TRN-2026-0018`), e apagar solicitação alheia é pior que deixar lixo visível.

**Duas saídas, e não escolhi por você:**

1. Cascatear o soft-delete do BDT para a casca.
2. Manter a casca como registro histórico — o BDT existiu e foi agendado, e
   a solicitação documenta isso. Combina com a decisão que você já tomou de
   manter a casca visível, mas aí a lista precisa marcar "BDT excluído", e
   hoje ela não marca nada.

**Não tracei o caminho de exclusão do BDT** — quem retomar precisa achar
onde o delete acontece antes de decidir onde cascatear.

---

## 4. Pendências que dependem de terceiros

### 4.1 Enumeração de CPF no `login()` 🟡

O `login()` ainda responde "Usuário não encontrado." quando o CPF não
existe, e "CPF ou senha inválidos." quando existe — dá para enumerar CPFs de
servidores. O `esqueci-senha` que fiz já nasceu sem o vazamento (resposta
idêntica exista ou não o usuário; os motivos reais vão só para o log).

Fechar exige **alinhar a mensagem com o time do web**: é a mesma tela que
eles usam, e mudar de um lado só deixaria a UX inconsistente.

**Onde:** `AuthApiController::login` (mobile) e `LoginController` (web), no
`e-prefeitura`.

### 4.2 Bug aberto: "trecho do mobile some ao adicionar outro pela web" 🟡

Relatado em 21/07. Reproduzi o fluxo exato por script PHP e **não
reproduzi** — os três trechos coexistem no banco, no `bdt/detalhes` do
mobile e no sync.

**Para destravar, preciso de:** o `ano/numero` do BDT em que você viu
acontecer, e a sequência exata de cliques. Sem isso não há o que investigar.

Vale testar de novo no piloto: várias correções de itinerário entraram
depois do relato, e é possível que já tenha morrido junto.

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
