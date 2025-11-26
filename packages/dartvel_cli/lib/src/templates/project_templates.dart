class ProjectTemplates {
  static String pubspec(String packageName) => '''
name: $packageName
description: A new Dartvel project.
publish_to: "none"

environment:
  sdk: ">=3.4.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  dartvel_flutter:
    path: ../packages/dartvel_flutter
  dartvel_core:
    path: ../packages/dartvel_core

dev_dependencies:
  flutter_test:
    sdk: flutter
  lints: ^4.0.0

flutter:
  uses-material-design: true

dartvel:
  backendHost: 0.0.0.0
  backendPort: 3000
  devBackendHost: http://localhost:3000
  apiBasePath: /api
  pagesDir: lib/pages
  backendDir: lib/backend
  envFiles: [ .env, .env.local ]
''';

  static const String analysisOptions =
      'include: package:lints/recommended.yaml\n';

  static String readme(String projectName) => '''# $projectName

Generated with `dartvel new`. Run the following to get started:

```
cd $projectName
flutter pub get
dart run dartvel_cli:dartvel dev
```

Project layout follows the recommended Dartvel structure.
''';

  static const String indexPage = '''import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';

class IndexPage extends DartvelPage {
  const IndexPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Dartvel')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Hello from Dartvel starter template!'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/about'),
              child: const Text('Go to /about'),
            )
          ],
        ),
      ),
    );
  }
}
''';

  static const String aboutPage = '''import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';

class AboutPage extends DartvelPage {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: const Center(
        child: Text('Edit lib/pages/about.page.dart to customise.'),
      ),
    );
  }
}
''';

  static const String layoutPage = '''import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';

class RootLayout extends DartvelLayout {
  const RootLayout({super.key, required super.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: child),
    );
  }
}
''';

  static const String helloFunction = '''import 'package:dartvel_core/dartvel.dart';

Future<ResponseType> handler(RequestType req) async {
  final name = req.url.queryParameters['name'] ?? 'friend';
  return Res.json({'message': 'Hello, ' + name + '!'});
}
''';

  static const String echoFunction = '''import 'package:dartvel_core/dartvel.dart';

Future<ResponseType> handler(RequestType req) async {
  final body = await req.body.jsonDecode();
  return Res.json({'echo': body});
}
''';

  static const String gitignore = '''/.dart_tool/
/build/
.env
.env.local
lib/dartvel_client/
''';
}
