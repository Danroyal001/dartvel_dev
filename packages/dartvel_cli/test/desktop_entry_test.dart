// File associations and app links on Linux: the desktop entry and the MIME
// database entry a build writes next to the binary.
//
// A Linux desktop learns what an application opens from a .desktop file's
// MimeType line and, for a type it has never heard of, from a shared-mime-info
// XML naming the extension. dartvel build linux writes both from the
// `dartvel.desktop` section of pubspec.yaml, so an association is declared
// once, next to the app, and never hand-edited into a system directory.
import 'dart:io';

import 'package:dartvel_cli/src/build/desktop_entry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

DVDesktopSettings settings([Map<String, Object?> desktop = const <String, Object?>{}]) =>
    DVDesktopSettings.parse(desktop, app: 'shop_app', appName: 'Shop');

void main() {
  group('parsing dartvel.desktop', () {
    test('defaults come from the app', () {
      final DVDesktopSettings s = settings();
      expect(s.name, 'Shop');
      expect(s.exec, 'shop_app');
      expect(s.associations, isEmpty);
      expect(s.schemes, isEmpty);
      expect(s.problems, isEmpty);
    });

    test('an association names a MIME type, extensions and a description', () {
      final DVDesktopSettings s = settings(<String, Object?>{
        'name': 'Shop',
        'comment': 'Orders and stock',
        'icon': 'shop',
        'categories': <String>['Office'],
        'fileAssociations': <Object?>[
          <String, Object?>{'mimeType': 'application/x-shop-order', 'extensions': <String>['order'], 'description': 'Shop order'},
          <String, Object?>{'mimeType': 'application/pdf'},
        ],
        'schemes': <String>['shop', 'dartvel'],
      });
      expect(s.problems, isEmpty);
      expect(s.associations, hasLength(2));
      expect(s.associations.first.extensions, <String>['order']);
      expect(s.associations.last.extensions, isEmpty, reason: 'a known type needs no extension of its own');
      expect(s.schemes, <String>['shop', 'dartvel']);
    });

    test('an association with no MIME type is a problem, not a guess', () {
      final DVDesktopSettings s = settings(<String, Object?>{
        'fileAssociations': <Object?>[<String, Object?>{'extensions': <String>['order']}],
      });
      expect(s.problems.single, contains('mimeType'));
    });

    test('a scheme is a scheme, not a URL', () {
      final DVDesktopSettings s = settings(<String, Object?>{'schemes': <String>['shop://', 'ok']});
      expect(s.problems.single, contains('shop://'));
      expect(s.schemes, <String>['ok']);
    });
  });

  group('the desktop entry', () {
    test('carries the app, opens files and links, and lists every type', () {
      final String entry = dvDesktopEntry(settings(<String, Object?>{
        'comment': 'Orders and stock',
        'icon': 'shop',
        'categories': <String>['Office', 'Finance'],
        'fileAssociations': <Object?>[
          <String, Object?>{'mimeType': 'application/x-shop-order', 'extensions': <String>['order']},
          <String, Object?>{'mimeType': 'application/pdf'},
        ],
        'schemes': <String>['shop'],
      }));
      expect(entry, startsWith('[Desktop Entry]\n'));
      expect(entry, contains('Type=Application\n'));
      expect(entry, contains('Name=Shop\n'));
      expect(entry, contains('Comment=Orders and stock\n'));
      expect(entry, contains('Icon=shop\n'));
      expect(entry, contains('Exec=shop_app %U\n'), reason: '%U is how files and links reach main');
      expect(entry, contains('Categories=Office;Finance;\n'));
      expect(entry, contains('MimeType=application/x-shop-order;application/pdf;x-scheme-handler/shop;\n'));
    });

    test('with nothing to open, Exec still takes %U and MimeType is absent', () {
      final String entry = dvDesktopEntry(settings());
      expect(entry, contains('Exec=shop_app %U\n'));
      expect(entry, isNot(contains('MimeType=')));
    });

    test('a value with a newline cannot smuggle a second key', () {
      final String entry = dvDesktopEntry(settings(<String, Object?>{'comment': 'Orders\nExec=rm -rf /'}));
      expect(entry, isNot(contains('\nExec=rm')));
    });
  });

  group('the MIME info', () {
    test('names each new type by its extensions; known types are left alone', () {
      final String? xml = dvMimeInfo(settings(<String, Object?>{
        'fileAssociations': <Object?>[
          <String, Object?>{'mimeType': 'application/x-shop-order', 'extensions': <String>['order', 'shoporder'], 'description': 'Shop order'},
          <String, Object?>{'mimeType': 'application/pdf'},
        ],
      }));
      expect(xml, isNotNull);
      expect(xml, contains('<mime-type type="application/x-shop-order">'));
      expect(xml, contains('<comment>Shop order</comment>'));
      expect(xml, contains('<glob pattern="*.order"/>'));
      expect(xml, contains('<glob pattern="*.shoporder"/>'));
      expect(xml, isNot(contains('application/pdf')));
    });

    test('nothing new means no file', () {
      expect(dvMimeInfo(settings(<String, Object?>{
        'fileAssociations': <Object?>[<String, Object?>{'mimeType': 'application/pdf'}],
      })), isNull);
    });

    test('text is escaped', () {
      final String? xml = dvMimeInfo(settings(<String, Object?>{
        'fileAssociations': <Object?>[
          <String, Object?>{'mimeType': 'application/x-a', 'extensions': <String>['a'], 'description': 'A & <B>'},
        ],
      }));
      expect(xml, contains('<comment>A &amp; &lt;B&gt;</comment>'));
    });
  });

  group('the files a build writes', () {
    test('are the entry and, when needed, the MIME info, under the bundle', () {
      final Map<String, String> files = dvDesktopFiles(settings(<String, Object?>{
        'fileAssociations': <Object?>[
          <String, Object?>{'mimeType': 'application/x-shop-order', 'extensions': <String>['order']},
        ],
      }));
      expect(files.keys, <String>['shop_app.desktop', 'share/mime/packages/shop_app.xml']);
    });

    test('and only the entry when nothing is new', () {
      expect(dvDesktopFiles(settings()).keys, <String>['shop_app.desktop']);
    });
  });

  group('writing under the bundle', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('dv_desktop_'));
    tearDown(() => root.deleteSync(recursive: true));

    test('reads dartvel.desktop from the pubspec and writes the files', () {
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shop_app
dartvel:
  desktop:
    name: Shop
    fileAssociations:
      - mimeType: application/x-shop-order
        extensions: [order]
''');
      final Directory bundle = Directory(p.join(root.path, 'build', 'linux', 'x64', 'release', 'bundle'))..createSync(recursive: true);
      final DVDesktopWrite result = dvWriteLinuxDesktopFiles(root.path, bundle.path);

      expect(result.written, <String>['shop_app.desktop', 'share/mime/packages/shop_app.xml']);
      expect(result.problems, isEmpty);
      expect(File(p.join(bundle.path, 'shop_app.desktop')).readAsStringSync(), contains('MimeType=application/x-shop-order;'));
      expect(File(p.join(bundle.path, 'share', 'mime', 'packages', 'shop_app.xml')).existsSync(), isTrue);
    });

    test('with no desktop section, only the entry, from the app name', () {
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: shop_app\n');
      final Directory bundle = Directory(p.join(root.path, 'bundle'))..createSync(recursive: true);
      final DVDesktopWrite result = dvWriteLinuxDesktopFiles(root.path, bundle.path);
      expect(result.written, <String>['shop_app.desktop']);
      expect(File(p.join(bundle.path, 'shop_app.desktop')).readAsStringSync(), contains('Name=shop_app\n'));
    });

    test('problems are reported, and the entry is still written without the bad parts', () {
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shop_app
dartvel:
  desktop:
    schemes: ['shop://']
''');
      final Directory bundle = Directory(p.join(root.path, 'bundle'))..createSync(recursive: true);
      final DVDesktopWrite result = dvWriteLinuxDesktopFiles(root.path, bundle.path);
      expect(result.problems.single, contains('shop://'));
      expect(File(p.join(bundle.path, 'shop_app.desktop')).readAsStringSync(), isNot(contains('x-scheme-handler')));
    });
  });
  desktopOnOtherPlatforms();
}

// The same declaration on the other desktops. macOS reads document and URL
// types from the bundle's Info.plist, so the build writes them there before
// Xcode packages it; Windows reads them from the registry, which only an
// installer or the person may touch, so the build writes the script an
// installer runs, beside the binary.
const String _plist = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>CFBundleName</key>
\t<string>\$(PRODUCT_NAME)</string>
\t<key>NSPrincipalClass</key>
\t<string>NSApplication</string>
</dict>
</plist>
''';

void desktopOnOtherPlatforms() {
  group('macOS Info.plist', () {
    final DVDesktopSettings declared = settings(<String, Object?>{
      'fileAssociations': <Object?>[
        <String, Object?>{'mimeType': 'application/x-shop-order', 'extensions': <String>['order'], 'description': 'Shop order'},
      ],
      'schemes': <String>['shop'],
    });

    test('gains the URL types and document types, keeping what it had', () {
      final String out = dvMacosInfoPlist(_plist, declared);
      expect(out, contains('<key>CFBundleURLTypes</key>'));
      expect(out, contains('<string>shop</string>'));
      expect(out, contains('<key>CFBundleDocumentTypes</key>'));
      expect(out, contains('<string>order</string>'));
      expect(out, contains('<string>application/x-shop-order</string>'));
      expect(out, contains('<string>Shop order</string>'));
      expect(out, contains('<key>NSPrincipalClass</key>'), reason: 'the rest of the plist is kept');
      expect(out.trim(), endsWith('</plist>'));
    });

    test('is written once: a second run replaces the block rather than adding another', () {
      final String once = dvMacosInfoPlist(_plist, declared);
      final String twice = dvMacosInfoPlist(once, declared);
      expect(twice, once);
      expect('<key>CFBundleURLTypes</key>'.allMatches(twice), hasLength(1));
    });

    test('with nothing to open is left alone', () {
      expect(dvMacosInfoPlist(_plist, settings()), _plist);
    });

    test('text is escaped', () {
      final String out = dvMacosInfoPlist(_plist, settings(<String, Object?>{
        'fileAssociations': <Object?>[
          <String, Object?>{'mimeType': 'text/x-a', 'extensions': <String>['a'], 'description': 'Rock & <roll>'},
        ],
      }));
      expect(out, contains('Rock &amp; &lt;roll&gt;'));
      expect(out, isNot(contains('<roll>')));
    });
  });

  group('Windows registry script', () {
    test('registers each extension under a ProgId that opens the binary, and each scheme', () {
      final String reg = dvWindowsAssociationsScript(settings(<String, Object?>{
        'fileAssociations': <Object?>[
          <String, Object?>{'mimeType': 'application/x-shop-order', 'extensions': <String>['order'], 'description': 'Shop order'},
        ],
        'schemes': <String>['shop'],
      }), executable: r'C:\Apps\shop_app.exe')!;
      expect(reg, startsWith('Windows Registry Editor Version 5.00'));
      expect(reg, contains(r'[HKEY_CURRENT_USER\Software\Classes\.order]'));
      expect(reg, contains('@="shop_app.order"'));
      expect(reg, contains(r'[HKEY_CURRENT_USER\Software\Classes\shop_app.order\shell\open\command]'));
      expect(reg, contains(r'@="\"C:\\Apps\\shop_app.exe\" \"%1\""'));
      expect(reg, contains('"Content Type"="application/x-shop-order"'));
      expect(reg, contains(r'[HKEY_CURRENT_USER\Software\Classes\shop]'));
      expect(reg, contains('"URL Protocol"=""'));
      expect(reg, contains(r'[HKEY_CURRENT_USER\Software\Classes\shop\shell\open\command]'));
    });

    test('with nothing to open there is no script', () {
      expect(dvWindowsAssociationsScript(settings(), executable: r'C:\a.exe'), isNull);
    });
  });

  group('writing for macOS and Windows', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('dv_desktop_other_'));
    tearDown(() => root.deleteSync(recursive: true));

    const String pubspec = '''
name: shop_app
dartvel:
  desktop:
    schemes: [shop]
    fileAssociations:
      - mimeType: application/x-shop-order
        extensions: [order]
''';

    test('the Info.plist under macos/Runner is rewritten in place', () {
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
      final File plist = File(p.join(root.path, 'macos', 'Runner', 'Info.plist'))..createSync(recursive: true);
      plist.writeAsStringSync(_plist);

      final DVDesktopWrite result = dvWriteMacosDesktopEntries(root.path);

      expect(result.written, <String>['macos/Runner/Info.plist']);
      expect(plist.readAsStringSync(), contains('<string>shop</string>'));
    });

    test('without a macOS runner nothing is written, and that is said', () {
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
      final DVDesktopWrite result = dvWriteMacosDesktopEntries(root.path);
      expect(result.written, isEmpty);
      expect(result.problems.single, contains('macos/Runner/Info.plist'));
    });

    test('the registry script is written beside the Windows binary', () {
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
      final Directory bundle = Directory(p.join(root.path, 'out'))..createSync();

      final DVDesktopWrite result = dvWriteWindowsDesktopFiles(root.path, bundle.path);

      expect(result.written, <String>['shop_app-associations.reg']);
      final String reg = File(p.join(bundle.path, 'shop_app-associations.reg')).readAsStringSync();
      expect(reg, contains('shop_app.exe'));
      expect(reg, contains(r'[HKEY_CURRENT_USER\Software\Classes\shop]'));
    });
  });
}
