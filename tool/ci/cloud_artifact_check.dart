/// Checks what `dartvel build <target> --cloud` downloaded is the thing a
/// build of that target makes, rather than that a directory exists.
///
///   dart tool/ci/cloud_artifact_check.dart android examples/basic_app/build/cloud/android
///   dart tool/ci/cloud_artifact_check.dart ios examples/basic_app/build/cloud/ios
///
/// An APK is a zip whose central directory names AndroidManifest.xml and
/// classes.dex. An iOS build is a Runner.app with an Info.plist and a Mach-O
/// executable. An empty file or an error page saved under the right name
/// passes an existence check and fails these. dart: imports only, so it runs
/// with `dart` and no pub get.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: cloud_artifact_check.dart <android|ios> <dir>');
    exit(64);
  }
  final Directory dir = Directory(args[1]);
  if (!dir.existsSync()) _fail('${dir.path} does not exist');
  final List<File> files = dir.listSync(recursive: true).whereType<File>().toList();
  switch (args[0]) {
    case 'android':
      final List<File> apks = files.where((File f) => f.path.endsWith('.apk')).toList();
      if (apks.isEmpty) _fail('no .apk under ${dir.path}');
      for (final File apk in apks) {
        final Set<String> names = _zipNames(apk);
        for (final String wanted in <String>['AndroidManifest.xml', 'classes.dex']) {
          if (!names.contains(wanted)) _fail('${apk.path} has no $wanted');
        }
        if (!names.any((String n) => n.endsWith('libapp.so') || n.endsWith('kernel_blob.bin'))) {
          _fail('${apk.path} carries no compiled Dart (libapp.so or kernel_blob.bin)');
        }
        stdout.writeln('ok: ${apk.path} (${apk.lengthSync()} bytes, ${names.length} entries)');
      }
    case 'ios':
      final File? plist = files
          .where((File f) => f.path.endsWith('Runner.app/Info.plist'))
          .firstOrNull;
      if (plist == null) _fail('no Runner.app/Info.plist under ${dir.path}');
      final File binary = File('${plist.parent.path}/Runner');
      if (!binary.existsSync()) _fail('Runner.app has no Runner executable');
      final Uint8List head = binary.openSync().readSync(4);
      final int magic = head.length < 4 ? 0 : ByteData.sublistView(head).getUint32(0, Endian.little);
      if (magic != 0xfeedfacf && magic != 0xcafebabe && magic != 0xbebafeca) {
        _fail('${binary.path} is not a Mach-O executable (magic ${magic.toRadixString(16)})');
      }
      stdout.writeln('ok: ${binary.path} (${binary.lengthSync()} bytes, Mach-O)');
    default:
      _fail('no check for ${args[0]}');
  }
}

Set<String> _zipNames(File file) {
  final Uint8List b = file.readAsBytesSync();
  int u16(int o) => b[o] | (b[o + 1] << 8);
  int u32(int o) => u16(o) | (u16(o + 2) << 16);
  for (int i = b.length - 22; i >= 0 && i >= b.length - 65557; i--) {
    if (u32(i) != 0x06054b50) continue;
    final Set<String> names = <String>{};
    int at = u32(i + 16);
    for (int n = 0; n < u16(i + 10); n++) {
      if (at + 46 > b.length || u32(at) != 0x02014b50) break;
      final int length = u16(at + 28);
      names.add(utf8.decode(b.sublist(at + 46, at + 46 + length), allowMalformed: true));
      at += 46 + length + u16(at + 30) + u16(at + 32);
    }
    return names;
  }
  _fail('${file.path} is not a zip');
}

Never _fail(String message) {
  stderr.writeln('cloud-artifact: $message');
  exit(1);
}
