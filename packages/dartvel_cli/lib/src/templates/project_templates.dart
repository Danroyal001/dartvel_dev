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
  dartvel_core: ${localPackagesDir == null ? '^0.1.0' : '\n    path: ${localPackagesDir}/dartvel_core'}
  dartvel_shelf: ${localPackagesDir == null ? '^0.1.0' : '\n    path: ${localPackagesDir}/dartvel_shelf'}
  dartvel_flutter: ${localPackagesDir == null ? '^0.1.0' : '\n    path: ${localPackagesDir}/dartvel_flutter'}
  ${web ? 'flutter_web_plugins:\n    sdk: flutter' : ''}

dev_dependencies:
  flutter_test:
    sdk: flutter
  lints: ^4.0.0
  dartvel_cli: ${localPackagesDir == null ? '^0.1.0' : '\n    path: ${localPackagesDir}/dartvel_cli'}


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
      '''import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';

@DVPage()
class IndexPage extends DartvelPage {
  const IndexPage({super.key});

  @override
  Future<Object?> loadData(
      Map<String, String> params, Map<String, String> query) async {
    // Fetch data here - runs on page load
    await Future.delayed(const Duration(milliseconds: 500));
    return {'timestamp': DateTime.now().toIso8601String()};
  }

  @override
  Widget build(BuildContext context) {
    final data = DvDataScope.of(context).data as Map?;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to Dartvel'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.rocket_launch, size: 64, color: Colors.blue),
              const SizedBox(height: 24),
              Text(
                'Your Dartvel app is ready!',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Loaded at: \${data?['timestamp'] ?? 'N/A'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.book),
                    label: const Text('Docs'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.code),
                    label: const Text('GitHub'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
''';

  static String loadingTemplate(String className) =>
      '''import 'package:flutter/material.dart';

class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loading...')),
      body: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
''';

  static String errorTemplate(String className) =>
      '''import 'package:flutter/material.dart';

class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Error')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Something went wrong'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
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

  // TODO: Send email, save to database, etc.
  print('Contact form submission:');
  print('  Name: \$name');
  print('  Email: \$email');
  print('  Message: \$message');

  return {
    'success': true,
    'message': 'Thank you for contacting us!',
  };
}
''';

  static const String mainTemplate = '''import 'package:flutter/material.dart';
import 'dartvel_client/router.g.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Dartvel App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routerConfig: createDartvelRouter(),
    );
  }
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

@DVPage()
class AboutPage extends DartvelPage {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: const Center(child: Text('About page')),
    );
  }
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
