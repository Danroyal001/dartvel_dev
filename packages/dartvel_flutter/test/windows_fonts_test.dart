// The Windows font list, the part that can be checked off Windows: how a
// registry value becomes a path.
//
// HKLM's Fonts key holds bare file names ("arialbd.ttf"), in %WINDIR%\Fonts;
// HKCU's holds absolute paths for fonts a user installed for themselves. A
// rule that joined every value onto the system folder would point every
// per-user font at a file that does not exist, and the family would list and
// then fail to load. The enumeration itself (RegEnumValueW) has not been run
// on a Windows machine yet.
import 'package:dartvel_flutter/src/platform/windows/windows_fonts_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String system = r'C:\Windows\Fonts';

  test('a bare file name is in the fonts folder', () {
    expect(DVWindowsFonts.resolve('arialbd.ttf', system), r'C:\Windows\Fonts\arialbd.ttf');
  });

  test('a per-user font keeps its own absolute path', () {
    const String own = r'C:\Users\ada\AppData\Local\Microsoft\Windows\Fonts\Inter.ttf';
    expect(DVWindowsFonts.resolve(own, system), own);
    expect(DVWindowsFonts.resolve('d:/fonts/Inter.ttf', system), 'd:/fonts/Inter.ttf');
  });

  test('a network path is absolute too', () {
    expect(DVWindowsFonts.resolve(r'\\server\fonts\Inter.ttf', system), r'\\server\fonts\Inter.ttf');
  });

  test('off Windows the list is empty rather than a crash', () {
    // No advapi32 and no fonts folder: the honest answer is nothing.
    expect(DVWindowsFonts.fontFiles(null), isEmpty);
  });
}
