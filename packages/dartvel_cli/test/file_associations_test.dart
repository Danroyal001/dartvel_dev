import 'dart:io';

import 'package:dartvel_cli/src/build/desktop_entry.dart';
import 'package:dartvel_cli/src/build/file_associations.dart';
import 'package:dartvel_cli/src/build/ios_deep_links.dart';
import 'package:dartvel_cli/src/build/pwa_manifest.dart';
import 'package:dartvel_cli/src/config/dartvel_section.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const DVFileAssociation order = DVFileAssociation(
  mimeType: 'application/x-shop-order',
  extensions: <String>['order'],
  description: 'Shop order',
);
const DVFileAssociation pdf = DVFileAssociation(mimeType: 'application/pdf', role: DVFileAssociationRole.viewer);
const DVFileAssociation sheet = DVFileAssociation(mimeType: 'application/vnd.shop.sheet');

const String androidManifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="shop">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <data android:scheme="mine"/>
            </intent-filter>
        </activity>
        <activity android:name=".Other"/>
    </application>
</manifest>
''';

const String plist = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
\t<key>CFBundleName</key>
\t<string>shop</string>
\t<key>UIApplicationSceneManifest</key>
\t<dict>
\t\t<key>x</key>
\t\t<true/>
\t</dict>
</dict>
</plist>
''';

void main() {
  group('the declaration', () {
    test('dartvel.fileAssociations is read', () {
      final DVProjectFileAssociations declared = DVProjectFileAssociations.of(<String, Object?>{
        'fileAssociations': <Object?>[order.toPubspec()],
      });
      expect(declared.associations, <DVFileAssociation>[order]);
      expect(declared.warnings, isEmpty);
    });

    test('dartvel.desktop.fileAssociations still works and warns once', () {
      final DVProjectFileAssociations declared = DVProjectFileAssociations.of(<String, Object?>{
        'desktop': <String, Object?>{'fileAssociations': <Object?>[order.toPubspec(), pdf.toPubspec()]},
      });
      expect(declared.associations, <DVFileAssociation>[order, pdf]);
      expect(declared.warnings.single, contains('moved to dartvel.fileAssociations'));
    });

    test('a type in both places is registered once, the new key winning', () {
      final DVProjectFileAssociations declared = DVProjectFileAssociations.of(<String, Object?>{
        'fileAssociations': <Object?>[order.toPubspec()],
        'desktop': <String, Object?>{
          'fileAssociations': <Object?>[<String, Object?>{'mimeType': 'application/x-shop-order', 'extensions': <Object?>['old']}],
        },
      });
      expect(declared.associations.single.extensions, <String>['order']);
    });

    test('the desktop writers read the top-level key', () {
      final DVDesktopSettings settings = DVDesktopSettings.fromDartvel(<String, Object?>{
        'fileAssociations': <Object?>[order.toPubspec()],
      }, app: 'shop', appName: 'Shop');
      expect(dvDesktopEntry(settings), contains('MimeType=application/x-shop-order;'));
      expect(dvMimeInfo(settings), contains('<glob pattern="*.order"/>'));
    });
  });

  group('Android', () {
    final String written = dvAndroidFileAssociationsManifest(androidManifest, <DVFileAssociation>[order, pdf]);
    String receiver(String manifest) => manifest.substring(
        manifest.indexOf('dev.dartvel.jni.DartvelOpenActivity'), manifest.indexOf('</activity>', manifest.indexOf('DartvelOpenActivity')));

    test('open-with and share filters go on Dartvel\'s receiving activity, inside the application', () {
      final String activity = receiver(written);
      expect(activity, contains('<data android:mimeType="application/x-shop-order"/>'));
      expect(activity, contains('android.intent.action.SEND"'));
      expect(activity, contains('android.intent.action.SEND_MULTIPLE"'));
      expect(activity, contains('<data android:scheme="content"/>'));
      expect(activity, contains('android:exported="true"'), reason: 'other apps start it');
      expect(written.indexOf('DartvelOpenActivity'), lessThan(written.indexOf('</application>')));
    });

    test('MainActivity is not touched', () {
      final String main = written.substring(written.indexOf('.MainActivity'), written.indexOf('</activity>'));
      expect(main, androidManifest.substring(androidManifest.indexOf('.MainActivity'), androidManifest.indexOf('</activity>')));
    });

    test('a new type is also matched by extension; a known one is not', () {
      expect(written, contains(r'<data android:pathPattern=".*\\.order"/>'));
      expect(written, contains(r'<data android:pathPattern=".*\\..*\\.order"/>'));
      expect(RegExp('pathPattern').allMatches(written).length, 3, reason: 'pdf has no extensions');
    });

    test('the developer\'s own filters are kept, and a rebuild changes nothing', () {
      expect(written, contains('<data android:scheme="mine"/>'));
      expect(dvAndroidFileAssociationsManifest(written, <DVFileAssociation>[order, pdf]), written);
    });

    test('removing the declaration removes the block and nothing else', () {
      expect(dvAndroidFileAssociationsManifest(written, const <DVFileAssociation>[]), androidManifest);
    });

    test('the Java takes VIEW, SEND, SEND_MULTIPLE and shared text, and exposes take()', () {
      final String java = dvAndroidOpenActivitySource();
      expect(java, contains('public final class DartvelOpenActivity extends Activity'));
      expect(java, contains('public static String take()'));
      expect(java, contains('Intent.ACTION_SEND_MULTIPLE'));
      expect(java, contains('Intent.EXTRA_TEXT'));
      expect(java, contains('getLaunchIntentForPackage'));
      expect(java, contains(r'.replace("\\", "_")'), reason: 'a Java string holding one backslash');
      expect(dvAndroidOpenActivityPath, endsWith('dev/dartvel/jni/DartvelOpenActivity.java'));
    });
  });

  group('iOS app delegate', () {
    const String delegate = '''
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
''';
    test('with file types, a file URL is copied out of its scope and listed', () {
      final String written = dvIosAppDelegate(delegate, enabled: true, files: true);
      expect(written, contains('url.isFileURL'));
      expect(written, contains('startAccessingSecurityScopedResource'));
      expect(written, contains('forKey: "$dvIosOpenedFilesKey"'));
      expect(written, contains(r'"\(Int(Date().timeIntervalSince1970 * 1000))-\(url.lastPathComponent)"'));
      expect(dvIosAppDelegate(written, enabled: true, files: true), written);
    });

    test('without them, every URL is still a link', () {
      final String written = dvIosAppDelegate(delegate, enabled: true);
      expect(written, isNot(contains('isFileURL')));
      expect(written, contains('forKey: "$dvIosLaunchUrlKey"'));
      expect(dvIosAppDelegate(written, enabled: false), delegate);
    });
  });

  group('Apple', () {
    test('iOS: document types, an exported type for a new one, open in place', () {
      final String written = dvAppleFileAssociationsPlist(plist, 'shop', <DVFileAssociation>[order, pdf, sheet], ios: true);
      expect(written, contains('<key>CFBundleDocumentTypes</key>'));
      expect(written, contains('<string>dev.dartvel.shop.application-x-shop-order</string>'));
      expect(written, contains('<string>com.adobe.pdf</string>'), reason: 'a type Apple knows is named by its own UTI');
      expect(written, contains('<string>Viewer</string>'));
      expect(written, contains('<string>Editor</string>'));
      final String exported = written.substring(written.indexOf('UTExportedTypeDeclarations'), written.indexOf('UTImportedTypeDeclarations'));
      expect(exported, contains('<string>order</string>'));
      expect(exported, isNot(contains('sheet')));
      final String imported = written.substring(written.indexOf('UTImportedTypeDeclarations'));
      expect(imported, contains('application/vnd.shop.sheet'));
      expect(imported, isNot(contains('com.adobe.pdf')), reason: 'Apple already declares PDF');
      expect(written, contains('<key>LSSupportsOpeningDocumentsInPlace</key>\n\t<true/>'));
    });

    test('the block goes in the top dictionary, not a nested one', () {
      final String written = dvAppleFileAssociationsPlist(plist, 'shop', <DVFileAssociation>[order], ios: true);
      expect(written.indexOf('dartvel.fileAssociations: begin'), greaterThan(written.indexOf('\t</dict>')));
      expect(written.trimRight(), endsWith('</dict>\n</plist>'));
    });

    test('macOS has no open-in-place key', () {
      expect(dvAppleFileAssociationsPlist(plist, 'shop', <DVFileAssociation>[order], ios: false),
          isNot(contains('LSSupportsOpeningDocumentsInPlace')));
    });

    test('idempotent, removable, and never beside document types the developer wrote', () {
      final String written = dvAppleFileAssociationsPlist(plist, 'shop', <DVFileAssociation>[order], ios: true);
      expect(dvAppleFileAssociationsPlist(written, 'shop', <DVFileAssociation>[order], ios: true), written);
      expect(dvAppleFileAssociationsPlist(written, 'shop', const <DVFileAssociation>[], ios: true), plist);
      final String own = plist.replaceFirst('</dict>\n</plist>', '\t<key>CFBundleDocumentTypes</key>\n\t<array/>\n</dict>\n</plist>');
      expect(dvAppleFileAssociationsPlist(own, 'shop', <DVFileAssociation>[order], ios: true), own);
      expect(dvAppleHasOwnDocumentTypes(own), isTrue);
    });

    test('macOS desktop entries carry URL types and the shared document types', () {
      final DVDesktopSettings settings = DVDesktopSettings.fromDartvel(<String, Object?>{
        'fileAssociations': <Object?>[order.toPubspec()],
        'desktop': <String, Object?>{'schemes': <Object?>['shop']},
      }, app: 'shop', appName: 'Shop');
      final String written = dvMacosInfoPlist(plist, settings);
      expect(written, contains('<key>CFBundleURLSchemes</key>'));
      expect(written, contains('UTExportedTypeDeclarations'));
      expect(dvMacosInfoPlist(written, settings), written);
    });
  });

  group('Web', () {
    test('file_handlers accept each type with its extensions', () {
      final Map<String, Object?> manifest = dvPwaManifest(
        name: 'Shop',
        fileHandlers: dvWebFileHandlers(<DVFileAssociation>[order, pdf]),
      );
      expect(manifest['file_handlers'], <Object?>[
        <String, Object?>{
          'action': './',
          'accept': <String, Object?>{
            'application/x-shop-order': <String>['.order'],
            'application/pdf': <String>[],
          },
        },
      ]);
    });

    test('no declaration, no file_handlers key', () {
      expect(dvPwaManifest(name: 'Shop').containsKey('file_handlers'), isFalse);
    });
  });

  group('Windows', () {
    test('an editor gets Open and Edit; a viewer only Open', () {
      final DVDesktopSettings settings = DVDesktopSettings.fromDartvel(<String, Object?>{
        'fileAssociations': <Object?>[
          order.toPubspec(),
          const DVFileAssociation(mimeType: 'text/x-log', extensions: <String>['log'], role: DVFileAssociationRole.viewer).toPubspec(),
        ],
      }, app: 'shop', appName: 'Shop');
      final String script = dvWindowsAssociationsScript(settings, executable: r'C:\shop\shop.exe')!;
      expect(script, contains(r'[HKEY_CURRENT_USER\Software\Classes\shop.order\shell\edit\command]'));
      expect(script, isNot(contains(r'shop.log\shell\edit')));
      expect(script, contains(r'[HKEY_CURRENT_USER\Software\Classes\shop.log\shell\open\command]'));
    });
  });

  group('Tizen', () {
    const String tizen = '''
<manifest xmlns="http://tizen.org/ns/packages" package="dev.shop" version="1.0.0">
    <ui-application appid="dev.shop" exec="runner" type="capp">
        <label>shop</label>
    </ui-application>
</manifest>
''';
    test('a view app control per type, inside the application, removable', () {
      final String written = dvTizenFileAssociationsManifest(tizen, <DVFileAssociation>[order]);
      expect(written, contains('<operation name="http://tizen.org/appcontrol/operation/view"/>'));
      expect(written, contains('<mime name="application/x-shop-order"/>'));
      expect(written.indexOf('<app-control>'), lessThan(written.indexOf('</ui-application>')));
      expect(dvTizenFileAssociationsManifest(written, <DVFileAssociation>[order]), written);
      expect(dvTizenFileAssociationsManifest(written, const <DVFileAssociation>[]), tizen);
    });
  });

  group('the Dart config file', () {
    late Directory project;
    setUpAll(() {
      project = Directory.systemTemp.createTempSync('dv_dart_config_');
      final String core = p.normalize(p.absolute('..', 'dartvel_core'));
      File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: shop
environment:
  sdk: ^3.13.0
dependencies:
  dartvel_core:
    path: $core
dartvel: dartvel_config.dart
''');
      File(p.join(project.path, 'dartvel_config.dart')).writeAsStringSync('''
import 'package:dartvel_core/config.dart';

class ShopConfig extends DartvelConfig {
  const ShopConfig();

  @override
  List<DVFileAssociation> get fileAssociations => const <DVFileAssociation>[
        DVFileAssociation(mimeType: 'application/x-shop-order', extensions: <String>['order'], description: 'Shop order'),
        DVFileAssociation(mimeType: 'application/pdf', role: DVFileAssociationRole.viewer),
      ];
}
''');
      final ProcessResult got = Process.runSync('dart', <String>['pub', 'get', '--offline'], workingDirectory: project.path);
      if (got.exitCode != 0) fail('pub get: ${got.stderr}');
    });
    tearDownAll(() => project.deleteSync(recursive: true));

    test('reads as exactly the object the YAML spelling would be', () {
      final DVDartvelSection section = dvDartvelSection(project.path);
      expect(section.problems, isEmpty);
      expect(section.fromDartConfig, 'dartvel_config.dart');
      expect(section.values, <String, Object?>{
        'fileAssociations': <Object?>[order.toPubspec(), pdf.toPubspec()],
      });
      expect(DVProjectFileAssociations.of(section.values).associations, <DVFileAssociation>[order, pdf]);
    });

    test('a second read comes from the cache until the file changes', () {
      final File cache = File(p.join(project.path, '.dart_tool', 'dartvel', 'dart_config.json'));
      expect(cache.existsSync(), isTrue);
      cache.writeAsStringSync(cache.readAsStringSync().replaceAll('Shop order', 'From cache'));
      expect('${dvDartvelSection(project.path).values}', contains('From cache'));
      final File config = File(p.join(project.path, 'dartvel_config.dart'));
      config.writeAsStringSync('${config.readAsStringSync()}\n// changed\n');
      expect('${dvDartvelSection(project.path).values}', contains('Shop order'));
    });

    test('a file without a config class says so', () {
      File(p.join(project.path, 'broken.dart')).writeAsStringSync('void main() {}');
      expect(dvEvaluateDartConfig(project.path, 'broken.dart').problems.single, contains('extending DartvelConfig'));
    });
  });
}
