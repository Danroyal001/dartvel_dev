// The native server is opt-in at build time.
//
// dartvel_core depends on dartvel_shelf for its request and response types, so
// every Dartvel application pulls this package whether or not it ever serves
// anything. The build hook used to compile and bundle the Axum server
// regardless: a Flutter desktop app that only calls a remote API still shipped
// dartvel_shelf.dll at 7.2 MB, libdartvel_shelf.so at 6.5 MB, or
// dartvel_shelf.framework -- a full HTTP server, with TLS and a static file
// handler, inside a client binary that never listens.
//
// This is the same rule the project already applies to rendering backends:
// never link one by default, and no application gets one it did not ask for.
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as hook;

/// User-defines as they would arrive from an application's pubspec.yaml.
PackageUserDefines definesWith(Map<String, Object?> values) =>
    PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: values,
        basePath: Uri.directory('/'),
      ),
    );

/// Whether a Rust toolchain is present.
///
/// Without one the hook skips for want of cargo, so an assertion that no code
/// asset was produced holds for the wrong reason. These tests are skipped
/// rather than allowed to pass vacuously.
bool get hasCargo {
  try {
    return Process.runSync('cargo', <String>['--version']).exitCode == 0;
  } on Object {
    return false;
  }
}

void main() {
  test('an application that has not asked for a server gets no code asset',
      () async {
    await testBuildHook(
      mainMethod: hook.main,
      extensions: <ProtocolExtension>[
        CodeAssetExtension(
          targetOS: OS.linux,
          targetArchitecture: Architecture.x64,
          linkModePreference: LinkModePreference.dynamic,
        ),
      ],
      check: (BuildInput input, BuildOutput output) {
        expect(output.assets.encodedAssets, isEmpty);
      },
    );
  },
      skip: hasCargo
          ? false
          : 'needs a Rust toolchain: without cargo the hook skips anyway and '
              'this would pass for the wrong reason');

  test('an application that asks for one gets it', () async {
    // Skipped where cargo is absent: the hook cannot build without it, and
    // that is a toolchain fact rather than a failure of this rule.
    await testBuildHook(
      mainMethod: hook.main,
      userDefines: definesWith(<String, Object?>{'embed_server': true}),
      extensions: <ProtocolExtension>[
        CodeAssetExtension(
          targetOS: OS.linux,
          targetArchitecture: Architecture.x64,
          linkModePreference: LinkModePreference.dynamic,
        ),
      ],
      check: (BuildInput input, BuildOutput output) {
        expect(input.userDefines['embed_server'], isTrue);
        expect(output.assets.encodedAssets, isNotEmpty);
      },
    );
  },
      // A real cargo build from a cold target directory takes minutes; the
      // 30-second default made this fail for taking the time it needs.
      timeout: const Timeout(Duration(minutes: 20)),
      skip: hasCargo
          ? false
          : 'needs a Rust toolchain to produce the code asset');

  test('the opt-in is read as a value, not as the presence of a key', () async {
    // `embed_server: false` written explicitly must mean no, or turning the
    // feature off would require deleting the line rather than setting it.
    await testBuildHook(
      mainMethod: hook.main,
      userDefines: definesWith(<String, Object?>{'embed_server': false}),
      extensions: <ProtocolExtension>[
        CodeAssetExtension(
          targetOS: OS.linux,
          targetArchitecture: Architecture.x64,
          linkModePreference: LinkModePreference.dynamic,
        ),
      ],
      check: (BuildInput input, BuildOutput output) {
        expect(output.assets.encodedAssets, isEmpty);
      },
    );
  },
      skip: hasCargo
          ? false
          : 'needs a Rust toolchain: without cargo the hook skips anyway');
}
