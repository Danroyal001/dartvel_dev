# A session with `dartvel`

This walks through a new application from an empty directory to a web build:
create it, add a page and a data model, run it with `dartvel dev`, and build
it for the web. Every command below was run against `dartvel` 0.6.0 on Linux
with Flutter 3.47. Output is trimmed to the lines that matter.

You need Flutter 3.44 or newer to build and run the application. `dartvel`
itself is a self-contained binary; see the
[package README](../README.md#install) for how to install it.

## 1. Check the machine

```sh
dartvel doctor
```

```text
[+] Dart SDK: Dart SDK version: 3.13.4 (stable)
[+] Flutter SDK: Flutter 3.47.5 • channel stable
[+] Git: git version 2.53.0
...
[-] Shorebird: Not installed (optional for OTA updates)
```

Run inside a project, it also checks the project; see step 3.

## 2. Create the application

```sh
dartvel create notes_app
cd notes_app
```

```text
Running: flutter create .
Flutter project scaffolded
Project structure created
Running: flutter pub get
Project initialized successfully!
```

`create` runs `flutter create`, then writes the Dartvel layout over it:

```text
lib/main.dart
lib/pages/index.dart                 # the page at /
lib/pages/index.loading.dart
lib/pages/index.error.dart
lib/backend/functions/health.get.dart   # GET  /api/health
lib/backend/functions/contact.dart      # POST /api/contact
.env
pubspec.yaml                         # with a dartvel: section
```

If `flutter pub get` fails (no network, or an SDK older than Dartvel's floor),
`create` warns and still writes the project. Fix what pub reported and run
`flutter pub get` yourself.

`create` refuses a directory that already holds a project it did not write:

```text
DV-ADOPT-005: .../pubspec.yaml was not written by Dartvel, and `dartvel create`
would replace it — every dependency and setting in it. Refusing.
```

For that case, `dartvel init --dry-run` shows what adding Dartvel to the
existing project would change, and `dartvel init` applies it.

## 3. Add a page and a data model

```sh
dartvel generate page about
dartvel generate model note
```

```text
Generated page: .../lib/pages/about.dart
Generated model: .../lib/models/note.dart
```

The model is a private class the generator reads:

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

Your code uses the generated public `Note`, never `_Note`. Replace the starter
page with one that shows a form for a new note and a typed link home:

```dart
// lib/pages/about.dart
import '../dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

@DVPage(title: 'New note', showAppBar: true)
@pragma('vm:entry-point')
Widget _aboutPage(BuildContext context) => DVBox.list([
      Note.Form(),
      TextButton(
        onPressed: () => context.navigateToPage(DVRoutes.index),
        child: const Text('Back home'),
      ),
    ]).modifier(const DVModifier().padding(24));
```

`Note.Form()` saves a new record itself; it takes no callback. `DVRoutes.index`
is generated from `lib/pages/index.dart`, so moving that page is a compile
error here rather than a broken link.

`showAppBar: true` gives the page a bar whose title is its level 1 heading.
The starter page `generate page` writes has no heading, and `dartvel build web`
refuses a page without one (step 6).

## 4. Generate the client

```sh
dartvel routes
```

```text
dartvel: loaded env file: .env
dartvel: generated lib/dartvel_client/* and .dart_tool/dartvel_backend*.g.dart
Generated routes and client artifacts.
```

`dartvel dev` and `dartvel build` run this first on their own. Running it by
hand is for the analyzer: until it runs, `../dartvel_client/dartvel_client.dart`
does not exist and the page above does not resolve. Look at what it produced:

```sh
dartvel inspect routes
dartvel inspect models
dartvel inspect functions
```

```text
/  indexPage  lib/pages/index.dart:4
/about  aboutPage  lib/pages/about.dart:4
/account/delete  DeletePage  pubspec.yaml: dartvel.auth.pages.delete
...
/login  SignInWithEmailAndPasswordPage  pubspec.yaml: dartvel.auth.pages.signIn
/sign-up  SignUpPage  pubspec.yaml: dartvel.auth.pages.signUp

Note  2 fields  lib/models/note.dart:3

POST /contact  contact  lib/backend/functions/contact.dart:7
GET /health  health  lib/backend/functions/health.get.dart:4
```

The account and sign-in pages come with every project.

To have CI fail when committed generated output is out of date:

```sh
dartvel generate --check
```

```text
Generated output is up to date.
```

And `dartvel doctor`, now inside the project:

```text
[+] dartvel: configuration section found
[+] Flutter dependency configured
[+] lib/pages exists
[+] lib/backend/functions exists
[+] lib/models exists
[+] .env present

[+] All system checks passed!
```

## 5. Run it

```sh
dartvel dev -d web-server --web-port 8099
```

```text
Pairing: serving HEAD on port 8787.
Scan with the camera on a device running a development build:
  <QR code>
  dartvel-dev://pair?server=...
Dartvel web app local URL: http://localhost:8099
dartvel dev: starting backend and Flutter app...
[dev] Compiling Studio for /__studio (flutter build web)...
[backend] dartvel backend listening on http://0.0.0.0:3000/api
[dev] Studio: http://localhost:3000/__studio/?dev_grant=... (only the browser that opens this link gets in).
[flutter] lib/main.dart is being served at http://0.0.0.0:8099
[flutter] r Hot reload.
```

`dev` generates, starts the backend on `dartvel.backendPort` (3000), runs the
Flutter app on the device you pick with `-d`, and serves Studio over
the project's models. A save regenerates and hot reloads. The QR code pairs a
phone running `dartvel build android --profile development`; pairing is always
on, and `--pairing-port` moves it.

While it runs, the backend answers from `lib/backend/functions`:

```sh
curl http://localhost:3000/api/health
```

```text
{"status":"ok","timestamp":"2026-09-25T14:05:58.087147"}
```

Stop it with Ctrl+C.

## 6. Build for the web

```sh
dartvel build web
```

```text
Generating Dartvel artifacts...
Building for web...
   flutter build web --release --tree-shake-icons
✓ Built build/web
   Reading the semantics tree for 4 routes...
   Captured 4 of 4.
web build successful
Build complete!
```

On this machine it took about two minutes. `build/web` holds the Flutter web
app plus a prerendered `index.html` per route (`about/`, `login/`,
`sign-up/`, `account/`...), so a crawler or a browser with scripts off sees
each page's text.

The semantics pass is also an accessibility audit. With an `/about` page that
had no heading (as the `generate page` starter has none), the same command
ended with:

```text
   /about  [page-heading]  The page has no headings, so a screen reader user has no way to tell what it is or to skim it.
1 accessibility finding(s)
```

and exits 1. Give the page a heading, or record a waiver under
`dartvel.accessibility.waivers` with a `route`, a `rule` and a `reason`.

`dartvel preview` serves the finished build locally on port 8080.

## Where next

- `dartvel build web-server` writes `build/server`, one executable carrying
  the backend, the native server library and the web app, which runs on its
  own on another machine.
- `dartvel deploy --target web --provider vercel` (or `firebase-hosting`,
  `netlify`, `cloudflare`) builds and ships the web app.
- `dartvel --help` lists every command.
