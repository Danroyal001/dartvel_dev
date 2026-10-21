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
const String dartvelPackageVersion = '0.13.13';

/// The same, for dartvel_shelf, which is versioned on its own.
///
/// Its own constant rather than a literal in the template below. It was
/// written there as `^0.3.0` beside three interpolated constraints, and
/// because it was a literal, nothing bumped it and nothing checked it: the
/// scaffold asked for a shelf from three releases back while the other three
/// constraints tracked correctly.
const String dartvelShelfVersion = '0.13.13';

class ProjectTemplates {
  static String pubspecTemplate({
    required String name,
    required String org,
    bool web = true,
    bool mobile = true,
    bool desktop = true,
    String? localPackagesDir,
  }) {
    final List<String> flutterPlatforms = <String>[
      if (web) 'web',
      if (mobile) ...<String>['android', 'ios'],
      if (desktop) ...<String>['linux', 'macos', 'windows'],
    ];

    final StringBuffer platformsYaml = StringBuffer();
    if (flutterPlatforms.isNotEmpty) {
      platformsYaml.writeln('platforms:');
      for (final p in flutterPlatforms) {
        platformsYaml.writeln('  $p:');
      }
    }

    final StringBuffer dartvelPlatformsYaml = StringBuffer();
    if (flutterPlatforms.isNotEmpty) {
      dartvelPlatformsYaml.writeln('  platforms:');
      for (final p in flutterPlatforms) {
        dartvelPlatformsYaml.writeln('    - $p');
      }
    }

    return '''
name: $name
description: A new Dartvel project
publish_to: "none"
version: 0.0.1

environment:
  sdk: ">=3.13.0 <4.0.0"
  flutter: ">=3.47.0"
${platformsYaml.toString()}
dependencies:
  flutter:
    sdk: flutter
  go_router: ^14.2.0
  dio: ^5.5.0
  dartvel_core: ${localPackagesDir == null ? '^$dartvelPackageVersion' : '\n    path: $localPackagesDir/dartvel_core'}
  dartvel_shelf: ${localPackagesDir == null ? '^$dartvelShelfVersion' : '\n    path: $localPackagesDir/dartvel_shelf'}
  dartvel_flutter: ${localPackagesDir == null ? '^$dartvelPackageVersion' : '\n    path: $localPackagesDir/dartvel_flutter'}
  ${web ? 'flutter_web_plugins:\n    sdk: flutter' : ''}

dev_dependencies:
  flutter_test:
    sdk: flutter
  lints: ^4.0.0
  dartvel_cli: ${localPackagesDir == null ? '^$dartvelPackageVersion' : '\n    path: $localPackagesDir/dartvel_cli'}
${localPackagesDir == null ? '' : '''
dependency_overrides:
  dartvel_core:
    path: $localPackagesDir/dartvel_core
  dartvel_shelf:
    path: $localPackagesDir/dartvel_shelf
  dartvel_flutter:
    path: $localPackagesDir/dartvel_flutter
  dartvel_cli:
    path: $localPackagesDir/dartvel_cli'''}

flutter:
  uses-material-design: true
  assets:
    - assets/

dartvel:
  org: $org
  backendHost: 0.0.0.0
  backendPort: 3000
  devBackendHost: http://localhost:3000
  prodBackendHost: https://api.${name.replaceAll('_', '-')}.com
  pagesDir: lib/pages
  backendDir: lib/backend
  apiBasePath: /api
  envFiles: [.env, .env.local]
  plugins: []
  ota: false
${dartvelPlatformsYaml.toString()}
  transitions:
    default: fade
    durationMs: 200
    curve: easeInOut

  seo:
    siteName: ${name.replaceAll('_', ' ')}
    defaultTitle: Welcome
    defaultDescription: A Dartvel application
''';
  }

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

  /// `/`: the root route is `lib/pages/index.dart`.
  static const String indexPageTemplate =
      '''import 'package:flutter/widgets.dart';
import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel', showAppBar: true, centerTitle: true)
Widget _indexPage(BuildContext context) => DVBox.list([
      const DVText('Welcome to Dartvel'),
      const DVText('DARTVEL').modifier(
        const DVModifier().fontSize(28).fontWeight(.w800),
      ),
      const DVText('Your Dartvel app is ready!').modifier(
        const DVModifier().padding(8),
      ),
      DVText('Loaded at: \${DateTime.now().toIso8601String()}'),
    ]).modifier(
      const DVModifier().padding(24).align(.center),
    );
''';

  /// The page shown while a page's data loads.
  ///
  /// A functional widget, like everything else a Dartvel project writes: the
  /// private function's name decides the generated class, so
  /// `_indexPageLoading` generates `IndexPageLoading`, which the router
  /// renders. A class is for the rare widget a function cannot express.
  static String loadingTemplate(String className) =>
      '''import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';

@DVFunctionalWidget()
Widget ${_inputName(className)}(BuildContext context) => const DVBox(
      DVText('Loading...'),
    );
''';

  /// `IndexPageLoading` is generated from `_indexPageLoading`.
  static String _inputName(String className) =>
      '_${className[0].toLowerCase()}${className.substring(1)}';

  /// The page shown when a page's data fails to load.
  static String errorTemplate(String className) =>
      '''import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';

@DVFunctionalWidget()
Widget ${_inputName(className)}(BuildContext context) => DVBox.list(<Widget>[
      const DVText('Something went wrong').modifier(
        const DVModifier().fontSize(24).fontWeight(.w800),
      ),
      const DVText('The page could not load its data.'),
      const DVText('Go back').modifier(
        const DVModifier()
            .padding(12)
            .rounded(8)
            .backgroundColor(Colors.black)
            .color(Colors.white)
            .onPressed(() => Navigator.of(context).pop()),
      ),
    ]).modifier(
      const DVModifier().align(.center),
    );
''';

  // Backend functions in the form the generator compiles: a private
  // annotated function, with the client's typed call generated from it. A
  // function named handler is read as a raw handler taking the request, and
  // these took none, so a new project's backend did not compile.
  static const String healthFunctionTemplate = '''// GET /api/health
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
String _health() => 'ok';
''';

  // Typed in and typed out: the client calls `contact(name: ..., email: ...,
  // message: ...)` and gets a String back. The wire format is the framework's.
  static const String contactFormTemplate =
      '''// POST /api/contact (filename without method = POST by default)
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _contact(
    {required String name, required String email, required String message}) async {
  if (name.isEmpty || email.isEmpty || message.isEmpty) {
    throw ArgumentError('All fields are required');
  }
  if (!email.contains('@')) {
    throw ArgumentError.value(email, 'email', 'Invalid email address');
  }
  // To keep what people send, declare a data model in lib/models and save
  // it here; to be told, send it with DV.Notifications.mail.
  return 'Thank you for contacting us, \$name!';
}
''';

  static const String mainTemplate = '''import 'dartvel_client/dartvel_client.dart';

void main(List<String> args) => DV.run(args);
''';

  static String widgetTestTemplate(String projectName) =>
      '''import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:$projectName/dartvel_client/dartvel_client.dart';

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

# Ephemeral native platform folders (generated at build time)
android/
ios/
web/
linux/
windows/
macos/
tizen/
elinux/
webos/
tvos/

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
  errors:
    # A Dartvel generation input is a private declaration whose body is
    # copied into generated code, so nothing in your own files calls it.
    unused_element: ignore
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

- Flutter SDK \u003e= 3.47.0
- Dart SDK \u003e= 3.13.0

### Installation

```bash
flutter pub get
```

### Development

```bash
dartvel dev
```

This will:
- Generate the client in `lib/dartvel_client/`
- Start the backend server on http://localhost:3000
- Run your Flutter app with hot reload

### Generating

`dartvel dev` and `dartvel build` generate before they run, so most of the
time there is nothing to do. To generate on its own — after adding a page,
model or backend function, or on a fresh clone before opening the project in
an editor:

```bash
dart run dartvel_cli:dartvel routes
```

That writes everything under `lib/dartvel_client/`: the barrel your pages
import, the router, models, backend function clients and config. It is
gitignored and never edited by hand: a fresh clone generates it.

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
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Map<String, Object?> _hello() => <String, Object?>{'message': 'Hello World!'};
```

Endpoint is automatically available at `GET /api/hello`, and pages call it as `hello()`.

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
