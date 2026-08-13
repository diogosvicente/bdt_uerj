# bdt_uerj — instruções do projeto

## Regra inegociável: mobile NÃO quebra o web

O `e-prefeitura` (web) está **em produção** atendendo usuários reais da UERJ.
Todo esforço mobile é **aditivo**. Ver `docs/ARCHITECTURE.md` §0 para a lista
completa do que pode e do que não pode.

Em uma linha: criar coisa nova (controller/rota/service/repository, campo
opcional no payload, método novo, migration aditiva) é seguro. Renomear,
mudar assinatura, remover campo ou **alterar regra de negócio existente** para
"ficar melhor no mobile" não é — vira tarefa web separada.

## Arquitetura: leia antes de escrever código

`docs/ARCHITECTURE.md` é a referência **autoritativa**. O resumo abaixo serve
para reconhecer a camada certa; quando divergir do documento, vale o documento.

**Services (§3) — todo arquivo em `lib/services/` cai em exatamente UMA
categoria.** A convenção é o comportamento, não o sufixo do nome. Se um service
cruzou categorias, quebre em dois.

| Categoria | O que faz | Não pode |
|---|---|---|
| **API** | Chama endpoint HTTP, devolve `Model`/`Result` tipado | Persistir estado local ou tocar plugin nativo |
| **STORAGE** | Persiste local (Preferences, secure, SQLite) | Chamar HTTP direto |
| **DOMAIN** | Regra pura, sem IO | Depender de plugin nativo |
| **PLATFORM** | Integra com OS/plugins | Conter regra de negócio complexa |

**UI (§3):**
- Tela é `StatefulWidget` (`*Page`) em `lib/pages/`.
- Tela **nunca** chama `ApiClient` direto — passa por Service da categoria API.
- Tela **nunca** decide olhando `Map<String,dynamic>` — converte para `Model`
  (`.fromJson`) o quanto antes.
- `lib/widgets/` não contém regra de negócio: recebe callbacks e valores prontos.

**Model (§4.1):** DTO imutável.

## Git

- Executar `add`, `commit` e `push`. Este projeto trabalha direto na `main`
  (confirmado pelo usuário como seguro aqui).
- **Nunca** incluir o trailer `Co-Authored-By: Claude`.
