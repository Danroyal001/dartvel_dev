/// The version a scaffolded project asks pub.dev for.
///
/// One number for the whole family, because they are released together. It was
/// three hand-written constraints that nothing kept in step, and when the
/// packages reached 0.2.1 the template still asked for ^0.1.1 -- a version
/// never published, so every `dartvel create` outside this repository produced
/// a project that could not resolve.
///
/// A test asserts this admits the version each package declares, so the two
/// cannot drift again without the suite saying so.
const String dartvelPackageVersion = '0.2.1';

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
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  go_router: ^14.2.0
  dio: ^5.5.0
  dartvel_core: ${localPackagesDir == null ? '^$dartvelPackageVersion' : '\n    path: $localPackagesDir/dartvel_core'}
  dartvel_shelf: ${localPackagesDir == null ? '^0.3.0' : '\n    path: $localPackagesDir/dartvel_shelf'}
  dartvel_flutter: ${localPackagesDir == null ? '^$dartvelPackageVersion' : '\n    path: $localPackagesDir/dartvel_flutter'}
  ${web ? 'flutter_web_plugins:\n    sdk: flutter' : ''}

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.5.4
  lints: ^4.0.0
  dartvel_cli: ${localPackagesDir == null ? '^$dartvelPackageVersion' : '\n    path: $localPackagesDir/dartvel_cli'}


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
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => buildIndexPage(context);

Widget buildIndexPage(BuildContext context) {
  final loadedAt = DateTime.now().toIso8601String();

  return DVBox.list([
      const DVText('Welcome to Dartvel'),
      const DVText('DARTVEL').modifier(
        DVModifier().fontSize(28).fontWeight(FontWeight.w800),
      ),
      const DVText('Your Dartvel app is ready!').modifier(
        DVModifier().color(Color(0xFF111827)).padding(8),
      ),
      DVText('Loaded at: \$loadedAt'),
      DVBox.wrapLine([
        const DVText('Docs').modifier(DVModifier().padding(12).rounded(8)),
        const DVText('GitHub').modifier(DVModifier().padding(12).rounded(8)),
      ], spacing: 12),
    ]).modifier(
      const DVModifier().padding(24).align(Alignment.center),
    );
}
''';

  static String loadingTemplate(String className) =>
      '''import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';

class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) {
    return const DVBox(
      DVText('Loading...'),
    );
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
      const DVText('ERROR').modifier(
        DVModifier().fontSize(24).fontWeight(FontWeight.w800).color(Colors.red),
      ),
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
Map<String, Object?> handler() {
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

Future<Map<String, Object?>> handler(
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

void main(List<String> arguments) async {
  // Where this launch renders: nothing to decide unless the build opted into
  // the terminal, in which case a launch with no display may leave for it.
  await negotiateDartvelLaunch(arguments);
  runApp(createDartvelApp(arguments: arguments));
}

// The arguments are what a file association, an app link or a second
// launch hands a desktop application; the router opens them.
Widget createDartvelApp({List<String> arguments = const <String>[]}) {
  return MaterialApp.router(
    title: 'Dartvel App',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      useMaterial3: true,
    ),
    routerConfig: createDartvelRouter(arguments: arguments),
  );
}
''';

  static String widgetTestTemplate(String projectName) =>
      '''import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:$projectName/main.dart';

void main() {
  testWidgets('Dartvel application starts', (WidgetTester tester) async {
    // Generated pages are deferred, and loadLibrary() resolves on the real
    // event loop rather than the fake one a widget test runs on. Pumping
    // inside runAsync lets that finish; a plain pumpWidget leaves its timer
    // pending and fails the test rather than the app.
    await tester.runAsync(() async {
      await tester.pumpWidget(createDartvelApp());
      await tester.pump();
    });

    expect(find.byType(WidgetsApp), findsOneWidget);
  });
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

- Flutter SDK \u003e= 3.44.0
- Dart SDK \u003e= 3.12.0

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
import '../dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';


@DVPage(
  title: 'About',
  showAppBar: true,
)
@pragma('vm:entry-point')
Widget _aboutPage(BuildContext context) => buildAboutPage(context);

Widget buildAboutPage(BuildContext context) => DVBox.list([
    const DVText('About'),
    const DVText('About page'),
  ]).modifier(const DVModifier().padding(16));
```

Route is automatically available at `/about`.

### Adding API Endpoints

Create a new file in `lib/backend/functions/`:

```dart
// lib/backend/functions/hello.get.dart
Map<String, Object?> handler() {
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
