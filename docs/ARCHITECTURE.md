# Contexto do App BDT UERJ (Flutter)

> Documento de referência sobre a stack, arquitetura e padrão de criação
> de novas features do app **mobile**. Use este guia sempre que for
> implementar uma nova funcionalidade no projeto.
>
> **Contraparte web**: `e-prefeitura/docs/ARCHITECTURE.md`. Muitos itens do
> app dependem de endpoints web — quando isso acontece, o item vive nos dois
> repos (branch `main` aqui + branch `feature/027-mobile-support` no
> `e-prefeitura`).

---

## 1. Stack Tecnológica

### Core
| Camada | Tecnologia | Versão |
|---|---|---|
| Linguagem | Dart | `^3.9.2` |
| Framework | **Flutter** (stable) | `3.41.9` (Dart 3.11.5) |
| Estilo visual | Material 3 (`useMaterial3: true`) | — |
| Locale | `pt_BR` fixo (`flutter_localizations`) | — |

### Dependências principais (`pubspec.yaml`)
| Package | Uso |
|---|---|
| `http` | Cliente HTTP (via wrapper `lib/api/api_client.dart`) |
| `shared_preferences` | Preferências e estado leve não-sensível (`token`, flags, `usuario_id`) |
| `flutter_secure_storage` | Credenciais sensíveis (Android Keystore / iOS Keychain) — **senha** |
| `geolocator` | Coleta de GPS (stream + one-shot) |
| `flutter_background_service` | Foreground service Android (GPS com tela bloqueada) |
| `flutter_local_notifications` | Notificação persistente do foreground service |
| `permission_handler` | Permissões avançadas (bg location, ignore battery) |
| `sqflite` + `path` | Fila offline de pontos GPS |
| `connectivity_plus` | Estado da rede (chip online/offline) |
| `intl` | Formatação de datas/números pt-BR |

### Ambientes
- Configuração de backend via **`--dart-define=APP_ENV=...`** (default `production`).
- Perfis prontos no `.vscode/launch.json`: **Dev localhost / emulator / wsl** e **Prod**.
- Detalhes em `lib/api/api_client.dart` (§ mais adiante).

---

## 2. Estrutura de Pastas

```
lib/
├── api/                       Cliente HTTP e bootstrap de SSL
│   ├── api_client.dart        Wrapper de `http.post` + baseUrl por ambiente
│   └── ssl_bootstrap.dart     Instala a CA da RNP ICPEdu (obrigatório antes de qualquer HTTPS)
│
├── models/                    DTOs tipados — a linguagem dos objetos de domínio
│   └── bdt_resumo.dart
│
├── services/                  Fachadas — dividem-se por FUNÇÃO:
│   ├── auth_service.dart              (API)     Login/logout/verify token
│   ├── bdt_service.dart               (API)     Endpoints do BDT
│   ├── captcha_service.dart           (API)     Endpoints do captcha
│   ├── credentials_storage.dart       (STORAGE) Senha em secure storage + CPF/flags em SharedPrefs
│   ├── location_queue_db.dart         (STORAGE) SQLite da fila offline de GPS
│   ├── location_service.dart          (PLATFORM) Permissões de GPS + posição one-shot
│   ├── location_outlier_filter.dart   (DOMAIN)  Regras puras para descartar pontos ruins
│   ├── gps_live_service.dart          (DOMAIN)  Orquestra Timer + BackgroundLocationService
│   └── background_location_service.dart (PLATFORM) Foreground service Android
│
├── pages/                     Telas — cada uma é um StatefulWidget que orquestra services
│   ├── login_page.dart
│   ├── home_page.dart
│   ├── bdt_page.dart
│   ├── bdt_form_page.dart
│   ├── pre_bdt_form_page.dart
│   ├── abastecimento_form_page.dart
│   └── trecho_extra_form_page.dart
│
├── widgets/                   Componentes de UI reutilizáveis (SEM lógica de domínio)
│   ├── app_navbar.dart
│   ├── app_scaffold.dart
│   ├── captcha_field.dart
│   └── loading.dart
│
├── formatters/                `TextInputFormatter` customizados
│   └── cpf_input_formatter.dart
│
├── utils/                     Helpers puros (log, formatação, etc.)
│   ├── logger.dart            Log unificado (dev.log + print, com tag)
│   └── date_fmt.dart          Helpers de data/hora
│
├── theme/                     Design tokens
│   └── app_theme.dart         Cores, tipografia, ThemeData
│
└── main.dart                  Bootstrap (SSL, background) + rotas nomeadas + MaterialApp

android/, ios/, assets/        Nativo e recursos
docs/                          Este ARCHITECTURE.md + SPRINTS_MOBILE.md
```

---

## 3. Arquitetura em Camadas

### Visão geral do fluxo

```
┌────────────────┐
│  Page/Widget   │  (LoginPage — StatefulWidget, orquestra a tela)
└───────┬────────┘
        │  await AuthService.login(cpf, senha, ...)
        ▼
┌────────────────┐
│  Service       │  Fachada com tipo de retorno claro (Model/Result).
│  (categoria: API, STORAGE, DOMAIN ou PLATFORM)
└───────┬────────┘
        │
    ┌───┴────────────────────────────────────────────────┐
    ▼                          ▼                         ▼
┌────────────┐        ┌────────────────┐         ┌────────────────┐
│ ApiClient  │        │ Storage        │         │ Platform       │
│ (HTTP)     │        │ (Prefs/Secure/ │         │ (Geolocator/   │
│            │        │  sqflite)      │         │  ForegroundSvc)│
└────────────┘        └────────────────┘         └────────────────┘
        │
        ▼
┌────────────┐
│  Backend   │  https://www.e-prefeitura.uerj.br
└────────────┘
```

### Categorias de service — regra de ouro

> Todo arquivo em `lib/services/` cai em **exatamente uma** das 4 categorias abaixo.
> A convenção é o **comportamento**, não o sufixo do nome.

| Categoria | O que faz | Depende de | Não pode |
|---|---|---|---|
| **API** | Chama endpoint HTTP, devolve `Model` ou `Result` tipado | `ApiClient` | Persistir estado local ou tocar em plugins nativos |
| **STORAGE** | Persiste local (Preferences, secure, SQLite) | Plugins de storage | Chamar HTTP direto (delega pra Service API) |
| **DOMAIN** | Regra pura sem IO (filtro, cálculo, orquestração) | Apenas Dart / outros Services | Depender de plugin nativo |
| **PLATFORM** | Integra com OS/plugins (permissões, foreground service, GPS) | Plugins nativos | Conter lógica de negócio complexa (delega ao DOMAIN) |

Um mesmo service **não deve** cruzar categorias. Se cruzou, quebre em dois.

### Regras UI

- Toda tela é um `StatefulWidget` (`*Page`) em `lib/pages/`.
- A tela **nunca** chama `ApiClient.post()` direto — passa por um Service da categoria **API**.
- A tela **nunca** decide UI só olhando `Map<String,dynamic>`: converte o payload em `Model` (`.fromJson`) o quanto antes.
- Componentes reutilizáveis (com estado ou não) ficam em `lib/widgets/` e **não** contêm lógica de negócio — recebem callbacks/valores prontos.

---

## 4. Padrões de Código (templates prontos)

### 4.1 Model — DTO imutável

**Arquivo:** `lib/models/feature_resumo.dart`

```dart
/// Objeto do domínio. Imutável, comparável por valor.
/// `fromJson` sanitiza tipos (int|String → int). Nunca depende do backend
/// devolver o tipo exato — o backend pode mandar "5" ou 5 e o app aceita.
class FeatureResumo {
  final int id;
  final String nome;
  final String? descricao;

  const FeatureResumo({
    required this.id,
    required this.nome,
    this.descricao,
  });

  factory FeatureResumo.fromJson(Map<String, dynamic> j) {
    int parseInt(dynamic v) => v is int ? v : int.tryParse(v.toString()) ?? 0;
    String? nn(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return FeatureResumo(
      id: parseInt(j['id']),
      nome: (j['nome'] ?? '').toString(),
      descricao: nn(j['descricao']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nome': nome,
    if (descricao != null) 'descricao': descricao,
  };
}
```

**Regras do Model:**
- `final` em todos os campos, construtor `const` sempre que possível.
- `fromJson` **sempre** tolera tipos — número que veio string, string vazia como `null`, chave ausente.
- Sem lógica de negócio (isso é DOMAIN service).
- Sem estado mutável (nem `late`, nem `_var setável`).

### 4.2 Result tipado — padrão para services de API

Para operações que precisam distinguir sucesso × falha × falha específica (ex.: `AuthService.login` distingue credencial inválida × captcha errado), retorne um **Result** dedicado.

**Arquivo:** `lib/services/auth_service.dart` (real, resumido)

```dart
class LoginResult {
  final bool ok;
  final String? message;
  final bool captchaError;
  final bool captchaReloadRequired;

  const LoginResult._({required this.ok, this.message,
    this.captchaError = false, this.captchaReloadRequired = false});

  factory LoginResult.success() => const LoginResult._(ok: true);
  factory LoginResult.failure(String? msg) => LoginResult._(ok: false, message: msg);
  factory LoginResult.captchaFailure(String? msg, {required bool reload}) =>
      LoginResult._(ok: false, message: msg,
        captchaError: true, captchaReloadRequired: reload);
}
```

Para operações binárias simples (só sucesso/falha), retornar `Future<bool>` ou `Future<int>` (id inserido) direto é aceitável.

### 4.3 Service — API (fachada HTTP tipada)

**Arquivo:** `lib/services/feature_service.dart`

```dart
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../models/feature_resumo.dart';
import '../utils/logger.dart';

/// Fachada dos endpoints /transporte/api/feature/*.
/// Retorna Model tipado; nunca vaza Map<String,dynamic> pra UI.
class FeatureService {
  static const _log = Logger('FEATURE-SVC');

  static Future<int> _userId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('usuario_id') ?? 0;
  }

  static Future<List<FeatureResumo>> listar() async {
    final usuarioId = await _userId();
    final res = await ApiClient.post('transporte/api/feature/list', {
      'usuario_id': usuarioId, // fallback enquanto o backend não resolve 100% via Bearer
    });
    if (res['success'] != true) {
      _log.warn('listar FALHOU: ${res['message']}');
      return const [];
    }
    final list = (res['data'] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => FeatureResumo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<Map<String, dynamic>> criar({
    required String nome,
    String? descricao,
  }) async {
    final usuarioId = await _userId();
    final res = await ApiClient.post('transporte/api/feature/create', {
      'usuario_id': usuarioId,
      'nome': nome.trim(),
      if (descricao != null && descricao.trim().isNotEmpty)
        'descricao': descricao.trim(),
    });
    _log.info('criar http=${res["http_status"]} ok=${res["success"]}');
    return res;
  }
}
```

**Regras do Service de API:**
- Métodos são `static` (sem estado). O único IO é o `ApiClient` + `SharedPreferences` pro token/id.
- Endpoint no primeiro argumento do `ApiClient.post` sempre relativo (`transporte/api/...`), **nunca** com host.
- Nunca trafica IDs internos para a UI se puder trafegar um `Model`. Para métodos que criam algo, retornar o `Map` bruto é aceitável (a UI leia só campos necessários: `success`, `message`, `bdt_id`, `protocolo`).
- Usar o `Logger` (§4.9) para diagnóstico — não `print` solto.

### 4.4 Service — STORAGE (persistência local)

**Arquivo:** `lib/services/credentials_storage.dart` (real; resumo)

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contrato: métodos static de leitura/escrita. Nunca chama HTTP.
/// Regra do secure storage: só o que é sensível (senha, token de app).
class CredentialsStorage {
  static const _kSenhaSecure = 'login_senha_salva_secure';
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<String?> getSenha() async {
    return _secure.read(key: _kSenhaSecure);
  }

  static Future<void> setSenha(String senha) async {
    await _secure.write(key: _kSenhaSecure, value: senha);
  }

  static Future<void> clear() async {
    await _secure.delete(key: _kSenhaSecure);
    final p = await SharedPreferences.getInstance();
    await p.remove('login_cpf_salvo');
  }
}
```

**Regras do Storage:**
- Sensível (senha, api keys) → `flutter_secure_storage`.
- Não sensível (CPF, flags, ids) → `SharedPreferences`.
- Chaves em `static const` no topo, sempre prefixadas (`login_...`, `bg_gps_...`).
- Sem chamada HTTP. Se precisar sincronizar remoto, é o Page que orquestra: Storage → Service API.

### 4.5 Service — DOMAIN (regra pura)

Regra pura = sem IO. Fácil de testar unitariamente.

**Arquivo:** `lib/services/location_outlier_filter.dart` (real; resumo)

```dart
import 'package:geolocator/geolocator.dart';

class LocationOutlierFilter {
  final double maxAccuracyMeters;
  final double maxSpeedKmh;
  Position? _lastAccepted;

  LocationOutlierFilter({
    this.maxAccuracyMeters = 50,
    this.maxSpeedKmh = 200,
  });

  /// null = aceita; string = razão do descarte
  String? reject(Position pos) {
    if (pos.accuracy > maxAccuracyMeters) return 'accuracy';
    if (pos.speed * 3.6 > maxSpeedKmh)    return 'speed';
    // ... teleporte, etc.
    _lastAccepted = pos;
    return null;
  }

  void reset() => _lastAccepted = null;
}
```

**Regras do Domain:**
- Nenhuma dependência de `dart:io`, plugin de OS, HTTP, storage.
- Estado interno **explícito** (documentar o motivo — aqui é a âncora do teleporte).
- Nome do arquivo descreve o quê, não o como (`*_filter.dart`, `*_calculator.dart`).

### 4.6 Service — PLATFORM (plugin nativo / OS)

**Arquivo:** `lib/services/background_location_service.dart` (referência)

```dart
class BackgroundLocationService {
  static Future<void> init() async { /* configura foreground service */ }

  /// Idempotente: se já está rodando, apenas atualiza o contexto.
  static Future<bool> start({
    required int bdtId,
    int? agendaId,
    required int trechoId,
    Duration interval = const Duration(seconds: 5),
  }) async { /* ... */ }

  static Future<void> stop() async { /* ... */ }
  static Future<bool> isRunning() async { /* ... */ }
}
```

**Regras do Platform:**
- Métodos `static`, idempotentes (`start` chamado 2× não quebra).
- Toda comunicação com o isolate do service via `SharedPreferences` (para estado persistente entre isolates) e `service.invoke(event)` (para comandos).
- Registrar entrypoints como `@pragma('vm:entry-point')` (foreground service, background tasks).
- Log sempre com o `Logger` (§4.9). Isolates de service **exigem** log persistente (`developer.log` + `print`).

### 4.7 Page (StatefulWidget)

**Arquivo:** `lib/pages/feature_page.dart`

```dart
import 'package:flutter/material.dart';
import '../services/feature_service.dart';
import '../models/feature_resumo.dart';
import '../widgets/app_scaffold.dart';

class FeaturePage extends StatefulWidget {
  const FeaturePage({super.key});
  @override
  State<FeaturePage> createState() => _FeaturePageState();
}

class _FeaturePageState extends State<FeaturePage> {
  late Future<List<FeatureResumo>> _future;

  @override
  void initState() {
    super.initState();
    _future = FeatureService.listar();
  }

  Future<void> _reload() async {
    setState(() { _future = FeatureService.listar(); });
    await _future; // aguarda pra o navbar sincronizar o spinner
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Features',
      subtitle: 'Módulo X',
      onRefresh: _reload,
      body: FutureBuilder<List<FeatureResumo>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) return const Center(child: Text('Nada por aqui.'));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (_, i) => ListTile(
              title: Text(items[i].nome),
              subtitle: Text(items[i].descricao ?? ''),
            ),
          );
        },
      ),
    );
  }
}
```

**Regras da Page:**
- Sempre `StatefulWidget` — mesmo que hoje não haja estado, a próxima iteração provavelmente vai precisar.
- Estado carregado no `initState` OU no primeiro `didChangeDependencies` (proteger com `_bootstrapped` bool).
- Nunca chamar HTTP direto — sempre por Service.
- Chamadas de UI que dependem do payload (`_uiDate`, `_labelTrechoAtivo`) ficam como métodos privados (`_*`) no state.
- `setState` **nunca** dentro de `build`. Se precisar reagir a Future, coloque em `addPostFrameCallback`.
- Sempre validar `if (!mounted) return;` após `await` antes de tocar em `context`.

### 4.8 Widget reutilizável

**Arquivo:** `lib/widgets/feature_chip.dart`

```dart
import 'package:flutter/material.dart';

/// Chip de status para uso em cards da feature X.
/// Zero lógica de negócio: recebe cor+texto prontos.
class FeatureChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const FeatureChip({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar: Icon(icon, size: 14, color: color),
      label: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
```

**Regras do Widget:**
- `StatelessWidget` sempre que possível.
- Recebe dados prontos (sem chamar Service).
- Estilos por parâmetro, não hardcode — permite variações.
- Se tiver estado (ex.: `CaptchaField`), expor `GlobalKey<State>` e uma API pública mínima.

### 4.9 Logger

**Arquivo:** `lib/utils/logger.dart`

```dart
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// Log unificado. Escreve com `dart:developer` (aparece no DevTools/logcat
/// com o nome como tag) E `print` (aparece bruto no `flutter run`/logcat).
///
/// - Use `const Logger('TAG')` no topo da classe.
/// - `info` sempre; `warn` para condições recuperáveis; `error` para
///   exceções. Todos escrevem em release também (o app não tem trace do
///   celular; sem log persistente não dá pra diagnosticar).
class Logger {
  final String tag;
  const Logger(this.tag);

  void info(String msg)  => _emit(msg);
  void warn(String msg)  => _emit('WARN: $msg');
  void error(String msg, [Object? e, StackTrace? st]) {
    _emit('ERROR: $msg${e == null ? "" : " | $e"}');
    if (st != null && kDebugMode) _emit('  st: ${st.toString().split("\n").take(3).join(" | ")}');
  }

  void _emit(String msg) {
    developer.log(msg, name: tag);
    // ignore: avoid_print
    print('[$tag] $msg');
  }
}
```

**Uso:**
```dart
class BdtService {
  static const _log = Logger('BDT-SVC');
  static Future<bool> foo() async {
    _log.info('foo start');
    // ...
  }
}
```

**Tags convencionadas (grep-friendly):**
- Services API: `AUTH-SVC`, `BDT-SVC`, `CAPTCHA-SVC`
- Services STORAGE: `CREDS-STORE`, `GPS-QUEUE`
- Services DOMAIN: `GPS-LIVE`, `OUTLIER-FILTER`
- Services PLATFORM: `BG-GPS`, `LOC-PERM`

### 4.10 Rotas

Rotas são nomeadas, registradas em `lib/main.dart`. Argumento passado via `Navigator.pushNamed(context, '/rota', arguments: X)` e lido no `build` da Page: `ModalRoute.of(context)!.settings.arguments as int`.

```dart
// main.dart
routes: {
  '/login':       (_) => const LoginPage(),
  '/home':        (_) => const HomePage(),
  '/bdt':         (_) => const BdtPage(),        // arguments: int bdtId
  '/bdt_form':    (_) => const BdtFormPage(),    // arguments: int bdtId
  '/pre_bdt/novo':(_) => const PreBdtFormPage(),
},
```

**Regras:**
- Nome curto, com prefixo lógico (`/pre_bdt/novo` — separador `/` OK).
- Argumento: `int` (id) na maioria dos casos. Para composições, criar uma classe `FooArgs` imutável (evita `Map<String, dynamic>`).

### 4.11 Formatação de datas/horas

`lib/utils/date_fmt.dart` centraliza os helpers. Nada de duplicar `_two(int)` / `_fmtDt(v)` em cada page.

```dart
import 'package:intl/intl.dart';

class DateFmt {
  static String two(int v) => v.toString().padLeft(2, '0');

  /// "03/01/2026"
  static String dataBr(DateTime d) =>
      '${two(d.day)}/${two(d.month)}/${d.year}';

  /// "03/01 07:00" (compacto para listas)
  static String dtCompact(dynamic raw) { /* ... */ }

  /// "yyyy-MM-dd" (formato da API)
  static String apiDate(DateTime d) =>
      '${d.year}-${two(d.month)}-${two(d.day)}';

  /// "HH:MM"
  static String hora(dynamic raw) { /* ... */ }
}
```

### 4.12 Tema

`lib/theme/app_theme.dart` centraliza cores/tipografia. O `main.dart` só faz `theme: AppTheme.light()`.

```dart
class AppTheme {
  static const Color primary = Color(0xFF0D47A1);   // azul UERJ

  static ThemeData light() => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: primary,
    fontFamily: null, // sistema
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}
```

---

## 5. Convenções de Nomenclatura

| Camada | Caminho | Sufixo |
|---|---|---|
| Page | `lib/pages/foo_page.dart` | `*Page` |
| Widget | `lib/widgets/foo_bar.dart` | `*Bar`, `*Field`, `*Card`, `*Chip`, etc. |
| Service (API) | `lib/services/foo_service.dart` | `*Service` |
| Service (STORAGE) | `lib/services/foo_storage.dart` ou `*_db.dart` | `*Storage` ou `*Db` |
| Service (DOMAIN) | `lib/services/foo_filter.dart`, `*_calculator.dart` | descritivo |
| Service (PLATFORM) | `lib/services/foo_service.dart` | `*Service` (documentar categoria no header) |
| Model | `lib/models/foo.dart` ou `foo_resumo.dart` | sem sufixo, ou `*Resumo` para versão enxuta |
| Formatter | `lib/formatters/foo_formatter.dart` | `*Formatter` |
| Utils | `lib/utils/foo.dart` | descritivo |
| Theme | `lib/theme/app_*.dart` | prefixo `app_` |

**Nomes de métodos por camada:**
- **Service API:** `listar()`, `detalhes(int id)`, `criar(...)`, `atualizar(...)`, `excluir(int id)`.
- **Storage:** `getFoo()`, `setFoo(...)`, `clear()`.
- **Domain:** verbo que descreve a operação (`reject`, `calcular`, `validar`).
- **Platform:** `init()`, `start(...)`, `stop()`, `isRunning()`.

---

## 6. Permissões e OS

### 6.1 Android — `android/app/src/main/AndroidManifest.xml`

Permissões atualmente exigidas:

| Permissão | Motivo |
|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | HTTP + `connectivity_plus` |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | GPS foreground |
| `ACCESS_BACKGROUND_LOCATION` | GPS com app fora da tela |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION` | Foreground service com tipo location (Android 14+) |
| `POST_NOTIFICATIONS` | Notificação persistente (Android 13+) |
| `WAKE_LOCK` | CPU acordada durante tracking |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Sobrevivência ao Doze (M2) |
| `RECEIVE_BOOT_COMPLETED` | (Opcional) reiniciar service após boot |

**Ao criar feature nova que exige permissão nativa:**
1. Adicionar `<uses-permission>` no manifest.
2. Criar helper em `LocationService.ensureXxxPermission()` (ou análogo) que **pede** a permissão via `permission_handler`.
3. Documentar a UX: quando pedir? geralmente no primeiro uso da feature, com `addPostFrameCallback` para não colidir com bottom sheets/dialogs.

### 6.2 iOS — `ios/Runner/Info.plist`

Fora do escopo atual (app é Android-first). Se um dia compilar iOS, adicionar `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSLocationWhenInUseUsageDescription`, `UIBackgroundModes` com `location` e `fetch`.

---

## 7. Checklist para Criar uma Nova Feature

1. [ ] **Model** — `lib/models/feature_resumo.dart` (imutável, `.fromJson` tolerante)
2. [ ] **Service (categoria correta)** — em `lib/services/`. Se for API, retornar `Model` ou `Result`.
3. [ ] **Endpoint no backend** — se ainda não existe, criar na branch `feature/027-mobile-support` do `e-prefeitura` (registrar no stub `SPRINTS_MOBILE.md` de lá).
4. [ ] **Page** — em `lib/pages/`. StatefulWidget, `initState`/`_bootstrap`, tratar `!mounted`.
5. [ ] **Widgets reutilizáveis** — em `lib/widgets/` (sem lógica de negócio).
6. [ ] **Rota** — nomeada em `lib/main.dart` (nome curto, prefixado).
7. [ ] **Formatters específicos** — em `lib/formatters/` se for `TextInputFormatter`; em `lib/utils/date_fmt.dart` se for data/hora.
8. [ ] **Logger** — `static const _log = Logger('TAG-CATEGORIA');` no topo da classe. Nunca `print` solto.
9. [ ] **Permissões nativas** — atualizar `AndroidManifest.xml` + helper em `LocationService` (ou análogo).
10. [ ] **Estado do FAB / Refresh** — expor via `AppScaffold(onRefresh: _reload)`. `_reload` deve retornar `Future<void>` para o spinner sincronizar.
11. [ ] **Sem IDs internos na UI** — mostrar protocolo (`BDT ano/numero`), origem→destino, horário. IDs (`bdt_id`, `trecho_id`, `agenda_id`) ficam só nas navegações/args.
12. [ ] **Atualizar `docs/proposta/SPRINTS_MOBILE.md`** — se a mudança fecha item de sprint, marcar `✅` no bullet correspondente (regra de processo — obrigatória).
13. [ ] **Rodar `flutter analyze`** — zero erros. Warnings pré-existentes toleráveis.
14. [ ] **`flutter build apk --debug`** — sucesso obrigatório antes de commitar.
15. [ ] **Testar no device real** — plugins de OS (background service, permission, storage) só se comportam de verdade em Android real. Não confie só no emulador.

---

## 8. Testes

### Estado atual
- Só o smoke test default (`test/widget_test.dart`) — apenas confirma que o app monta sem crash.
- Cobertura de teste é **baixa** de propósito nesta fase (MVP em iteração rápida).

### Onde vale investir teste unitário
Priorize regras **DOMAIN** puras — elas testam sem plugin, sem HTTP, sem device.

- `LocationOutlierFilter` — casos: accuracy alta, velocidade impossível, teleporte, reset.
- Parsers de `Model.fromJson` — testar tipos toleráveis (int vs string, chave ausente).
- `DateFmt` — bordas (hora com segundos, hora sem data, etc.).

Services **API**/**STORAGE**/**PLATFORM** exigem mock que hoje não é rentável; deixar para quando estabilizar.

---

## 9. Build e Ambientes

### `--dart-define=APP_ENV=...`

Configuração de backend via constante lida em build time (`String.fromEnvironment`):

| APP_ENV | baseUrl | Uso |
|---|---|---|
| `production` (default) | `https://www.e-prefeitura.uerj.br` | Release |
| `localhost` | `http://localhost:8080/e-prefeitura` | Celular USB + `adb reverse tcp:8080 tcp:80` |
| `emulator` | `http://10.0.2.2/e-prefeitura` | Emulador Android |
| `wsl` | `http://192.168.1.138/e-prefeitura` | Celular na LAN do PC |
| `localhostIp` | `http://152.92.228.217/e-prefeitura` | IP específico da rede UERJ |

Em **release build** (`flutter build apk --release`) o `_env` **sempre** cai em `production` (garantia extra em `ApiClient.baseUrl`).

Perfis prontos em `.vscode/launch.json`. Para rodar via CLI:
```
flutter run --dart-define=APP_ENV=localhost
```

### Comandos essenciais
```powershell
flutter clean                          # limpa build cache
flutter pub get                        # baixa deps
flutter analyze --no-pub               # lint (zero erros obrigatório antes de commitar)
flutter build apk --debug              # build de teste
flutter build apk --release            # build de produção
flutter run -d <device-id>             # roda em device específico
adb devices                            # lista devices disponíveis
adb reverse tcp:8080 tcp:80            # tunneling USB para testar contra Docker local
```

### SSL — CA da RNP

O app confia em `https://www.e-prefeitura.uerj.br` via CA custom (RNP ICPEdu). O certificado está em `assets/certs/rnp_icpedu_chain.pem` e é injetado no `SecurityContext.defaultContext` pelo `SslBootstrap.install()` no `main()`.

**Importante:** cada isolate Dart tem seu próprio `SecurityContext.defaultContext`. Se você criar isolate novo (background service, etc.), **chame `SslBootstrap.install()` também lá**. Já feito em `BackgroundLocationService._onServiceStart`.

---

## 10. Referências dentro do projeto

Exemplos reais para copiar e adaptar:

| Padrão | Arquivo |
|---|---|
| Model tipado (imutável, `fromJson` tolerante) | `lib/models/bdt_resumo.dart` |
| Service API (fachada HTTP) | `lib/services/bdt_service.dart`, `lib/services/auth_service.dart` |
| Service com `Result` tipado | `lib/services/auth_service.dart` (`LoginResult`) |
| Service STORAGE (secure + prefs) | `lib/services/credentials_storage.dart` |
| Service STORAGE (SQLite) | `lib/services/location_queue_db.dart` |
| Service DOMAIN (regra pura) | `lib/services/location_outlier_filter.dart` |
| Service PLATFORM (foreground service Android) | `lib/services/background_location_service.dart` |
| Page com Future + refresh | `lib/pages/home_page.dart` |
| Page com formulário dinâmico | `lib/pages/pre_bdt_form_page.dart` |
| Widget composto reutilizável | `lib/widgets/captcha_field.dart` (com `GlobalKey<State>`) |
| Chip com estado externo | `lib/pages/bdt_page.dart` (`_chipStatusConexao`, `_chipStatusFila`) |
| Cliente HTTP + baseUrl por ambiente | `lib/api/api_client.dart` |
| Bootstrap SSL (CA custom) | `lib/api/ssl_bootstrap.dart` |
| Formatter TextInputFormatter | `lib/formatters/cpf_input_formatter.dart` |
| Logger unificado (`Logger('TAG')`) | `lib/utils/logger.dart` |
| Helper de datas | `lib/utils/date_fmt.dart` |
| Tema Material 3 | `lib/theme/app_theme.dart` |
| Manifest Android com foreground service | `android/app/src/main/AndroidManifest.xml` |
| Rotas nomeadas | `lib/main.dart` |
| Perfis de dev/prod para VSCode | `.vscode/launch.json` |
