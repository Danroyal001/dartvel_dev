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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<void> main(List<String> args) async {
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
    case 'macos':
      final File? plist = files
          .where((File f) => RegExp(r'\.app/Contents/Info\.plist$').hasMatch(f.path.replaceAll(r'\', '/')))
          .firstOrNull;
      if (plist == null) _fail('no *.app/Contents/Info.plist under ${dir.path}: not a macOS app bundle');
      if (!latin1.decode(plist.readAsBytesSync()).contains('MacOSX')) {
        _fail('${plist.path} names no MacOSX platform');
      }
      final String contents = plist.parent.path;
      final List<File> executables = Directory('$contents/MacOS').existsSync()
          ? Directory('$contents/MacOS').listSync().whereType<File>().toList()
          : const <File>[];
      if (executables.isEmpty) _fail('$contents/MacOS holds no executable');
      for (final File binary in executables) {
        _machO(binary);
        _executable(binary);
      }
      // Versioned frameworks: the engine reaches the app's assets and its own
      // binary through the links into Versions/Current.
      if (!Directory('$contents/Frameworks/App.framework/Resources/flutter_assets').existsSync()) {
        _fail('$contents/Frameworks/App.framework/Resources/flutter_assets is not reachable: '
            'the framework lost its links into Versions/Current');
      }
      _machO(File('$contents/Frameworks/FlutterMacOS.framework/FlutterMacOS'));
      if (Platform.isMacOS) {
        final ProcessResult verified = Process.runSync(
            'codesign', <String>['--verify', '--deep', '--strict', Directory(contents).parent.path]);
        if (verified.exitCode != 0) {
          _fail('codesign --verify rejects ${Directory(contents).parent.path}: ${verified.stderr}');
        }
      }
      stdout.writeln('ok: ${Directory(contents).parent.path}: Mach-O ${executables.first.uri.pathSegments.last}, '
          'FlutterMacOS and App frameworks');
    case 'windows':
      final List<File> exes = files.where((File f) => f.path.toLowerCase().endsWith('.exe')).toList();
      if (exes.isEmpty) _fail('no .exe under ${dir.path}');
      for (final File exe in exes) {
        if (_pe(exe)) _fail('${exe.path} is a DLL, not an executable');
      }
      if (!_pe(File('${dir.path}/flutter_windows.dll'))) {
        _fail('${dir.path}/flutter_windows.dll is not a DLL');
      }
      _nonEmpty(File('${dir.path}/data/icudtl.dat'));
      _compiledDart(dir, 'data/app.so');
      stdout.writeln('ok: ${exes.first.path}, flutter_windows.dll and data/');
    case 'linux':
      final File? gtk = files.where((File f) => f.path.endsWith('lib/libflutter_linux_gtk.so')).firstOrNull;
      if (gtk == null) _fail('no lib/libflutter_linux_gtk.so under ${dir.path}: not the GTK desktop bundle');
      _elf(gtk);
      final List<File> runners = dir.listSync().whereType<File>().toList();
      if (runners.isEmpty) _fail('${dir.path} has no executable at the top of the bundle');
      for (final File runner in runners) {
        _elf(runner);
        _executable(runner);
      }
      _nonEmpty(File('${dir.path}/data/icudtl.dat'));
      _compiledDart(dir, 'lib/libapp.so');
      stdout.writeln('ok: Linux bundle in ${dir.path}: ${runners.first.uri.pathSegments.last}, GTK runner, assets');
    case 'web':
      _nonEmpty(File('${dir.path}/index.html'));
      _nonEmpty(File('${dir.path}/flutter_bootstrap.js'));
      _nonEmpty(File('${dir.path}/main.dart.js'));
      stdout.writeln('ok: web build in ${dir.path} (${files.length} files)');
    case 'web-server':
      if (files.length != 1) {
        _fail('a web-server build is one file, and ${dir.path} holds ${files.length}');
      }
      final File server = files.single;
      final Uint8List head = server.openSync().readSync(4);
      final bool native = head.length == 4 &&
          ((head[0] == 0x7f && head[1] == 0x45 && head[2] == 0x4c && head[3] == 0x46) ||
              (head[0] == 0x4d && head[1] == 0x5a) ||
              <int>[0xfeedfacf, 0xcafebabe, 0xbebafeca]
                  .contains(ByteData.sublistView(head).getUint32(0, Endian.little)));
      if (!native) _fail('${server.path} is not a native executable');
      _executable(server);
      await _serves(server);
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
  if (!binary.existsSync()) _fail('no ${binary.path}');
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


/// Whether [file] is a Windows PE image: false for an executable, true for a
/// DLL. Anything else fails.
bool _pe(File file) {
  if (!file.existsSync()) _fail('no ${file.path}');
  final Uint8List b = file.readAsBytesSync();
  if (b.length < 0x40 || b[0] != 0x4d || b[1] != 0x5a) _fail('${file.path} is not a PE image');
  final int at = ByteData.sublistView(b).getUint32(0x3c, Endian.little);
  if (at + 24 > b.length || b[at] != 0x50 || b[at + 1] != 0x45 || b[at + 2] != 0 || b[at + 3] != 0) {
    _fail('${file.path} is not a PE image');
  }
  return ByteData.sublistView(b).getUint16(at + 4 + 18, Endian.little) & 0x2000 != 0;
}

/// A binary the download left without its executable bit cannot be run by
/// whoever downloaded it. Windows has no such bit.
void _executable(File file) {
  if (Platform.isWindows) return;
  if (file.statSync().mode & 0x49 == 0) _fail('${file.path} is not executable');
}

/// A release build's AOT library at [aot], or a debug build's kernel.
void _compiledDart(Directory dir, String aot) {
  if (File('${dir.path}/$aot').existsSync()) return _nonEmpty(File('${dir.path}/$aot'));
  _nonEmpty(File('${dir.path}/data/flutter_assets/kernel_blob.bin'));
}

/// Copies [server] alone into an empty directory, starts it with nothing but
/// a port, and asks it for / and for the web app's code.
Future<void> _serves(File server) async {
  final Directory deploy = Directory.systemTemp.createTempSync('cloud_artifact_server_');
  final File binary = server.copySync('${deploy.path}/${server.uri.pathSegments.last}');
  if (!Platform.isWindows) Process.runSync('chmod', <String>['755', binary.path]);
  final ServerSocket probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final int port = probe.port;
  await probe.close();
  final Map<String, String> parent = Platform.environment;
  final Process process = await Process.start(binary.path, const <String>[],
      workingDirectory: deploy.path,
      includeParentEnvironment: false,
      environment: <String, String>{
        if (Platform.isWindows) ...<String, String>{
          for (final String name in const <String>['SystemRoot', 'TEMP', 'TMP', 'USERPROFILE', 'PATH'])
            if (parent[name] != null) name: parent[name]!,
        } else
          'PATH': '/usr/bin:/bin',
        'DARTVEL_PORT': '$port',
      });
  final StringBuffer output = StringBuffer();
  process.stdout.transform(utf8.decoder).listen(output.write);
  process.stderr.transform(utf8.decoder).listen(output.write);
  int? exited;
  unawaited(process.exitCode.then((int code) => exited = code));
  final HttpClient client = HttpClient();
  Future<(int, String, String)?> get(String path) async {
    try {
      final HttpClientResponse r = await (await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'))).close();
      return (r.statusCode, r.headers.contentType?.mimeType ?? '', await r.transform(utf8.decoder).join());
    } on SocketException {
      return null;
    } on HttpException {
      return null;
    }
  }

  try {
    (int, String, String)? page;
    final DateTime deadline = DateTime.now().add(const Duration(minutes: 2));
    while (page == null && exited == null && DateTime.now().isBefore(deadline)) {
      page = await get('/');
      if (page == null) await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (page == null) _fail('${server.path} never answered on port $port (exit $exited):\n$output');
    if (page.$1 != 200 || page.$2 != 'text/html' || !page.$3.contains('<title>')) {
      _fail('${server.path} answered / with ${page.$1} ${page.$2}, not a page:\n${page.$3}');
    }
    final (int, String, String)? script = await get('/main.dart.js');
    if (script == null || script.$1 != 200 || script.$3.length < 10000) {
      _fail('${server.path} does not serve the web app code at /main.dart.js');
    }
    stdout.writeln('ok: ${server.path} (${server.lengthSync()} bytes) started alone and served / '
        'and main.dart.js (${script.$3.length} bytes)');
  } finally {
    client.close(force: true);
    process.kill();
    await process.exitCode.timeout(const Duration(seconds: 10), onTimeout: () => -1);
    try {
      deploy.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows can hold the image a moment after exit.
    }
  }
}

Never _fail(String message) {
  stderr.writeln('cloud-artifact: $message');
  exit(1);
}
