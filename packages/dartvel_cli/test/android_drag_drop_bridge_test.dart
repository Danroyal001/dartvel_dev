// The Java `dartvel build android` writes for drag and drop, compiled against
// the real Android platform jar, so a wrong method name or a missing import
// fails here rather than in somebody's Gradle build.
@TestOn('vm')
library;

import 'dart:io';

import 'package:dartvel_cli/src/build/android_capture_bridge.dart';
import 'package:dartvel_cli/src/build/android_drag_drop_bridge.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String? _javac() {
  final String? home = Platform.environment['JAVA_HOME'];
  if (home != null && File(p.join(home, 'bin', 'javac')).existsSync()) {
    return p.join(home, 'bin', 'javac');
  }
  final ProcessResult which = Process.runSync('which', <String>['javac']);
  return which.exitCode == 0 ? '${which.stdout}'.trim() : null;
}

/// The newest android.jar in the SDK, or null when there is no SDK here.
String? _androidJar() {
  final String? sdk = Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'];
  if (sdk == null) return null;
  final Directory platforms = Directory(p.join(sdk, 'platforms'));
  if (!platforms.existsSync()) return null;
  final List<String> jars = <String>[
    for (final FileSystemEntity entry in platforms.listSync())
      if (File(p.join(entry.path, 'android.jar')).existsSync())
        p.join(entry.path, 'android.jar'),
  ]..sort();
  return jars.isEmpty ? null : jars.last;
}

void main() {
  final String? javac = _javac();
  final String? androidJar = _androidJar();

  test('the drag and drop bridge is written beside the capture bridge', () {
    expect(p.dirname(dvAndroidDragDropPath), p.dirname(dvAndroidCaptureFilesPath));
    expect(File('lib/src/commands/build_command.dart').readAsStringSync(),
        contains('dvAndroidDragDropPath: dvAndroidDragDropSource()'),
        reason: 'every Android build writes it, as it writes the capture bridge');
  });

  test('a drag leaves the window and lets the receiver read its files', () {
    final String source = dvAndroidDragDropSource();
    expect(source, contains('View.DRAG_FLAG_GLOBAL | View.DRAG_FLAG_GLOBAL_URI_READ'));
    expect(source, contains('requestDragAndDropPermissions(event)'),
        reason: 'without it a content:// URI from another app throws on read');
  });

  test('the Java compiles against the Android platform', () async {
    final Directory work = Directory.systemTemp.createTempSync('dartvel_dnd_java_');
    addTearDown(() => work.deleteSync(recursive: true));
    final String folder = p.join(work.path, 'src', 'dev', 'dartvel', 'jni');
    Directory(folder).createSync(recursive: true);
    final String dragDrop = p.join(folder, 'DartvelDragDrop.java');
    final String files = p.join(folder, 'DartvelCaptureFiles.java');
    File(dragDrop).writeAsStringSync(dvAndroidDragDropSource());
    File(files).writeAsStringSync(dvAndroidCaptureFilesSource());
    final ProcessResult result = await Process.run(javac!, <String>[
      '--release', '8', '-Xlint:-options',
      '-cp', androidJar!,
      '-d', p.join(work.path, 'classes'),
      dragDrop, files,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  }, skip: javac == null || androidJar == null
      ? 'needs a JDK and an Android SDK (ANDROID_HOME) to compile against'
      : null);
}
