import 'dart:io';

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
}
