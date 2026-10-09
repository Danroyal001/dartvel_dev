// The Swift `dartvel build ios` compiles in for the iOS DV.Platform bindings,
// and the Info.plist keys without which iOS terminates the app that asks.
//
// Nothing here compiles Swift -- that needs Xcode, and the macOS job in
// runtime-verification.yml does it. What is checked here is what goes wrong
// silently: an operation the Dart sends that the Swift has no case for, a
// symbol spelled differently on the two sides, a shim written into the folder
// and left out of the target, and a permission declared in the pubspec that
// never reaches Info.plist.
import 'dart:io';

import 'package:dartvel_cli/src/build/apple_widget_reload.dart';
import 'package:dartvel_cli/src/build/ios_platform_shim.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _examplePbxproj() {
  // The real Runner project, so the splice is tested against the file shape
  // Flutter actually generates rather than a hand-written approximation.
  Directory dir = Directory.current;
  while (!File(p.join(dir.path, 'examples', 'dartvel_example', 'ios', 'Runner.xcodeproj', 'project.pbxproj'))
      .existsSync()) {
    dir = dir.parent;
  }
  return File(p.join(dir.path, 'examples', 'dartvel_example', 'ios', 'Runner.xcodeproj', 'project.pbxproj'))
      .readAsStringSync();
}

void main() {
  group('the Swift', () {
    final String swift = dvIosPlatformShimSource();

    test('has a case for every operation the Dart sends', () {
      expect(dvIosShimSourceOperations(swift), containsAll(dvIosShimOperations));
    });

    test('exports the four symbols the Dart looks up, spelled the same', () {
      for (final String symbol in <String>[
        dvIosShimVersionSymbol,
        dvIosShimCompletionSymbol,
        dvIosShimCallSymbol,
        dvIosShimDiskFreeSymbol,
      ]) {
        expect(swift, contains('@_cdecl("$symbol")'));
      }
    });

    test('answers the protocol version the runtime expects', () {
      expect(swift, contains('return $dvIosShimVersion\n'));
    });

    test('leaves no placeholder unfilled', () {
      // $VERSION is a prefix of $VERSION_SYMBOL; replaced in the wrong order
      // the symbol becomes "1_SYMBOL" and nothing finds it.
      expect(RegExp(r'\$[A-Z][A-Z_]+').hasMatch(swift), isFalse,
          reason: RegExp(r'\$[A-Z][A-Z_]+').firstMatch(swift)?.group(0));
    });

    test('reports connectivity under the reserved id', () {
      expect(swift, contains('dartvelAnswer($dvIosShimNetworkEventId, ['));
    });

    test('uses no platform channel', () {
      for (final String channel in <String>['FlutterMethodChannel', 'FlutterEventChannel', 'FlutterBasicMessageChannel']) {
        expect(swift, isNot(contains(channel)));
      }
    });

    test('checks the usage key before every protected request it makes itself', () {
      // Each of these is a resource iOS terminates the app over.
      for (final String key in <String>[
        'NSCameraUsageDescription',
        'NSContactsUsageDescription',
        'NSLocationWhenInUseUsageDescription',
        'NSBluetoothAlwaysUsageDescription',
        'NSFaceIDUsageDescription',
      ]) {
        expect(swift, contains('declared(["$key"])'), reason: key);
      }
    });
  });

  group('the Xcode wiring', () {
    final String before = _examplePbxproj();

    test('compiles the file into the application target', () {
      final String after = dvIosPbxprojWithPlatformShim(before);
      expect(after, contains('$dvIosPlatformShimFileName in Sources'));
      expect(after, contains('path = $dvIosPlatformShimFileName;'));
      // A build file (naming its file reference), the file reference, and
      // one entry in each of the group and the Sources phase.
      expect(RegExp(dvIosPlatformShimIdPrefix).allMatches(after).length, 5);
    });

    test('is idempotent, so a second build leaves no diff', () {
      final String once = dvIosPbxprojWithPlatformShim(before);
      expect(dvIosPbxprojWithPlatformShim(once), once);
    });

    test('sits beside the widget reload shim without disturbing it', () {
      final String both = dvIosPbxprojWithPlatformShim(
          dvApplePbxprojWithWidgetReload(before, hasWidgets: true, platform: 'ios'));
      expect(both, contains('$dvAppleWidgetReloadFileName in Sources'));
      expect(both, contains('$dvIosPlatformShimFileName in Sources'));
      // Taking the widgets away leaves the platform shim in place.
      final String noWidgets = dvApplePbxprojWithWidgetReload(both, hasWidgets: false, platform: 'ios');
      expect(noWidgets, isNot(contains(dvAppleWidgetReloadFileName)));
      expect(noWidgets, contains('$dvIosPlatformShimFileName in Sources'));
    });
  });

  group('dartvel.ios.permissions', () {
    test('a list takes a default sentence for each name', () {
      final Map<String, String> asked = dvIosRequestedPermissions(<String, Object?>{
        'ios': <String, Object?>{'permissions': <Object?>['camera', 'location']},
      });
      expect(asked.keys, <String>['camera', 'location']);
      expect(asked['camera'], isNotEmpty);
    });

    test('a map gives the project its own sentence', () {
      final Map<String, String> asked = dvIosRequestedPermissions(<String, Object?>{
        'ios': <String, Object?>{'permissions': <String, Object?>{'camera': 'To scan receipts.'}},
      });
      expect(asked, <String, String>{'camera': 'To scan receipts.'});
    });

    test('nothing declared is nothing written', () {
      expect(dvIosRequestedPermissions(null), isEmpty);
      expect(dvIosUsageDescriptionEntries(const <String, String>{}), isEmpty);
    });

    test('an unknown name is reported, not silently dropped', () {
      expect(dvIosUnknownPermissions(<String>['camera', 'camrea']), <String>['camrea']);
    });

    test('each name becomes the Info.plist key iOS asks for, escaped', () {
      expect(
          dvIosUsageDescriptionEntries(<String, String>{'camera': 'Receipts & <bills>', 'notifications': 'x'}),
          <String, String>{'NSCameraUsageDescription': '<string>Receipts &amp; &lt;bills&gt;</string>'});
    });

    const String plist = '<?xml version="1.0"?>\n<plist version="1.0">\n<dict>\n'
        '\t<key>CFBundleName</key>\n\t<string>x</string>\n</dict>\n</plist>\n';

    test('the block is written into the top dictionary and replaced on rebuild', () {
      final String once = dvWithIosPermissionsBlock(
          plist, <String, String>{'NSCameraUsageDescription': '<string>a</string>'});
      expect(once, contains('<key>NSCameraUsageDescription</key>'));
      final String twice = dvWithIosPermissionsBlock(
          once, <String, String>{'NSCameraUsageDescription': '<string>b</string>'});
      expect(RegExp('NSCameraUsageDescription').allMatches(twice).length, 1);
      expect(twice, contains('<string>b</string>'));
      // And taken out entirely when the pubspec stops asking.
      expect(dvWithIosPermissionsBlock(twice, const <String, String>{}), plist);
    });

    test('a key the developer wrote is theirs and is kept', () {
      final String mine = plist.replaceFirst(
          '</dict>', '\t<key>NSCameraUsageDescription</key>\n\t<string>mine</string>\n</dict>');
      final List<String> skipped = <String>[];
      final String after = dvWithIosPermissionsBlock(
          mine, <String, String>{'NSCameraUsageDescription': '<string>ours</string>'},
          skipped: skipped);
      expect(after, mine);
      expect(skipped, <String>['NSCameraUsageDescription']);
    });
  });
}
