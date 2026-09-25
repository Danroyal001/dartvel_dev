# A Flutter application on the umbrella package

`dartvel create` starts a project on the individual Dartvel packages. This
example shows the other layout: one `dartvel_dev` constraint that moves every
Dartvel package together. It was checked against 0.6.0 by generating the
client, analyzing the application, and analyzing the generated server.

For a full walk from an empty directory to a web build, see the
[dartvel_cli example](https://pub.dev/packages/dartvel_cli/example).

## pubspec.yaml

```yaml
name: notes_app
publish_to: none
version: 0.0.1

environment:
  sdk: ">=3.13.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  dartvel_dev: ^0.6.0
  # The umbrella decides these versions. Declaring them is for the
  # depend_on_referenced_packages lint, since models and backend functions
  # import package:dartvel_core by name.
  dartvel_core: any
  dartvel_flutter: any

dev_dependencies:
  dartvel_cli: ^0.6.0   # for `dart run dartvel_cli:dartvel`
  lints: ^4.0.0

flutter:
  uses-material-design: true

dartvel:
  pagesDir: lib/pages
  backendDir: lib/backend
```

## A data model

```dart
// lib/models/note.dart
import 'package:dartvel_core/dartvel.dart';

@DVModel()
@pragma('vm:entry-point')
class _Note {
  final String id;
  final String name;

  const _Note({required this.id, required this.name});
}
```

The class is private because it is the generator's input. The application
uses the generated `Note`.

## A backend function

```dart
// lib/backend/functions/health.get.dart   ->  GET /api/health
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Map<String, Object?> _health() => <String, Object?>{
      'status': 'ok',
      'timestamp': DateTime.now().toIso8601String(),
    };
```

Import `dartvel_core` here rather than the umbrella. The generated server is
pure Dart and drops any import that reaches Flutter, which
`package:dartvel_dev` does.

## A page

```dart
// lib/pages/index.dart   ->  /
import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Notes', showAppBar: true)
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => DVBox.list([
      Note.Form(),
    ]).modifier(const DVModifier().padding(24));
```

Pages import the generated barrel, which re-exports the framework with the
application's own routes, models and client.

## Generate and run

With the CLI installed:

```sh
flutter pub get
dartvel routes      # writes lib/dartvel_client/
dartvel dev
```

Or through the project's own dev dependency, with no binary installed:

```sh
dart run dartvel_cli:dartvel routes
dart run dartvel_cli:dartvel dev
```

`lib/main.dart` is the one `dartvel create` writes; it calls the generated
`createDartvelRouter()`:

```dart
import 'package:flutter/material.dart';
import 'dartvel_client/dartvel_client.dart';

void main(List<String> arguments) async {
  await negotiateDartvelLaunch(arguments);
  runApp(MaterialApp.router(
    routerConfig: createDartvelRouter(arguments: arguments),
  ));
}
```
