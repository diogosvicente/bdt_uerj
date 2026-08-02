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
| `bdt_uerj` (Flutter) | `main` | `9924daf` (+ o commit deste doc) | limpo, sincronizado |
| `e-prefeitura` (CI4) | `development` | `ea173e7c` | limpo, sincronizado |

> ✅ **Produção está no ar** (2026-08-01). O PR #88 foi mergeado em
> `development` (`8d7e11f6`), publicado, e as migrations rodaram. As 14
> rotas mobile que eu sondava como 404 agora respondem. **A branch
> `feature/027-mobile-support` não é mais o lugar de trabalho** — o que veio
> depois do merge foi commitado direto em `development`.

**Três coisas mordidas no primeiro contato com produção**, todas resolvidas
e detalhadas no [SPRINTS_MOBILE.md](SPRINTS_MOBILE.md) — vale conhecer,
porque nenhuma reproduzia em desenvolvimento:

1. **O header `Authorization` era descartado.** Produção está atrás de
   openresty e o `.htaccess` de lá não tinha a regra de repasse. Sintoma:
   login OK e todo o resto 401, enquanto `token/refresh` — único que recebe
   a credencial no corpo — funcionava. Resolvido no `.htaccess` do servidor.
2. **O captcha não aparecia**: `Filters.php` de produção estava sem
   `transporte/api/captcha/*` na lista de exceções de CSRF.
3. **A foto do condutor vinha errada**: o endpoint pegava o primeiro
   documento do condutor sem filtrar tipo, e podia devolver a CNH.

> ⚠️ **O `.htaccess` de produção é diferente do versionado** — lá são 11
> linhas mínimas mais a regra de `Authorization`; no repo é o padrão do
> CodeIgniter. E o `deploy.sh` **não** o exclui do espelhamento. Se algum
> dia o mirror pegá-lo, derruba o repasse **e** o roteamento do site.
> Prevenção de uma linha, no `deploy.config`:
>
> ```
> EXTRA_EXCLUDES="app/Config/App.php app/Config/Database.php .htaccess"
> ```

> ⚠️ **Git do backend roda por dentro do WSL, sempre.** Pelo Windows, o git
> reescreve os arquivos em CRLF e trava o checkout. O mobile não tem esse
> problema (tem `.gitattributes`).

**Migrations do backend estão aplicadas no dev.** A última é
`2026-07-30-200000_CorrigeDescricaoFotoCargaBdtDireto`. Em outro ambiente, rodar
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
- ✅ **Pinning de certificado — validado em campo (2026-08-01).** O app
  rodou contra `www.e-prefeitura.uerj.br` num celular real e as requisições
  completaram o handshake TLS. Antes disso, as impressões SHA-256 da
  intermediária (`RNP ICPEdu GR46 OV TLS CA 2025`, `E1:07:47…`) e da raiz
  (`GlobalSign Root R46`, `4F:A3:12…`) já batiam com o
  `assets/certs/rnp_icpedu_chain.pem`. Item encerrado. Se um dia der erro
  de TLS, o escape hatch é `--dart-define=SSL_PINNING=off`.

- 🟡 **GPS em background por uma viagem inteira — NÃO testado.** É o teste
  que mais importa e o único cenário sério ainda em aberto. O fix de
  renovação de token no isolate de background (`9924daf`) foi validado por
  análise e build, não por uso real.
  **Como testar**: iniciar um trecho, deixar o celular no bolso com o app em
  segundo plano por **mais de 20 minutos** (o access token dura 15), e depois
  conferir se os pontos do intervalo chegaram. Era exatamente aí que o
  trajeto sumia antes — silenciosamente, com a notificação ativa.

- 🟡 **O APK no celular está desatualizado.** O aparelho tem um build
  anterior a `3401553` e `9924daf` — ou seja, **sem** o fix do GPS em
  background. Instalar o build novo antes de qualquer teste de viagem.
- **Restore de backup com as regras novas (MSEC.9).** As exclusões foram
  verificadas de forma indireta: o `flutter build apk` resolve as
  referências `@xml/...` (referência inexistente quebraria o build) e os
  dois arquivos saem empacotados em `res/xml/` do APK. Não consegui ler o
  manifest binário de volta — não há `aapt2` neste SDK. **O teste definitivo
  é um ciclo real**: fazer backup, restaurar num aparelho e conferir que o
  app pede login de novo e que a fila de GPS voltou vazia.

---

## 6. Higiene — ✅ resolvida em 2026-07-30

**Soft-delete ignorado: revisão concluída.** O bug do "BDT zumbi" era uma
**classe** de defeito — consulta montada com o query builder cru
(`$this->db->table(...)`) **não** aplica o soft-delete do model, ao
contrário de `find()`. Corrigidas 8 ocorrências em `trnsp_bdt` e, na
revisão das outras 33 tabelas com soft-delete do módulo, mais **2**:

- **`BdtViagemService::getViagemCompleta`** — ocorrência excluída ainda
  saía no PDF do BDT. Era assimetria pura: no MESMO array, a consulta de
  manutenções logo abaixo sempre filtrou.
- **`BdtRepository::getOrigemBdt`** (trechos) — trecho e dia excluídos
  apareciam no itinerário do modal "Origem". O fallback de Pré-BDT logo
  abaixo já filtrava; a consulta principal era a fora do padrão.

**O critério que separou defeito de comportamento correto:** o filtro
importa quando a consulta **enumera filhos** — trecho, ocorrência,
passageiro — porque o filho pode ser apagado com o pai vivo. Consulta que
busca por um id já validado pelo caller é apenas defensiva, e consulta de
**identificação histórica** deve mesmo enxergar o excluído: se
`BdtHistoricoService::nomeCondutor` filtrasse, um BDT antigo passaria a
exibir "Condutor #12" no lugar do nome. As 13 restantes caem nessas duas
categorias e ficam como estão, deliberadamente.

> ⚠️ Contra-exemplo, para não "corrigir" por simetria:
> `BdtModel::getProximoNumeroParaAno` usa o builder cru **de propósito** e
> os excluídos **precisam** contar — há `UNIQUE(ano, numero)` e reusar o
> número de um BDT apagado colide no INSERT.

Verificado com fixture em transação e rollback: trecho e ocorrência
recém-criados aparecem (1), somem ao serem excluídos (0).

*(Os trailers `Co-Authored-By` no `e-prefeitura` saíram desta lista — o
usuário decidiu em 30/07 que não importam mais.)*

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
