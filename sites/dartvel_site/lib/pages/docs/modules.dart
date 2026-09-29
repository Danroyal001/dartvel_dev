import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

// Modules: a whole Dartvel app mounted inside another at a path, the native
// code a module can carry behind its Dart surface, and the signing and
// capability checks that decide whether a published one can be trusted.
// Status boxes follow docs/spec-status.json.
@DVPage(
  title: 'Dartvel modules: Dart, npm, C, Rust, JVM and Swift behind one surface',
  description: 'A Dartvel module is a complete app, or a Dart, npm, C, Rust, '
      'JVM or Swift package that dartvel add wraps as one. The parent '
      'mounts, grants and calls it the same way.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsModulesPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsmodules,
      lead: <String>[
        'A module is a complete Dartvel app with its own pages, models and '
            'backend. Mount it at a path and the parent serves all of it.',
        'Its Dart can call a Rust crate or a C library over FFI, or an '
            'Android library over JNI. The parent mounts it, grants it and '
            'calls it the same way whatever is underneath.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'mount',
          title: 'Mount a module at a path',
          children: <Widget>[
            DocsShell(<String>[
              '# pubspec.yaml',
              'dartvel:',
              '  modules:',
              '    notes:',
              '      source:',
              '        path: modules/notes',
              '      mount: /notes',
              '      deployment: embedded',
            ]),
            Bullets(<String>[
              'The module\'s own /view/:id is served at /notes/view/:id. Its '
                  'backend functions, schedules and AI tools join the '
                  'parent\'s, and `dartvel db migrate` creates its tables.',
              'The parent reaches it as DV.Modules.notes, with paths resolved '
                  'against wherever it is mounted, so the module never names '
                  'its own mount point.',
              'Two functions on one path, or two models on one table, stop the '
                  'build instead of one quietly winning.',
            ]),
            DocsShell(<String>['dartvel modules list']),
          ],
        ),
        DocsSection(
          id: 'native',
          title: 'Put a Rust crate or an Android library behind a module',
          children: <Widget>[
            DocsText('The parent sees a module. Whether its Dart calls a REST '
                'API, a Rust crate over FFI or an Android library over JNI, '
                'it is mounted, granted, pinned and called the same way, and '
                'nothing in the parent names the language underneath.'),
            DocsShell(<String>[
              'modules/payments/',
              '  pubspec.yaml       the module, and what it may reach',
              '  hook/build.dart    runs cargo for the target being built',
              '  rust/Cargo.toml    the crate, built as a cdylib',
              '  lib/payments.dart  the Dart the parent calls',
            ]),
            DocsCode('modules-native-ffi'),
            DocsShell(<String>[
              '# modules/payments/pubspec.yaml',
              'name: payments',
              'dependencies:',
              '  hooks: ^0.20.1',
              '  code_assets: ^0.19.7',
              'dartvel:',
              '  module:',
              '    id: payments',
              '    capabilities:',
              '      nativeBindings: true',
            ]),
            DocsShell(<String>[
              '# pubspec.yaml',
              'dartvel:',
              '  modules:',
              '    payments:',
              '      source:',
              '        path: modules/payments',
              '      mount: /payments',
              '      deployment: embedded',
              '      grant:',
              '        nativeBindings: true',
            ]),
            Bullets(<String>[
              '`dartvel build` reads the module\'s lib, bin and hook '
                  'directories first. An import of dart:ffi or package:jni, a '
                  'DynamicLibrary.open or an @Native function is a native '
                  'binding, and one the parent did not grant stops the build '
                  'with DV-MODULE-001.',
              'The module says so too. Binding native code without '
                  'declaring nativeBindings is a DV-MODULE-007 warning, and a '
                  'grant that differs from what the module asks for stops '
                  'the build with DV-MODULE-003. `dartvel doctor --modules` '
                  'runs the same checks.',
              'A module holding its own Cargo.toml is still a Dartvel '
                  'project, so `dartvel add ../payments` mounts it directly '
                  'and wraps nothing.',
              'The crate is compiled by the module\'s build hook, which Dart '
                  'runs for each target it builds and bundles with the app. '
                  'Dartvel\'s own server is a Rust crate shipped this way: it '
                  'lands in bundle/lib on Linux and in Contents/Frameworks on '
                  'macOS.',
              'An Android library is reached the same way over JNI: jnigen '
                  'generates Dart classes for it and the module\'s surface '
                  'calls them. Dartvel\'s own Android features under '
                  'DV.Platform are bound like this, and nothing uses platform '
                  'channels.',
              'The web has no FFI. A C library or a Rust crate added with '
                  '`dartvel add` is also compiled to WebAssembly for the '
                  'browser, for functions of numbers. A module whose FFI '
                  'surface you wrote yourself keeps those calls behind a '
                  'conditional import.',
            ]),
            DocsNote('What `dartvel add` does with a bare directory',
                'Pointed at a directory with a Cargo.toml, C sources, a '
                'Package.swift or a .wasm file, it generates the module as '
                'cargo:, c:, swift: or wasm: would. A build.gradle or a '
                'package.json is named and refused: add the library as '
                'maven: or jar:, or the package as npm:.'),
            DocsStatus('Native Binding Graph', missing: <String>[
              'The binding graph itself: DVBindingGraph and its five binding '
                  'kinds. A module you write yourself around a crate or an '
                  'Android library still has a hand-written FFI or JNI '
                  'surface.',
              'Typed errors naming the module, the operation and the '
                  'binding kind, and foreign callbacks turned into a Future '
                  'or a Stream at the boundary.',
              'An ownership annotation on every pointer that crosses, with '
                  'an ambiguous one refused as DV-BIND-003.',
              '`dartvel inspect bindings --json`, and DV-BIND-001 through '
                  'DV-BIND-008.',
            ]),
          ],
        ),
        DocsSection(
          id: 'trust',
          title: 'Publish a signed module, and pin what you mount',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel modules publish --key signing.key --key-id acme',
              'dartvel modules pin',
              'dartvel doctor --modules',
            ]),
            Bullets(<String>[
              'publish reads the capabilities your code uses, such as the '
                  'domains it calls, the secrets it reads and the native code '
                  'it binds, and refuses when they differ from what you '
                  'declared. Then it signs and publishes to pub.dev.',
              'pin writes dartvel.module.lock with each module\'s version, '
                  'digest, signing key and publisher. A changed key, a '
                  'stripped signature or an older version stops the build.',
              'The parent grants each module\'s capabilities under '
                  'dartvel.modules. A module that uses more than it was '
                  'granted is refused.',
            ]),
          ],
        ),
        DocsSection(
          id: 'sources',
          title: 'Where a module can come from',
          children: <Widget>[
            DocsText('A module is also how capability from outside Dart '
                'reaches an application. Every capability a product needs '
                'already exists behind somebody\'s SDK, so one command '
                'resolves any of them and what comes back is always a '
                'module.'),
            DocsShell(<String>[
              'dartvel add ../store',
              'dartvel add ./vendor_api --as vendorErp',
              'dartvel add ./vendor_api --as vendorErp \\',
              '  --url https://api.vendor.com/graphql',
              'dartvel add ./vendor_api --as vendorErp --dry-run',
            ]),
            Bullets(<String>[
              'add reads the directory and says what it found. A pubspec with '
                  'a `dartvel key` is a Dartvel project; a Package.swift, a '
                  'Cargo.toml, a build.gradle, a package.json or an '
                  'openapi.yaml each name a source the spec covers. A '
                  'directory matching none of them is refused with a list of '
                  'what it holds.',
              'A source that is already a Dartvel project is mounted '
                  'directly. Nothing is wrapped, because wrapping a module '
                  'that is already a module adds a layer whose only job is '
                  'to be walked through.',
              'An OpenAPI document or a GraphQL schema is generated into '
                  'modules/<package>: a pubspec declaring the module and the '
                  'host its calls go through, and a Dart library of typed '
                  'methods. There is no binding and no foreign runtime, so a '
                  'described API is the cheapest source there is.',
              'A GraphQL schema names no server, so --url gives the endpoint '
                  'to post to. It overrides an OpenAPI document\'s servers '
                  'too, which is how a published document is used against '
                  'staging without editing it.',
              'Each GraphQL call gets its own result types. A class carries '
                  'the fields that query selected and no others, so a field '
                  'that is null is one the service answered null for. Where '
                  'the graph turns back on itself the selection stops and the '
                  'class says which type it returned to.',
              'The host goes under dartvel.http, so the base URL, the '
                  'credential, the retries and the timeout are configuration. '
                  'The generated calls carry none of them.',
              '--dry-run prints every file it would write and changes '
                  'nothing. Everything is generated before anything is '
                  'written, so a document add cannot read stops the command '
                  'with an empty modules directory.',
              'Every other kind of source is wrapped: see the next '
                  'section. A .proto is the one that is named and refused.',
            ]),
            DocsNote('Every kind of source works but one',
                'A .proto is named and refused; everything else in the list '
                'above is generated into a module and pinned in the '
                'lockfile.'),
          ],
        ),
        DocsSection(
          id: 'foreign',
          title: 'Wrap a package from any ecosystem',
          children: <Widget>[
            DocsText('`dartvel add` turns a Dart package, an npm package, a C '
                'library, a Rust crate, a WebAssembly binary, a Maven artifact '
                'or jar, a Swift package or a CocoaPod into a module you call '
                'as DV.Modules.<id>. Each operation says what it does on a '
                'device, in a browser and on the backend, and the build checks '
                'your calls against it.'),
            DocsShell(<String>[
              'dartvel add pub:slugify@^2.0.0',
              'dartvel add git:https://github.com/acme/textkit.git#v1.4.0',
              'dartvel add npm:@acme/text-kit@^3.0.0',
              'dartvel add vendor/mathkit          # C headers and sources',
              'dartvel add cargo:vendor/fastmath   # or cargo:<crate>@<version>',
              'dartvel add wasm:vendor/engine.wasm',
              'dartvel add maven:com.acme:scanner@4.2.0 --class com.acme.Scanner',
              'dartvel add swift:vendor/TextKit',
              'dartvel add pod:CalcKit@^1.0.0',
              'dartvel inspect modules',
            ]),
            DocsCode('modules-dart-package'),
            DocsTable(columns: <String>[
              'Source',
              'Device',
              'Browser',
              'Backend',
            ], rows: <List<String>>[
              <String>['Dart package', 'the package', 'the package; one that needs dart:io runs on the backend over generated RPC', 'the package, unless it needs Flutter'],
              <String>['npm package', 'Node bundled beside a desktop app; phones not yet', 'dynamic import() of the bundled package', 'Node, one process per call'],
              <String>['C library, Rust crate', '@Native, built by the module\'s hook', 'the same sources compiled to WebAssembly, for functions of numbers', '@Native, built by the hook'],
              <String>['WebAssembly binary', 'Node bundled beside a desktop app; phones not yet', 'WebAssembly.instantiate', 'Node\'s WebAssembly'],
              <String>['Maven artifact or jar', 'JNI through package:jni, Android only', '--elsewhere', '--elsewhere'],
              <String>['Swift package or pod', 'C-ABI shim built by the hook: iOS and macOS, and Linux and Windows with the Swift toolchain unless it imports an Apple framework', '--elsewhere', 'the Swift toolchain, for a package that imports no Apple framework'],
            ]),
            Bullets(<String>[
              'Every download is checked against what its registry publishes: '
                  'pub.dev\'s sha256, npm\'s sha512 integrity, crates.io\'s '
                  'sha256, Maven Central\'s sha1. git and pod sources are '
                  'pinned to a commit.',
              'The module exposes what can cross every environment it runs '
                  'in: numbers, booleans, strings, lists and maps. What cannot '
                  'is listed in the module\'s README with the reason: a '
                  'callback, a generic, an instance method, or a pointer whose '
                  'owner nobody named (DV-BIND-003).',
              'Where a source cannot run but the backend can, an asynchronous '
                  'call crosses to the backend, and the build asks who may make '
                  'it: dartvel.modules.<id>.backendPolicy names a policy, or '
                  'public (DV-MODULE-021 when it is missing), because the call '
                  'runs with the server\'s authority.',
              '--elsewhere unavailable makes a call from an environment the '
                  'source cannot reach throw DVModuleUnavailable naming the '
                  'module, the call and the environment, instead of crossing to '
                  'the backend. --elsewhere noop makes it do nothing.',
              '`dartvel build` refuses a call it can see reaching an unavailable '
                  'operation (DV-MODULE-013), and a call from a target the '
                  'module does not run on (DV-MODULE-014).',
              'dartvel.module.lock pins the source, its digest, the hash of the '
                  'generated module and the generator version. `dartvel inspect '
                  'modules` reports a module edited by hand (DV-MODULE-016).',
              'npm and WebAssembly calls on the backend need Node on the host '
                  '(DV-MODULE-020 when it is missing); `dartvel build` copies Node '
                  'into a desktop bundle that calls one. Compiling C for the '
                  'browser needs clang and a wasm-ld (a Rust toolchain carries '
                  'one), and a crate needs the wasm32-unknown-unknown target. Building a C library needs '
                  'a C compiler, a crate needs cargo, and a Swift package or '
                  'pod needs Xcode.',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Modules', missing: <String>[
              'A module that runs in its own deployment contributes no '
                  'backend to the parent build, by design.',
              'Tree-shaking per environment, so a module with a heavy native '
                  'library costs a web build nothing until a web page calls '
                  'it.',
              'Ambient requirements: a module declaring the app lifecycle '
                  'hooks, background work and push registration an SDK such '
                  'as Firebase needs, wired into the target\'s entry points.',
            ]),
            DocsStatus('Module Sources', missing: <String>[
              'Node on phones, a WebAssembly runtime without Node, and '
                  'strings across WebAssembly.',
              'A .proto source, a Swift package with dependencies, the JVM '
                  'outside Android, and a backend JVM carrier.',
              'A component library exported with exports: components.',
            ]),
            DocsStatus('Module Health'),
            DocsStatus('Module Distribution and Trust', missing: <String>[
              'Capabilities are checked at build time only. A running module\'s '
                  'network and secret access are not checked yet.',
              'Nothing calls pub.dev to verify the publisher, so without a '
                  'registry lookup it is recorded as unverified.',
            ]),
          ],
        ),
      ],
    );
