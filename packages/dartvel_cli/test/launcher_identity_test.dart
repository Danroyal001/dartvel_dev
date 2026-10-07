import 'dart:io';

import 'package:dartvel_cli/src/build/desktop_entry.dart';
import 'package:dartvel_cli/src/build/launcher_identity.dart';
import 'package:dartvel_cli/src/build/pwa_icons.dart';
import 'package:test/test.dart';

/// What `flutter create` writes, which is what every new project starts with.
const String _templateManifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="my_app"
        android:name="\${applicationName}"
        android:icon="@mipmap/ic_launcher">
    </application>
</manifest>
''';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dv_launcher_');
    Directory('${root.path}/android/app/src/main').createSync(recursive: true);
    File('${root.path}/android/app/src/main/AndroidManifest.xml')
        .writeAsStringSync(_templateManifest);
    final DVRgbaImage art = DVRgbaImage(64, 64);
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        art.set(x, y, r: 200, g: 30, b: 40);
      }
    }
    Directory('${root.path}/assets').createSync();
    File('${root.path}/assets/logo.png').writeAsBytesSync(dvPngEncode(art));
  });

  tearDown(() => root.deleteSync(recursive: true));

  void pubspec(String dartvel) => File('${root.path}/pubspec.yaml')
      .writeAsStringSync('name: my_app\ndartvel:\n$dartvel');

  test('the launcher label is the configured short name, not the package name', () {
    pubspec('  pwa:\n    name: Eating Today Kitchen\n    shortName: EatingToday\n');
    dvWriteAndroidLauncher(root.path);
    final String manifest =
        File('${root.path}/android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:label="EatingToday"'));
    expect(manifest, isNot(contains('android:label="my_app"')));
  });

  test('the full name is the label when there is no short name', () {
    pubspec('  pwa:\n    name: Elena & Co\n');
    dvWriteAndroidLauncher(root.path);
    expect(
        File('${root.path}/android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('android:label="Elena &amp; Co"'));
  });

  test('the configured icon becomes every launcher density at its size', () {
    pubspec('  pwa:\n    name: NaijaLife\n    icon: assets/logo.png\n');
    dvWriteAndroidLauncher(root.path);
    const Map<String, int> sizes = <String, int>{
      'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192,
    };
    sizes.forEach((String density, int size) {
      final File icon = File(
          '${root.path}/android/app/src/main/res/mipmap-$density/ic_launcher.png');
      expect(icon.existsSync(), isTrue, reason: density);
      final DVRgbaImage decoded = dvPngDecode(icon.readAsBytesSync());
      expect(decoded.width, size, reason: density);
      expect(decoded.get(size ~/ 2, size ~/ 2).sublist(0, 3), <int>[200, 30, 40],
          reason: 'the artwork, not a placeholder');
    });
  });

  test('with nothing configured the project is left exactly as it was', () {
    pubspec('  backendPort: 3000\n');
    dvWriteAndroidLauncher(root.path);
    expect(
        File('${root.path}/android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        _templateManifest);
    expect(Directory('${root.path}/android/app/src/main/res').existsSync(), isFalse);
  });

  test('a project with no android folder is not an error', () {
    Directory('${root.path}/android').deleteSync(recursive: true);
    pubspec('  pwa:\n    name: Web Only\n');
    expect(() => dvWriteAndroidLauncher(root.path), returnsNormally);
  });

  group('every other flutter platform', () {
    void file(String rel, String text) => File('${root.path}/$rel')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
    String read(String rel) => File('${root.path}/$rel').readAsStringSync();
    const String appleIcons = '{"images":[{"size":"20x20","idiom":"iphone",'
        '"filename":"Icon-App-20x20@3x.png","scale":"3x"},'
        '{"size":"1024x1024","idiom":"ios-marketing",'
        '"filename":"Icon-App-1024x1024@1x.png","scale":"1x"},'
        '{"size":"16x16","idiom":"mac","scale":"2x"}]}';

    setUp(() => pubspec('  pwa:\n    name: Eating Today Kitchen\n'
        '    shortName: Eating Today\n    icon: assets/logo.png\n'
        '    backgroundColor: "#00ff00"\n'));

    test('iOS: the display name, and every icon the set lists, at its pixel size, opaque', () {
      file('ios/Runner/Info.plist', '<plist><dict>\n\t<key>CFBundleDisplayName</key>\n'
          '\t<string>My App</string>\n</dict></plist>');
      file('ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json', appleIcons);
      dvWriteLauncherIdentity(root.path, 'ios');
      expect(read('ios/Runner/Info.plist'), contains('<string>Eating Today</string>'));
      final String set = '${root.path}/ios/Runner/Assets.xcassets/AppIcon.appiconset';
      expect(dvPngDecode(File('$set/Icon-App-20x20@3x.png').readAsBytesSync()).width, 60);
      final DVRgbaImage marketing =
          dvPngDecode(File('$set/Icon-App-1024x1024@1x.png').readAsBytesSync());
      expect(marketing.width, 1024);
      expect(marketing.get(512, 512), <int>[200, 30, 40, 255]);
    });

    test('macOS: the menu bar name replaces \$(PRODUCT_NAME) and the display name is added', () {
      file('macos/Runner/Info.plist', '<plist>\n<dict>\n\t<key>CFBundleName</key>\n'
          '\t<string>\$(PRODUCT_NAME)</string>\n</dict>\n</plist>');
      dvWriteLauncherIdentity(root.path, 'macos');
      final String plist = read('macos/Runner/Info.plist');
      expect(plist, isNot(contains('PRODUCT_NAME')));
      expect('<string>Eating Today</string>'.allMatches(plist).length, 2);
    });

    test('Windows: the window title, the version resource and app_icon.ico', () {
      file('windows/runner/main.cpp', '  if (!window.Create(L"my_app", origin, size)) {');
      file('windows/runner/Runner.rc', '            VALUE "FileDescription", "my_app" "\\0"\n'
          '            VALUE "ProductName", "my_app" "\\0"\n'
          '            VALUE "OriginalFilename", "my_app.exe" "\\0"\n');
      dvWriteLauncherIdentity(root.path, 'windows');
      expect(read('windows/runner/main.cpp'), contains('window.Create(L"Eating Today", origin'));
      final String rc = read('windows/runner/Runner.rc');
      expect(rc, contains('"FileDescription", "Eating Today"'));
      expect(rc, contains('"ProductName", "Eating Today"'));
      expect(rc, contains('"my_app.exe"'), reason: 'the file name is the binary\'s');
      final List<int> ico = File('${root.path}/windows/runner/resources/app_icon.ico')
          .readAsBytesSync();
      expect(ico.sublist(0, 6), <int>[0, 0, 1, 0, dvWindowsIconSizes.length, 0]);
    });

    test('Windows: a name outside ASCII is a universal character name in the source', () {
      pubspec('  pwa:\n    name: Naija Lifé\n');
      file('windows/runner/main.cpp', 'window.Create(L"my_app", origin, size)');
      dvWriteLauncherIdentity(root.path, 'windows');
      expect(read('windows/runner/main.cpp'), contains(r'L"Naija Lif\u00e9"'));
    });

    test('Linux: both window titles', () {
      file('linux/runner/my_application.cc',
          '    gtk_header_bar_set_title(header_bar, "my_app");\n'
          '    gtk_window_set_title(window, "my_app");\n');
      dvWriteLauncherIdentity(root.path, 'linux');
      expect('"Eating Today"'.allMatches(read('linux/runner/my_application.cc')).length, 2);
    });

    test('Linux: the desktop entry takes the name and installs the icon', () {
      final Directory bundle = Directory('${root.path}/bundle')..createSync();
      final DVDesktopWrite result = dvWriteLinuxDesktopFiles(root.path, bundle.path);
      expect(result.written, contains('share/icons/hicolor/256x256/apps/my_app.png'));
      final String entry = File('${bundle.path}/my_app.desktop').readAsStringSync();
      expect(entry, contains('Name=Eating Today\n'));
      expect(entry, contains('Icon=my_app\n'));
    });
  });
}
