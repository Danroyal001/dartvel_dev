// What `dartvel build linux --profile development` writes into a project so
// the build pairs with `dartvel dev`, against the example's real runner.
//
// The quiet failures: a source file CMake never compiles, which builds a
// development app that can never pair; functions compiled but not exported,
// which Dart's FFI lookup cannot find, and says nothing louder than a status
// line; and a tunnel compiled into a release build.
import 'dart:io';

import 'package:dartvel_cli/src/build/build_profile.dart';
import 'package:dartvel_cli/src/devclient/android_dev_client.dart';
import 'package:dartvel_cli/src/devclient/apple_dev_client.dart';
import 'package:dartvel_cli/src/devclient/linux_dev_client.dart';
import 'package:dartvel_core/dartvel.dart' show DVDevClientManifest;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final String runner = File(
    p.join('..', '..', 'examples', 'dartvel_example', dvLinuxRunnerCmakePath),
  ).readAsStringSync();

  group('the runner\'s CMakeLists.txt', () {
    test('compiles and exports the tunnel in a Debug build only', () {
      final String cmake = dvLinuxRunnerCmakeWithDevClient(
        runner,
        enabled: true,
      );
      final int block = cmake.indexOf('if(CMAKE_BUILD_TYPE STREQUAL "Debug")');
      expect(block, greaterThan(0));
      final String body = cmake.substring(
        block,
        cmake.indexOf('endif()', block),
      );
      expect(
        body,
        contains(
          r'target_sources(${BINARY_NAME} PRIVATE "dartvel_dev_client.cc")',
        ),
      );
      expect(body, contains('ENABLE_EXPORTS ON'));
      // After the target it adds to exists.
      expect(
        block,
        greaterThan(cmake.indexOf(r'add_executable(${BINARY_NAME}')),
      );
      expect(p.basename(dvLinuxDevTunnelPath), 'dartvel_dev_client.cc');
    });

    test('building twice writes it once, and a release build takes it out', () {
      final String once = dvLinuxRunnerCmakeWithDevClient(
        runner,
        enabled: true,
      );
      expect(dvLinuxRunnerCmakeWithDevClient(once, enabled: true), once);
      expect(dvLinuxRunnerCmakeWithDevClient(once, enabled: false), runner);
    });
  });

  test('the tunnel records the manifest, pins the key and exports what Dart '
      'looks up', () {
    final String source = dvLinuxDevTunnelSource(
      const DVDevClientManifest(
        target: 'linux',
        bindings: <String>['plugin:jni', 'dartvel_flutter@0.5.0'],
      ),
    );
    expect(
      source,
      contains(
        r'{\"target\":\"linux\",\"bindings\":'
        r'[\"dartvel_flutter@0.5.0\",\"plugin:jni\"]}',
      ),
    );
    expect(source, contains('#ifndef NDEBUG'));
    expect(source, contains('"accept-certificate"'));
    expect(source, contains('g_tls_connection_get_peer_certificate'));
    for (final String symbol in <String>[
      dvAppleDevClientVmServiceSymbol,
      dvAppleDevClientServerHostSymbol,
    ]) {
      expect(source, contains('const char* $symbol('));
    }
  });

  test('a Linux development build is built from the entrypoint', () {
    expect(
      dvDevelopmentBuildTarget(
        platform: 'linux',
        profile: DVBuildProfile.development,
        target: null,
      ),
      dvDevelopmentEntrypoint,
    );
  });
}
