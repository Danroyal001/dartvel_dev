
# Bootstrapping a dartvel Project (v0.1)

> This guide assumes a *standard Flutter* project.

## 1) Add dependencies (local path or pub)
```yaml
# pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  go_router: ^14.2.0
  dartvel_core:        # Shelf helpers for your backend handlers (in-app)
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

## 4) Generate router & config
```bash
dart run dartvel_cli:dartvel routes
```

This emits:
- `.dart_tool/dartvel_client/dartvel_config.g.dart`
- `.dart_tool/dartvel_client/dartvel_runtime.dart`
- `.dart_tool/dartvel_client/router.g.dart`
- `.dart_tool/dartvel_backend.g.dart`

## 5) Wire up your app
`lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import '.dart_tool/dartvel_client/router.g.dart';
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
