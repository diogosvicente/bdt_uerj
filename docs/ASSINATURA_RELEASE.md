# Assinar o APK de release

Feito uma vez. Depois disso, `flutter build apk --release` já sai assinado.

## Por que isto existe

O projeto vinha assinando o release com a **chave de debug**, que o Android
gera sozinho e que é igual em toda máquina: caminho conhecido, alias conhecido
(`androiddebugkey`) e senha conhecida (`android`).

Quem tiver o APK consegue decompilar, alterar e assinar de novo com essa mesma
chave. O Android aceita o resultado como **atualização** do app instalado,
porque para ele a assinatura confere. Um app que preenche boletim oficial da
UERJ, com foto, localização e assinatura do condutor, não pode ficar nessa
situação.

## O que fazer

### 1. Gerar o keystore

Escolha uma senha forte e guarde-a no gerenciador de senhas da equipe **antes**
de rodar o comando. O `keytool` vem com o JDK.

```
keytool -genkeypair -v \
  -keystore C:/caminho/seguro/bdt-uerj-release.jks \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias bdt-uerj
```

Ele pergunta a senha e alguns dados de identificação (nome, unidade,
localidade). Esses dados aparecem no certificado; use os da UERJ.

O `-validity 10000` são cerca de 27 anos. Não é exagero: uma chave que expira
impede publicar atualização, e trocar de chave depois é pior do que parece
(ver o aviso no fim).

**Não coloque o `.jks` dentro do repositório.** Um lugar fora da pasta do
projeto, com backup.

### 2. Apontar o projeto para ele

Copie o modelo e preencha:

```
cp android/key.properties.example android/key.properties
```

Quatro linhas: `storePassword`, `keyPassword`, `keyAlias` e `storeFile`. O
`storeFile` de preferência absoluto; relativo resolve a partir de
`android/app/`, que não é onde a maioria espera.

O `.gitignore` do Flutter já barra `key.properties`, `*.jks` e `*.keystore`.
Confira com `git status` mesmo assim.

### 3. Conferir que pegou

```
flutter build apk --release
```

Se o `android/key.properties` não for encontrado, o build **não quebra**: cai
para a chave de debug e imprime

```
AVISO: android/key.properties nao encontrado. O release sera assinado com a
CHAVE DE DEBUG, que e publica. Nao distribua este APK.
```

A queda existe para `flutter run --release` continuar funcionando em máquina
sem a chave. Se esse aviso aparecer num build de distribuição, o APK não serve.

Para confirmar pelo próprio arquivo, use o **apksigner**, e não o
`keytool`. O `keytool -printcert -jarfile` só lê assinatura v1 (JAR), e o
Flutter assina em v2: nesse arquivo ele responde "não é um arquivo jar
assinado", que parece defeito e não é.

```
%SDK%/build-tools/<versao>/apksigner verify -v --print-certs   build/app/outputs/flutter-apk/app-release.apk
```

O caminho do SDK está em `android/local.properties`, na linha `sdk.dir`.

Procure a linha `certificate DN`. Hoje, sem a chave, ela sai assim:

```
Verified using v2 scheme (APK Signature Scheme v2): true
V2 Signer: certificate DN: C=US, O=Android, CN=Android Debug
```

Depois da chave, tem que mostrar os dados que você digitou no `keytool`.

## Não é certificado de autoridade certificadora

A assinatura de app Android é **autoassinada**. O `keytool` cria a chave e o
certificado ali mesmo, e os dados de identificação que ele pergunta são texto
que você digita: não vêm de ninguém, não são conferidos por ninguém.

Certificado da ICP-Brasil, e-CNPJ, ou o certificado TLS do domínio da UERJ são
outra coisa e não servem aqui. O Android não valida cadeia de autoridade em
assinatura de app: ele guarda o certificado da primeira instalação e exige que
a atualização traga exatamente o mesmo.

E usar um certificado de autoridade seria pior do que inútil: eles **expiram**
em um a três anos, e chave expirada impede publicar atualização. É por isso que
o comando acima usa `-validity 10000`.

Vale perguntar ao DGTI se já existe um keystore institucional de aplicativos
Android. Se existir, o time decide entre reaproveitar ou criar um só para o
BDT (o Google recomenda uma chave por app). Se não existir, este é o primeiro,
e o cuidado de guarda descrito abaixo passa a valer para a UERJ inteira.

## O aviso que importa

Perder o `.jks` ou a senha impede publicar atualização do app **para sempre**.
O Android só aceita atualização assinada com a mesma chave; a saída seria
distribuir outro app, com outro `applicationId`, e pedir a cada condutor que
desinstale o antigo e instale o novo.

Guarde o `.jks` e a senha em dois lugares, e não só na máquina de quem gerou.

## Nota sobre a troca de chave

Este app já foi distribuído assinado com a chave de debug. Quem tiver essa
versão instalada **não** vai conseguir atualizar por cima, porque a assinatura
muda: vai precisar desinstalar e instalar de novo. Vale avisar os condutores
junto com a primeira versão assinada de verdade.
