
# Bootstrapping a dartvel Project (v0.1)

> This guide assumes a *standard Flutter* project.

## 1) Add dependencies (local path or pub)
```yaml
# pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  go_router: ^14.2.0
  dartvel_core:        # Core helpers and types for backend handlers (dartvel_shelf-based)
    path: ../dartvel/packages/dartvel_core
  dartvel_flutter:     # Page API, SEO & transitions
    path: ../dartvel/packages/dartvel_flutter

dev_dependencies:
  dartvel_cli:         # Codegen CLI
    path: ../dartvel/packages/dartvel_cli
```

## 2) Configure dartvel
Add a `dartvel:` section to your `pubspec.yaml` (see **CONFIG** for all keys):
```yaml
dartvel:
  backendHost: 0.0.0.0
  backendPort: 3000
  devBackendHost: http://localhost:3000
  prodBackendHost: https://api.example.com

  pagesDir: lib/pages
  backendDir: lib/backend
  apiBasePath: /api

  webSeoDefaults:
    siteName: MyApp
    defaultTitle: MyApp
    defaultDescription: A beautiful app built with dartvel.
    defaultImage: assets/og_default.png
    twitterHandle: "@myapp"

  transitions:
    default: fade
    durationMs: 220
    curve: easeInOut

  # Optional: env files. PUBLIC_* keys are exposed to Flutter via env.g.dart
  envFiles: [ .env, .env.local ]
```

## 3) Create your first page
`lib/pages/index.page.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

class IndexPage extends DartvelPage {
  const IndexPage({super.key});

  @override
  SeoProps buildWebSeo(Map<String, String> params, Map<String, String> query) =>
      const SeoProps(title: 'Home • MyApp', description: 'Welcome to MyApp!');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: FilledButton(
          onPressed: () => Navigator.of(context).pushNamed('/blog/42'),
          child: const Text('Go to /blog/42'),
        ),
      ),
    );
  }
}
```

## 4) Generate router & config (+backend routes)
```bash
dart run dartvel_cli:dartvel routes
```

This emits:
- `lib/dartvel_client/dartvel_config.g.dart`
- `lib/dartvel_client/dartvel_runtime.dart`
- `lib/dartvel_client/router.g.dart`
- `lib/dartvel_client/functions.g.dart`
- `lib/dartvel_client/env.g.dart`
- `.dart_tool/dartvel_backend.g.dart`
 - `.dart_tool/dartvel_backend_routes.g.dart`

Optional sanity check:
```bash
dart run dartvel_cli:doctor
```
Shows pages found, backend functions count, and config tips.

404 behavior (optional):
- Set `notFoundRedirect: /` under `dartvel:` to redirect unknown routes to a path of your choice.

Loading/Error states (optional):
- Add sibling files next to a page to customize data loader UI:
  - `lib/pages/index.loading.dart` → `IndexPageLoading`
  - `lib/pages/index.error.dart` → `IndexPageError`
- If you don’t add them, defaults are provided: `DvDefaultLoading` and `DvDefaultError`.

## 5) Wire up your app
`lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:your_app/dartvel_client/router.g.dart';
void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: createDartvelRouter(),
      theme: ThemeData(useMaterial3: true),
    );
  }
}
```

## 6) Run (web recommended for SEO features)
```bash
flutter run -d chrome
```

> Tip: For Android emulator, set `devBackendHost: http://10.0.2.2:3000`.

Optional: start a custom server by importing the generated backend app:
```dart
import '.dart_tool/dartvel_backend_routes.g.dart' as gen;
Future<void> main() async {
  final app = gen.buildBackend();
  await app.listen(address: '0.0.0.0', port: 3000);
}
```

## Backend function quickstart
Create a handler under `lib/backend/functions/**/*.method.dart` (method in: get, post, put, patch, delete, head, options):
```dart
// lib/backend/functions/hello.get.dart
import 'package:dartvel_core/dartvel.dart';

Future<ResponseType> handler(RequestType req) async {
  return Res.json({'ok': true, 'hello': 'world'});
}
```
Run `dart run dartvel_cli:routes` again to regenerate backend routes.

## Public env values in Flutter
1) Add an env file like `.env`:
```
PUBLIC_GREETING=Hello
SECRET_TOKEN=do_not_export
```
2) Configure `envFiles` under `dartvel:` (or rely on defaults).
3) Run `dart run dartvel_cli:dartvel routes`.
4) Use from Flutter:
```dart
import 'package:your_app/dartvel_client/env.g.dart';
final greeting = DartvelEnv.get('PUBLIC_GREETING');
```

Only `PUBLIC_*` keys are exported to `env.g.dart`.

## Production build
Set `prodBackendHost` in `pubspec.yaml -> dartvel` and build:
```bash
flutter build web
```
You can override the backend URL at build time:
```bash
flutter build web \
  --dart-define=DARTVEL_BACKEND_URL=https://staging.example.com
```

Preview a built web folder locally (SPA fallback included):
```bash
dart run dartvel_cli:dartvel preview --dir build/web --port 5000
```
