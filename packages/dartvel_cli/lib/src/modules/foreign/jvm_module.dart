/// A JVM library, as a module: reached over JNI on Android.
///
/// The module is a Flutter plugin whose Android part declares the library
/// -- a Maven coordinate Gradle resolves, or a jar the module carries -- so
/// the application's Android build packages it. The carrier calls its
/// static methods through `package:jni`, never a platform channel. Every
/// string it hands the JVM is a local reference it releases after the call;
/// every string the JVM hands back is read and released at once, so no JNI
/// reference outlives the call that made it (DV-BIND-006 by construction).
///
/// JNI is present on Android only. On another device the carrier throws
/// `DVModuleUnavailable`, the module declares `targets: [android]` so the
/// build refuses a call from another target it can see (DV-MODULE-014), and
/// the web and the backend get what `--elsewhere` says.
library;

import 'dart:convert';

import 'package:dartvel_core/dartvel.dart'
    show DVModuleEnvironment, DVModuleOutcome;

import '../described_api.dart';
import 'dart_surface.dart';
import 'jvm_surface.dart';
import 'module_writer.dart';

/// Where the library comes from, for the Android build.
sealed class DVJvmArtifact {
  const DVJvmArtifact();
}

/// A Maven coordinate: `com.vendor:scanner:4.2.0`.
class DVMavenArtifact extends DVJvmArtifact {
  const DVMavenArtifact(this.coordinate);
  final String coordinate;
}

/// A jar the module carries, base64 so it can travel as a generated file.
class DVJarArtifact extends DVJvmArtifact {
  const DVJarArtifact(this.fileName, this.bytes);
  final String fileName;
  final List<int> bytes;
}

/// The module spec for a JVM library whose surface is [surface].
DVForeignModuleSpec dvJvmModuleSpec({
  required String id,
  required String source,
  required DVJvmSurface surface,
  required DVJvmArtifact artifact,
  DVModuleOutcome elsewhere = DVModuleOutcome.unavailable,
}) {
  final String packageName = 'dv_${dvSnake(id)}_module';
  final List<String> classes = <String>{
    for (final DVJvmMethod m in surface.methods) m.className,
  }.toList()
    ..sort();
  final StringBuffer decl = StringBuffer()
    ..writeln('/// The classes, looked up once each, and kept: a class reference')
    ..writeln('/// is global and lives as long as the process.');
  for (int i = 0; i < classes.length; i++) {
    decl
      ..writeln('JClass? _c$i;')
      ..writeln("JClass _class$i() => _c$i ??= JClass.forName('${classes[i]}');");
  }
  decl
    ..writeln()
    ..writeln('/// JNI is on Android only.')
    ..writeln('T _jvm<T>(String op, T Function() call) {')
    ..writeln('  if (!Platform.isAndroid) {')
    ..writeln("    throw DVModuleUnavailable('$id', op, DVModuleEnvironment.native);")
    ..writeln('  }')
    ..writeln('  return call();')
    ..writeln('}');

  final DVCarrierSource native = DVCarrierSource(
    imports: const <String>[
      "import 'dart:io' show Platform;",
      '',
      "import 'package:dartvel_core/dartvel.dart'\n"
          '    show DVModuleEnvironment, DVModuleUnavailable;',
      "import 'package:jni/jni.dart';",
    ],
    declarations: decl.toString(),
    body: (DVModuleOperation op) {
      final DVJvmMethod m = surface.methods
          .firstWhere((DVJvmMethod m) => m.operation.name == op.name);
      final int c = classes.indexOf(m.className);
      final List<String> strings = <String>[];
      final List<String> args = <String>[];
      for (int i = 0; i < m.paramJni.length; i++) {
        final String name = op.params[i].name;
        switch (m.paramJni[i]) {
          case 'int':
            args.add('JValueInt($name)');
          case 'float':
            args.add('JValueFloat($name)');
          case 'String':
            strings.add(name);
            args.add('j$name');
          default:
            args.add(name);
        }
      }
      final String type = switch (m.returnJni) {
        'int' => 'jint.type',
        'long' => 'jlong.type',
        'boolean' => 'jboolean.type',
        'float' => 'jfloat.type',
        'double' => 'jdouble.type',
        'String' => 'JString.type',
        _ => 'jvoid.type',
      };
      String call = "_class$c().staticMethodId('${m.name}', '${m.descriptor}')"
          '.call(_class$c(), $type, <Object?>[${args.join(', ')}])';
      if (m.returnJni == 'String') {
        call = '$call.toDartString(releaseOriginal: true)';
      }
      if (strings.isEmpty) return "_jvm('${op.name}', () => $call)";
      final String make = strings
          .map((String s) => 'final JString j$s = $s.toJString();')
          .join(' ');
      final String release =
          strings.map((String s) => 'j$s.release();').join(' ');
      return "_jvm('${op.name}', () { $make try { return $call; } "
          'finally { $release } })';
    },
  );

  final String gradle = switch (artifact) {
    DVMavenArtifact(:final String coordinate) =>
      "    implementation '$coordinate'",
    DVJarArtifact(:final String fileName) =>
      "    implementation files('libs/$fileName')",
  };

  return DVForeignModuleSpec(
    id: id,
    kind: 'jvm',
    source: source,
    description: '$source, reached over JNI on Android, as a Dartvel module.',
    operations: <DVModuleOperation>[
      for (final DVJvmMethod m in surface.methods) m.operation,
    ],
    outcomes: <String, Map<DVModuleEnvironment, DVModuleOutcome>>{
      for (final DVJvmMethod m in surface.methods)
        m.operation.name: <DVModuleEnvironment, DVModuleOutcome>{
          DVModuleEnvironment.native: DVModuleOutcome.real,
          DVModuleEnvironment.web: elsewhere,
          DVModuleEnvironment.backend: elsewhere,
        },
    },
    carriers: <DVModuleEnvironment, DVCarrierSource>{
      DVModuleEnvironment.native: native,
    },
    dependencies: const <String, String>{
      'flutter': '{sdk: flutter}',
      'jni': '^1.0.3',
    },
    skipped: surface.skipped,
    targets: const <String>['android'],
    pubspecExtra: '''
flutter:
  plugin:
    platforms:
      android:
        ffiPlugin: true
''',
    extraFiles: <String, String>{
      'android/build.gradle': '''
// GENERATED by dartvel add from $source.
// Declares the library, so the application's Android build packages it.
group 'dev.dartvel.modules.${dvSnake(id)}'
version '1.0'

apply plugin: 'com.android.library'

android {
    namespace 'dev.dartvel.modules.${dvSnake(id)}'
    compileSdk 35
    defaultConfig {
        minSdk 21
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}

dependencies {
$gradle
}
''',
      'android/settings.gradle': "rootProject.name = '$packageName'\n",
      if (artifact case DVJarArtifact(:final String fileName, :final List<int> bytes))
        'android/libs/$fileName.base64': base64Encode(bytes),
    },
  );
}
