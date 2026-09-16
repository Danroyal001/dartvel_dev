// What `dartvel build ios|macos --profile development` writes into a project
// so the build pairs with `dartvel dev`.
//
// Against the example's real Xcode projects and Info.plists, because every
// failure here is quiet: a source file added as a reference but not to the
// application's Sources phase compiles nothing and the build succeeds; a URL
// scheme in the Info.plist every configuration shares is a release build that
// answers dartvel-dev:// links; and a project that is rewritten differently on
// every build is a diff on every branch.
import 'dart:io';

import 'package:dartvel_cli/src/build/build_profile.dart';
import 'package:dartvel_cli/src/devclient/android_dev_client.dart';
import 'package:dartvel_cli/src/devclient/apple_dev_client.dart';
import 'package:dartvel_core/dartvel.dart' show DVDevClientManifest;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _example(String relative) => File(
  p.join('..', '..', 'examples', 'dartvel_example', relative),
).readAsStringSync();

/// The block of the XCBuildConfiguration [name] in the configuration list of
/// the application target.
String _appConfiguration(String pbxproj, String name) {
  final RegExp block = RegExp(
    r'\t\t[0-9A-F]{24} /\* ' +
        name +
        r' \*/ = \{\n\t\t\tisa = XCBuildConfiguration;.*?\n\t\t\};',
    dotAll: true,
  );
  return block
      .allMatches(pbxproj)
      .map((RegExpMatch m) => m.group(0)!)
      .firstWhere(
        (String b) => b.contains('INFOPLIST_FILE = ') && !b.contains('Tests'),
      );
}

/// The files list of the application target's Sources phase.
String _appSources(String pbxproj) {
  final RegExp target = RegExp(
    r'\t\t[0-9A-F]{24} /\*[^*]*\*/ = \{\n\t\t\tisa = PBXNativeTarget;.*?\n\t\t\};',
    dotAll: true,
  );
  final String app = target
      .allMatches(pbxproj)
      .map((RegExpMatch m) => m.group(0)!)
      .firstWhere((String b) => b.contains('product-type.application"'));
  final String phase = RegExp(
    r'([0-9A-F]{24}) /\* Sources \*/',
  ).firstMatch(app)!.group(1)!;
  return RegExp(
    '\\t\\t$phase /\\* Sources \\*/ = \\{.*?\\n\\t\\t\\};',
    dotAll: true,
  ).firstMatch(pbxproj)!.group(0)!;
}

void main() {
  for (final String platform in <String>['ios', 'macos']) {
    group('$platform: the Xcode project', () {
      final String original = _example(
        '$platform/Runner.xcodeproj/project.pbxproj',
      );

      test('compiles the tunnel as part of the application', () {
        final String project = dvApplePbxprojWithDevClient(
          original,
          enabled: true,
        );
        final String sources = _appSources(project);
        expect(sources, contains('$dvAppleDevTunnelFile in Sources'));
        // A reference to the file, in the group the file is written into.
        expect(
          project,
          contains('path = $dvAppleDevTunnelFile; sourceTree = "<group>";'),
        );
      });

      test('gives the Debug configuration, and only it, the development '
          'Info.plist', () {
        final String project = dvApplePbxprojWithDevClient(
          original,
          enabled: true,
        );
        expect(
          _appConfiguration(project, 'Debug'),
          contains('INFOPLIST_FILE = "$dvAppleDevelopmentInfoPlistPath";'),
        );
        for (final String name in <String>['Release', 'Profile']) {
          expect(
            _appConfiguration(project, name),
            contains('INFOPLIST_FILE = Runner/Info.plist;'),
            reason: name,
          );
        }
      });

      test('building twice writes the same project', () {
        final String once = dvApplePbxprojWithDevClient(
          original,
          enabled: true,
        );
        expect(dvApplePbxprojWithDevClient(once, enabled: true), once);
        expect(
          '$dvAppleDevTunnelFile in Sources */,'.allMatches(once).length,
          1,
        );
      });

      test(
        'a profile or release build takes it all back out, byte for byte',
        () {
          final String added = dvApplePbxprojWithDevClient(
            original,
            enabled: true,
          );
          expect(dvApplePbxprojWithDevClient(added, enabled: false), original);
        },
      );
    });

    group('$platform: the development Info.plist', () {
      final String info = _example('$platform/Runner/Info.plist');

      test('declares the dartvel-dev scheme', () {
        final String plist = dvAppleDevelopmentInfoPlist(info);
        expect(plist, contains('<key>CFBundleURLTypes</key>'));
        expect(plist, contains('<string>dartvel-dev</string>'));
        // Everything the application's own Info.plist says, still said.
        for (final String key in RegExp(
          r'<key>([^<]+)</key>',
        ).allMatches(info).map((RegExpMatch m) => m.group(1)!)) {
          expect(plist, contains('<key>$key</key>'), reason: key);
        }
        expect(plist.trimRight(), endsWith('</plist>'));
      });

      test('the application\'s own Info.plist is not where it goes', () {
        expect(info, isNot(contains('dartvel-dev')));
      });
    });
  }

  test('a URL type the application already declares is kept beside it', () {
    const String withTypes = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>shopfront</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
''';
    final String plist = dvAppleDevelopmentInfoPlist(withTypes);
    expect('<key>CFBundleURLTypes</key>'.allMatches(plist).length, 1);
    expect(plist, contains('<string>shopfront</string>'));
    expect(plist, contains('<string>dartvel-dev</string>'));
    expect(dvAppleDevelopmentInfoPlist(plist), plist);
  });

  test('the tunnel records the manifest this build compiled in, and pins the '
      'pairing key', () {
    final String source = dvAppleDevTunnelSource(
      const DVDevClientManifest(
        target: 'ios',
        bindings: <String>['plugin:jni', 'dartvel_flutter@0.5.0'],
      ),
    );
    expect(
      source,
      contains(
        r'{\"target\":\"ios\",\"bindings\":'
        r'[\"dartvel_flutter@0.5.0\",\"plugin:jni\"]}',
      ),
    );
    // Only in a Debug configuration, whatever else compiles the file.
    expect(source.trimLeft(), startsWith('//'));
    expect(source, contains('#if DEBUG'));
    expect(source, contains('sec_protocol_options_set_verify_block'));
    expect(source, contains('dartvel_dev_client_vm_service'));
  });

  test('the Dart session calls the functions the build writes', () {
    // Two packages that cannot import each other name the same symbols; a
    // rename on one side is a development build that never pairs.
    final String session = File(
      '../dartvel_flutter/lib/src/devclient/dev_session.dart',
    ).readAsStringSync();
    final String source = dvAppleDevTunnelSource(
      const DVDevClientManifest(target: 'ios', bindings: <String>[]),
    );
    for (final String symbol in <String>[
      dvAppleDevClientVmServiceSymbol,
      dvAppleDevClientServerHostSymbol,
    ]) {
      expect(session, contains("'$symbol'"));
      expect(source, contains('const char *$symbol('));
    }
  });

  group('which builds get the dev client', () {
    for (final String platform in <String>['ios', 'macos']) {
      test('a $platform development build, built from the entrypoint', () {
        expect(
          dvDevelopmentBuildTarget(
            platform: platform,
            profile: DVBuildProfile.development,
            target: null,
          ),
          dvDevelopmentEntrypoint,
        );
      });
    }
  });
}
