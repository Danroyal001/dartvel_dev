// Where the device-admin receiver stops being there.
//
// `dpm set-device-owner` failed with "Unknown admin", and `pm
// query-receivers` found none belonging to the package, against a build
// whose only guard was that the receiver's .java file existed. Those two
// facts are compatible with three different bugs, and the job could not tell
// them apart:
//
//   1. `dartvel build android` never wrote the receiver into the manifest
//      (the guard checked the Java file and the HOME category, not this);
//   2. it wrote it and the packager dropped it, so the APK does not carry it;
//   3. the APK carries it and the device is running an older install.
//
// This names which. It reads the source manifest, then reads the manifest
// back out of the APK that was actually built, and says what each one has.
// A check that reports the end state is a check that leaves somebody
// guessing at the middle.
import 'dart:convert';
import 'dart:io';

const String _receiver = 'DartvelDeviceAdminReceiver';
const String _action = 'android.app.action.DEVICE_ADMIN_ENABLED';

Future<void> main(List<String> args) async {
  final String root = args.isNotEmpty ? args.first : '.';
  final String apkPath = args.length > 1
      ? args[1]
      : '$root/build/app/outputs/flutter-apk/app-debug.apk';

  bool ok = true;

  // Stage one: what the generator wrote.
  final File manifest =
      File('$root/android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('✗ ${manifest.path} is not there at all.');
    exit(1);
  }
  final String source = manifest.readAsStringSync();
  if (source.contains(_receiver)) {
    stdout.writeln('✓ the source manifest declares $_receiver');
    if (!source.contains(_action)) {
      stdout.writeln('✗ ...but without the $_action intent filter, which is '
          'how the system finds a device-admin component at all. A receiver '
          'without it installs and resolves to nothing.');
      ok = false;
    }
  } else {
    stdout.writeln('✗ the source manifest does NOT declare $_receiver. '
        'dartvel build wrote the .java file and the policy XML and did not '
        'splice the manifest block -- the fault is in the generator, before '
        'anything Android does.');
    ok = false;
  }

  // Stage two: what the packager kept.
  final File apk = File(apkPath);
  if (!apk.existsSync()) {
    stdout.writeln('· no APK at $apkPath, so only the source was checked.');
    exit(ok ? 0 : 1);
  }
  final String? aapt2 = await _aapt2();
  if (aapt2 == null) {
    stdout.writeln('· aapt2 is not on PATH or under the SDK, so the packaged '
        'manifest was not read. This is a gap in the check, not a pass.');
    exit(ok ? 0 : 1);
  }
  final ProcessResult dump = await Process.run(aapt2,
      <String>['dump', 'xmltree', apk.path, '--file', 'AndroidManifest.xml']);
  final String tree = '${dump.stdout}';
  if (dump.exitCode != 0) {
    stdout.writeln('· aapt2 could not read $apkPath: ${dump.stderr}');
    exit(ok ? 0 : 1);
  }
  Directory('${Platform.environment['RUNNER_TEMP'] ?? '/tmp'}/diag')
      .createSync(recursive: true);
  File('${Platform.environment['RUNNER_TEMP'] ?? '/tmp'}/diag/'
          'android-packaged-manifest.txt')
      .writeAsStringSync(tree);

  if (tree.contains(_receiver)) {
    stdout.writeln('✓ the built APK carries $_receiver');
    if (!tree.contains(_action)) {
      stdout.writeln('✗ ...but the packaged manifest has no $_action filter. '
          'The merger kept the receiver and lost its intent filter, which is '
          'the same as not having it.');
      ok = false;
    }
    // The name as packaged, because ".Foo" in source becomes the fully
    // qualified name here, and a namespace that is not the applicationId is
    // how a component that exists resolves under a name nobody asks for.
    for (final String line in const LineSplitter().convert(tree)) {
      if (line.contains(_receiver)) stdout.writeln('   $line'.trimRight());
    }
  } else {
    stdout.writeln('✗ the built APK does NOT carry $_receiver, though the '
        'source manifest does. The manifest merger dropped it -- look at '
        'app/build/intermediates/merged_manifests/ and at the merger report, '
        'not at the generator.');
    ok = false;
  }

  exit(ok ? 0 : 1);
}

/// aapt2, from the SDK the runner already has.
Future<String?> _aapt2() async {
  final ProcessResult which = await Process.run('which', <String>['aapt2']);
  if (which.exitCode == 0) return '${which.stdout}'.trim();

  final String? sdk = Platform.environment['ANDROID_SDK_ROOT'] ??
      Platform.environment['ANDROID_HOME'];
  if (sdk == null) return null;
  final Directory tools = Directory('$sdk/build-tools');
  if (!tools.existsSync()) return null;
  // The newest build-tools, because an old one cannot read an APK a newer
  // AGP wrote.
  final List<String> versions = tools
      .listSync()
      .whereType<Directory>()
      .map((Directory d) => d.path)
      .toList()
    ..sort();
  for (final String version in versions.reversed) {
    final File candidate = File('$version/aapt2');
    if (candidate.existsSync()) return candidate.path;
  }
  return null;
}
