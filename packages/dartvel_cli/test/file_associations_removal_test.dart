import 'package:dartvel_cli/src/build/desktop_entry.dart';
import 'package:test/test.dart';

void main() {
  test('removing all file types removes generated macOS document metadata', () {
    const source = '<plist><dict><key>CFBundleName</key><string>app</string></dict></plist>';
    const declared = DVDesktopSettings(app: 'app', name: 'app', exec: 'app',
        associations: [DVFileAssociation(mimeType: 'application/x-order', extensions: ['order'])]);
    const removed = DVDesktopSettings(app: 'app', name: 'app', exec: 'app');
    final withTypes = dvMacosInfoPlist(source, declared);
    expect(withTypes, contains('CFBundleDocumentTypes'));
    expect(dvMacosInfoPlist(withTypes, removed).trim(), source);
  });
}
