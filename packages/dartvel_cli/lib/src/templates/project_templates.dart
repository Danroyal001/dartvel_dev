class ProjectTemplates {
  static String pubspecTemplate({
    required String name,
    required String org,
    bool web = true,
    bool mobile = true,
    bool desktop = false,
    String? localPackagesDir,
  }) =>
      '''
name: $name
description: A new Dartvel project
publish_to: "none"
version: 0.0.1

environment:
  sdk: ">=3.4.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  go_router: ^14.2.0
  dio: ^5.5.0
  dartvel_core: ${localPackagesDir == null ? '^0.1.1' : '\n    path: $localPackagesDir/dartvel_core'}
  dartvel_shelf: ${localPackagesDir == null ? '^0.3.0' : '\n    path: $localPackagesDir/dartvel_shelf'}
  dartvel_flutter: ${localPackagesDir == null ? '^0.1.1' : '\n    path: $localPackagesDir/dartvel_flutter'}
  ${web ? 'flutter_web_plugins:\n    sdk: flutter' : ''}

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.5.4
  lints: ^4.0.0
  dartvel_cli: ${localPackagesDir == null ? '^0.1.1' : '\n    path: $localPackagesDir/dartvel_cli'}


flutter:
  uses-material-design: true
  assets:
    - assets/

dartvel:
  backendHost: 0.0.0.0
  backendPort: 3000
  devBackendHost: http://localhost:3000
  prodBackendHost: https://api.${name.replaceAll('_', '-')}.com
  pagesDir: lib/pages
  backendDir: lib/backend
  apiBasePath: /api
  envFiles: [.env, .env.local]
  plugins: []
  webPrerender: false
  ota: false

  transitions:
    default: fade
    durationMs: 200
    curve: easeInOut

  seo:
    siteName: ${name.replaceAll('_', ' ')}
    defaultTitle: Welcome
    defaultDescription: A Dartvel application
''';

  static const String envTemplate = '''# Environment variables
# Add your secrets here - this file is gitignored

# PUBLIC_ variables are exposed to client
PUBLIC_GREETING=Hello from Dartvel!

# Backend/server only variables
# DATABASE_URL=postgresql://localhost/mydb
# API_KEY=your-secret-key
''';

  static const String envExampleTemplate = '''# Example environment variables
# Copy this to .env and fill in your values

PUBLIC_GREETING=Hello from Dartvel!
# DATABASE_URL=postgresql://localhost/mydb
# API_KEY=your-secret-key
''';

  static const String indexPageTemplate =
      '''import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel',
  showAppBar: true,
  centerTitle: true,
)
class IndexPage extends DartvelPage {
  const IndexPage({super.key});

  @override
  Future<Object?> loadData(
      Map<String, String> params, Map<String, String> query) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return <String, String>{'timestamp': DateTime.now().toIso8601String()};
  }

  @override
  Widget build(BuildContext context) {
    final data = DvDataScope.of(context).data as Map<String, String>?;
    
    return DVBox.list([
      const DVText('Welcome to Dartvel'),
      const Icon(Icons.rocket_launch, size: 64, color: Colors.blue),
      const DVText('Your Dartvel app is ready!').modifier(
        DVModifier().color(Color(0xFF111827)).padding(8),
      ),
      DVText('Loaded at: \${data?['timestamp'] ?? 'N/A'}'),
      DVBox.wrap([
        const DVText('Docs').modifier(DVModifier().padding(12).rounded(8)),
        const DVText('GitHub').modifier(DVModifier().padding(12).rounded(8)),
      ], spacing: 12),
    ]).modifier(
      const DVModifier().padding(24).align(Alignment.center),
    );
  }
}
''';

  static String loadingTemplate(String className) =>
      '''import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';

class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) {
    return const DVBox(CircularProgressIndicator());
  }
}
''';

  static String errorTemplate(String className) =>
      '''import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';

class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) {
    return DVBox.list([
      const Icon(Icons.error_outline, size: 48, color: Colors.red),
      const DVText('Something went wrong'),
      DVText('Go Back').modifier(
        const DVModifier()
            .padding(12)
            .rounded(8)
            .backgroundColor(Colors.black)
            .color(Colors.white)
            .onPressed(() => Navigator.of(context).pop()),
      ),
    ]).modifier(
      const DVModifier().align(Alignment.center),
    );
  }
}
''';

  static const String healthFunctionTemplate = '''// GET /api/health
Map<String, dynamic> handler() {
  return {
    'status': 'ok',
    'timestamp': DateTime.now().toIso8601String(),
  };
}
''';

  static const String contactFormTemplate =
      '''// POST /api/contact (filename without method = POST by default)
import 'dart:io';
import 'dart:convert';

Future<Map<String, dynamic>> handler(
    {required String name, required String email, required String message}) async {
  // Validate inputs
  if (name.isEmpty || email.isEmpty || message.isEmpty) {
    throw Exception('All fields are required');
  }

  if (!email.contains('@')) {
    throw Exception('Invalid email address');
  }

  final submission = {
    'name': name,
    'email': email,
    'message': message,
    'receivedAt': DateTime.now().toIso8601String(),
  };
  final inbox = File('storage/contact_submissions.jsonl');
  inbox.parent.createSync(recursive: true);
  inbox.writeAsStringSync('\${jsonEncode(submission)}\\n',
      mode: FileMode.append, flush: true);

  return {
    'success': true,
    'message': 'Thank you for contacting us!',
  };
}
''';

  static const String mainTemplate = '''import 'package:flutter/material.dart';
import 'dartvel_client/dartvel_client.dart';

void main() {
  runApp(createDartvelApp());
}

Widget createDartvelApp() {
  return MaterialApp.router(
    title: 'Dartvel App',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      useMaterial3: true,
    ),
    routerConfig: createDartvelRouter(),
  );
}
''';

  static const String gitignoreTemplate = '''# Dart
.dart_tool/
.packages
build/
.flutter-plugins
.flutter-plugins-dependencies

# Environment
.env
.env.local

# Generated
lib/dartvel_client/
.dartvel/

# IDE
.idea/
*.iml
.vscode/

# OS
.DS_Store
Thumbs.db
''';

  static const String analysisOptionsTemplate =
      '''include: package:lints/recommended.yaml

analyzer:
  exclude:
    - "lib/dartvel_client/**"
    - ".dart_tool/**"

linter:
  rules:
    - prefer_const_constructors
    - prefer_const_literals_to_create_immutables
    - avoid_print
''';

  static String readmeTemplate(String name) => '''# $name

A new Dartvel project.

## Getting Started

### Prerequisites

- Flutter SDK \u003e= 3.4.0
- Dart SDK \u003e= 3.4.0

### Installation

```bash
flutter pub get
```

### Development

```bash
dartvel dev
```

This will:
- Start the backend server on http://localhost:3000
- Run your Flutter app with hot reload

### Project Structure

```
lib/
├── pages/              # Page components (file-based routing)
├── models/             # @DVModel classes
├── backend/
│   └── functions/      # API endpoints
├── components/         # Shared UI widgets
├── styles/             # Shared DVModifier styles
├── services/           # Business logic and integrations
└── main.dart

.env                    # Environment variables (gitignored)
pubspec.yaml           # Dependencies and Dartvel config
```

### Adding Pages

Create a new file in `lib/pages/`:

```dart
// lib/pages/about.dart
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';

@DVPage(
  title: 'About',
  showAppBar: true,
)
Widget aboutPage(BuildContext context) {
  return DVBox.list([
    const DVText('About'),
    const DVText('About page'),
  ]).modifier(const DVModifier().padding(16));
}
```

Route is automatically available at `/about`.

### Adding API Endpoints

Create a new file in `lib/backend/functions/`:

```dart
// lib/backend/functions/hello.get.dart
Map<String, dynamic> handler() {
  return {'message': 'Hello World!'};
}
```

Endpoint is automatically available at `GET /api/hello`.

### Building for Production

```bash
dartvel build
```

## Learn More

- [Dartvel Documentation](https://dartvel.dev)
- [Flutter Documentation](https://flutter.dev)

## License

MIT
''';
}
