/// Checks that a directory holds what a build of a target makes, rather than
/// that it exists: what `dartvel build <target> --cloud` downloaded, for one.
///
///   dart tool/ci/cloud_artifact_check.dart android examples/basic_app/build/cloud/android
///   dart tool/ci/cloud_artifact_check.dart ios examples/basic_app/build/cloud/ios
///   dart tool/ci/cloud_artifact_check.dart aab examples/basic_app/build/app/outputs/bundle/release
///   dart tool/ci/cloud_artifact_check.dart ipa-archive examples/basic_app/build/ios/archive
///
/// And for the other cloud targets: fireos, chrome-extension, firefox-extension,
/// vscode, tvos (a simulator app whose Info.plist names appletv), linux-cli and
/// sony-elinux (ELF bundles with no GTK runner in them) and tizen (a signed
/// TPK carrying the engine and compiled Dart).
///
/// An App Bundle is a zip laid out by module: base/manifest/AndroidManifest.xml,
/// base/dex/classes.dex, compiled Dart under base/lib, and BundleConfig.pb,
/// which is what makes it a bundle Play accepts and not an APK renamed. An
/// unsigned IPA build stops at Runner.xcarchive, whose app is a Mach-O.
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
    stderr.writeln('usage: cloud_artifact_check.dart <target|aab|ipa-archive> <dir>');
    exit(64);
  }
  final Directory dir = Directory(args[1]);
  if (!dir.existsSync()) _fail('${dir.path} does not exist');
  final List<File> files = dir.listSync(recursive: true).whereType<File>().toList();
  switch (args[0]) {
    case 'android' || 'fireos':
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
    case 'aab':
      final List<File> bundles = files.where((File f) => f.path.endsWith('.aab')).toList();
      if (bundles.isEmpty) _fail('no .aab under ${dir.path}');
      for (final File bundle in bundles) {
        final Set<String> names = _zipNames(bundle);
        for (final String wanted in <String>[
          'BundleConfig.pb',
          'base/manifest/AndroidManifest.xml',
          'base/dex/classes.dex',
        ]) {
          if (!names.contains(wanted)) _fail('${bundle.path} has no $wanted');
        }
        if (!names.any((String n) => n.startsWith('base/lib/') && n.endsWith('libapp.so'))) {
          _fail('${bundle.path} carries no compiled Dart (base/lib/*/libapp.so)');
        }
        stdout.writeln('ok: ${bundle.path} (${bundle.lengthSync()} bytes, ${names.length} entries)');
      }
    case 'ipa-archive':
      final File? info = files
          .where((File f) => f.path.endsWith('.xcarchive/Info.plist'))
          .firstOrNull;
      if (info == null) _fail('no .xcarchive/Info.plist under ${dir.path}');
      final File? app = files
          .where((File f) => RegExp(r'\.xcarchive/Products/Applications/[^/]+\.app/Runner$').hasMatch(f.path))
          .firstOrNull;
      if (app == null) _fail('the archive has no Products/Applications/*.app/Runner');
      _machO(app);
      stdout.writeln('ok: ${app.path} (${app.lengthSync()} bytes, Mach-O, unsigned archive)');
    case 'ios':
      final File? plist = files
          .where((File f) => f.path.endsWith('Runner.app/Info.plist'))
          .firstOrNull;
      if (plist == null) _fail('no Runner.app/Info.plist under ${dir.path}');
      final File binary = File('${plist.parent.path}/Runner');
      if (!binary.existsSync()) _fail('Runner.app has no Runner executable');
      _machO(binary);
      stdout.writeln('ok: ${binary.path} (${binary.lengthSync()} bytes, Mach-O)');
    case 'chrome-extension' || 'firefox-extension':
      final Map<String, Object?> manifest = _json(File('${dir.path}/manifest.json'));
      final Object? background = manifest['background'];
      final bool chrome = args[0] == 'chrome-extension';
      if (manifest['manifest_version'] != 3) _fail('manifest.json is not manifest_version 3');
      if (background is! Map) _fail('manifest.json has no background');
      if (chrome && background['service_worker'] is! String) {
        _fail('a Chromium extension needs background.service_worker');
      }
      if (!chrome && background['scripts'] is! List) {
        _fail('a Firefox extension needs background.scripts');
      }
      for (final String wanted in <String>['index.html', 'main.dart.js']) {
        _nonEmpty(File('${dir.path}/$wanted'));
      }
      stdout.writeln('ok: ${args[0]} bundle in ${dir.path} (${files.length} files)');
    case 'vscode':
      final Map<String, Object?> package = _json(File('${dir.path}/package.json'));
      final Object? engines = package['engines'];
      if (engines is! Map || engines['vscode'] is! String) {
        _fail('package.json names no engines.vscode');
      }
      final String main = '${package['main'] ?? ''}'.replaceFirst(RegExp(r'^\./'), '');
      final String entry = main.endsWith('.js') ? main : '$main.js';
      if (main.isEmpty) _fail('package.json names no main extension.js');
      _nonEmpty(File('${dir.path}/$entry'));
      _nonEmpty(File('${dir.path}/build/web/flutter_bootstrap.js'));
      _nonEmpty(File('${dir.path}/build/web/main.dart.js'));
      stdout.writeln('ok: VS Code extension $entry with its Flutter web build');
    case 'tvos':
      final File? plist = files
          .where((File f) => RegExp(r'Runner\.app/Info\.plist$').hasMatch(f.path))
          .firstOrNull;
      if (plist == null) _fail('no Runner.app/Info.plist under ${dir.path}');
      // Binary or XML, the platform name is stored as plain ASCII.
      if (!latin1.decode(plist.readAsBytesSync()).contains('appletv')) {
        _fail('${plist.path} names no appletv platform: this is not a tvOS app');
      }
      final File binary = File('${plist.parent.path}/Runner');
      if (!binary.existsSync()) _fail('Runner.app has no Runner executable');
      _machO(binary);
      stdout.writeln('ok: ${binary.path} (${binary.lengthSync()} bytes, Mach-O, Apple TV)');
    case 'linux-cli':
      _noGtk(files);
      _elf(File('${dir.path}/flt'));
      _elf(File('${dir.path}/lib/libflutter_engine.so'));
      _nonEmpty(File('${dir.path}/run.sh'));
      _nonEmpty(File('${dir.path}/data/icudtl.dat'));
      if (!Directory('${dir.path}/data/flutter_assets').existsSync()) {
        _fail('the terminal bundle has no data/flutter_assets');
      }
      stdout.writeln('ok: terminal bundle in ${dir.path}: flt, its engine and the assets');
    case 'sony-elinux':
      _noGtk(files);
      _elf(File('${dir.path}/flutter-client'));
      _elf(File('${dir.path}/lib/libflutter_engine.so'));
      _elf(File('${dir.path}/lib/libapp.so'));
      _nonEmpty(File('${dir.path}/data/icudtl.dat'));
      if (!Directory('${dir.path}/data/flutter_assets').existsSync()) {
        _fail('the eLinux bundle has no data/flutter_assets');
      }
      stdout.writeln('ok: eLinux bundle in ${dir.path}: flutter-client, engine and AOT libapp.so');
    case 'tizen':
      final List<File> tpks = files.where((File f) => f.path.endsWith('.tpk')).toList();
      if (tpks.isEmpty) _fail('no .tpk under ${dir.path}');
      for (final File tpk in tpks) {
        final Set<String> names = _zipNames(tpk);
        for (final String wanted in <String>['tizen-manifest.xml', 'author-signature.xml']) {
          if (!names.contains(wanted)) _fail('${tpk.path} has no $wanted');
        }
        if (!names.any((String n) => n.endsWith('libflutter_engine.so'))) {
          _fail('${tpk.path} carries no libflutter_engine.so: the runner without Flutter');
        }
        if (!names.any((String n) => n.endsWith('libapp.so') || n.endsWith('kernel_blob.bin'))) {
          _fail('${tpk.path} carries no compiled Dart (libapp.so or kernel_blob.bin)');
        }
        stdout.writeln('ok: ${tpk.path} (${tpk.lengthSync()} bytes, ${names.length} entries)');
      }
    default:
      _fail('no check for ${args[0]}');
  }
}

Map<String, Object?> _json(File file) {
  if (!file.existsSync()) _fail('no ${file.path}');
  try {
    final Object? value = jsonDecode(file.readAsStringSync());
    if (value is Map<String, Object?>) return value;
  } on FormatException {
    // Reported below.
  }
  _fail('${file.path} is not a JSON object');
}

void _nonEmpty(File file) {
  if (!file.existsSync() || file.lengthSync() == 0) _fail('${file.path} is missing or empty');
}

void _elf(File file) {
  if (!file.existsSync()) _fail('no ${file.path}');
  final Uint8List head = file.openSync().readSync(4);
  if (head.length < 4 || head[0] != 0x7f || head[1] != 0x45 || head[2] != 0x4c || head[3] != 0x46) {
    _fail('${file.path} is not an ELF binary');
  }
}

/// A bundle built without a GUI carries no GTK runner library: the GUI build
/// under a terminal or device name would.
void _noGtk(List<File> files) {
  final File? gtk = files.where((File f) => f.path.endsWith('libflutter_linux_gtk.so')).firstOrNull;
  if (gtk != null) _fail('${gtk.path} is the GTK runner: this is the desktop GUI build');
}

void _machO(File binary) {
  final Uint8List head = binary.openSync().readSync(4);
  final int magic = head.length < 4 ? 0 : ByteData.sublistView(head).getUint32(0, Endian.little);
  if (magic != 0xfeedfacf && magic != 0xcafebabe && magic != 0xbebafeca) {
    _fail('${binary.path} is not a Mach-O executable (magic ${magic.toRadixString(16)})');
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
