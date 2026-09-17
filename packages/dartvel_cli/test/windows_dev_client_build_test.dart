// What `dartvel build windows --profile development` writes into a project so
// the build pairs with `dartvel dev`, against the example's real runner.
//
// The quiet failures: a source file CMake never compiles; a tunnel compiled
// into a Profile or Release build, which on Windows is not decided by
// CMAKE_BUILD_TYPE -- the Visual Studio generator builds every configuration
// from one project, so a check on it is always false and silently compiles
// nothing, or always true and ships the tunnel; and functions compiled but
// not exported, which Dart's FFI lookup in the process cannot find.
import 'dart:io';

import 'package:dartvel_cli/src/build/build_profile.dart';
import 'package:dartvel_cli/src/devclient/android_dev_client.dart';
import 'package:dartvel_cli/src/devclient/apple_dev_client.dart';
import 'package:dartvel_cli/src/devclient/windows_dev_client.dart';
import 'package:dartvel_core/dartvel.dart' show DVDevClientManifest;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final String runner = File(
    p.join('..', '..', 'examples', 'dartvel_example', dvWindowsRunnerCmakePath),
  ).readAsStringSync();

  group('the runner\'s CMakeLists.txt', () {
    test('compiles the tunnel into the Debug configuration only', () {
      final String cmake = dvWindowsRunnerCmakeWithDevClient(
        runner,
        enabled: true,
      );
      expect(
        cmake,
        contains(
          r'target_sources(${BINARY_NAME} PRIVATE '
          r'"$<$<CONFIG:Debug>:dartvel_dev_client.cpp>")',
        ),
      );
      expect(cmake, isNot(contains('CMAKE_BUILD_TYPE')));
      expect(
        cmake.indexOf('dartvel_dev_client.cpp'),
        greaterThan(cmake.indexOf(r'add_executable(${BINARY_NAME}')),
      );
      expect(p.basename(dvWindowsDevTunnelPath), 'dartvel_dev_client.cpp');
    });

    test('a checkout with Windows line endings gets the tunnel too, and loses '
        'it byte for byte', () {
      // git on a Windows runner checks the runner out with CRLF, and a search
      // for "\n)\n" found no add_executable there: the build refused on the
      // only platform it is for (Dev client run 35169461443).
      final String crlf = runner
          .replaceAll('\r\n', '\n')
          .replaceAll('\n', '\r\n');
      final String added = dvWindowsRunnerCmakeWithDevClient(
        crlf,
        enabled: true,
      );
      expect(added, contains('dartvel_dev_client.cpp'));
      expect(added.replaceAll('\r\n', ''), isNot(contains('\n')));
      expect(dvWindowsRunnerCmakeWithDevClient(added, enabled: true), added);
      expect(dvWindowsRunnerCmakeWithDevClient(added, enabled: false), crlf);
    });

    test('building twice writes it once, and a release build takes it out', () {
      final String once = dvWindowsRunnerCmakeWithDevClient(
        runner,
        enabled: true,
      );
      expect(dvWindowsRunnerCmakeWithDevClient(once, enabled: true), once);
      expect(dvWindowsRunnerCmakeWithDevClient(once, enabled: false), runner);
    });
  });

  test('the tunnel records the manifest, pins the key and exports what Dart '
      'looks up', () {
    final String source = dvWindowsDevTunnelSource(
      const DVDevClientManifest(
        target: 'windows',
        bindings: <String>['plugin:jni', 'dartvel_flutter@0.5.0'],
      ),
    );
    expect(
      source,
      contains(
        r'{\"target\":\"windows\",\"bindings\":'
        r'[\"dartvel_flutter@0.5.0\",\"plugin:jni\"]}',
      ),
    );
    expect(source, contains('#ifdef _DEBUG'));
    // The pin is read from the certificate's own public key info, and
    // Windows' own validation is switched off so nothing else decides.
    expect(source, contains('SECPKG_ATTR_REMOTE_CERT_CONTEXT'));
    expect(source, contains('SubjectPublicKeyInfo'));
    expect(source, contains('SCH_CRED_MANUAL_CRED_VALIDATION'));
    for (final String symbol in <String>[
      dvAppleDevClientVmServiceSymbol,
      dvAppleDevClientServerHostSymbol,
    ]) {
      expect(source, contains('__declspec(dllexport) const char* $symbol('));
    }
  });

  test('a Windows development build is built from the entrypoint', () {
    expect(
      dvDevelopmentBuildTarget(
        platform: 'windows',
        profile: DVBuildProfile.development,
        target: null,
      ),
      dvDevelopmentEntrypoint,
    );
  });

  test('the Dart session starts the tunnel on Windows', () {
    final String session = File(
      '../dartvel_flutter/lib/src/devclient/dev_session.dart',
    ).readAsStringSync();
    expect(session, contains('Platform.isWindows'));
  });
}
