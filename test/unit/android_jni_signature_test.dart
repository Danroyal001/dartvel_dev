// Every Java method Dart looks up by name, against the Java the build writes.
//
// This is the check that would have caught the bug the whole Android layer is
// built around. `JClass.forName` and `staticMethodId` take strings. A class
// that is not there, a method spelled differently, a JNI signature with one
// wrong letter: none of them is a compile error in either language, and all
// of them fail identically on a device, as a binding that quietly answers
// nothing. `GetApplicationContext` was declared in a header with no
// definition behind it and every Android binding shipped dead; the shape of
// that mistake is a name on one side that nothing answers on the other.
//
// So this reads both sides. The Dart, as text, for every lookup it performs;
// the Java, from the generator functions that write it, for what it actually
// declares. It runs on any machine, with no Android SDK and no device.
import 'dart:io';

import 'package:dartvel_cli/src/build/android_capture_bridge.dart';
import 'package:dartvel_cli/src/build/android_context_provider.dart';
import 'package:dartvel_cli/src/build/android_home_widget.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// One `staticMethodId('name', 'signature')` in the Dart source.
class _Lookup {
  const _Lookup(this.file, this.name, this.signature, this.classes);

  final String file;
  final String name;
  final String signature;

  /// The Java classes that file names, in JNI form.
  final Set<String> classes;

  @override
  String toString() => '$file: $name$signature in ${classes.join(', ')}';
}

/// One `public static` method in a generated Java source.
class _Declared {
  const _Declared(this.name, this.signature);

  final String name;
  final String signature;
}

void main() {
  // The Java the build writes, by the JNI name Dart looks it up under. The
  // widget publisher takes a package and a widget list; neither changes what
  // it declares.
  final Map<String, String> java = <String, String>{
    dvAndroidContextClass: dvAndroidContextProviderSource(),
    dvAndroidCaptureBridgeClass: dvAndroidCaptureBridgeSource(),
    dvHomeWidgetAndroidClass:
        dvAndroidWidgetPublisherSource('com.example.app', const []),
  };

  final List<_Lookup> lookups = _lookupsInDartSource(java.keys.toSet());

  test('the scan finds lookups at all', () {
    // Without this the regular expressions could stop matching -- a
    // reformat, a rename -- and every assertion below would pass over an
    // empty list, which is the way a check of this kind dies quietly.
    expect(lookups.length, greaterThanOrEqualTo(4));
    expect(lookups.map((_Lookup l) => l.name), contains('context'));
    expect(lookups.map((_Lookup l) => l.name), contains('begin'));
  });

  test('the signature reader can tell a wrong signature from a right one', () {
    // The checker checking itself. A comparison that always passed would
    // make every assertion below meaningless, and this file exists precisely
    // because that class of silence is expensive here.
    const String source = '''
public final class Example {
  public static String publish(String key, String text) { return key; }
  public static int begin(String op, String argument) { return 0; }
  public static Context context() { return null; }
}
''';
    final List<_Declared> declared = _declaredIn(source);
    expect(_signatureOf(declared, 'publish'),
        '(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;');
    expect(_signatureOf(declared, 'begin'),
        '(Ljava/lang/String;Ljava/lang/String;)I');
    expect(_signatureOf(declared, 'context'), '()Landroid/content/Context;');
    // The failure it has to catch: one letter wrong in the return type.
    expect(_signatureOf(declared, 'begin'),
        isNot('(Ljava/lang/String;Ljava/lang/String;)J'));
    expect(_signatureOf(declared, 'missing'), isNull);
  });

  test('every Java method Dart looks up is declared, with that signature', () {
    final List<String> problems = <String>[];
    for (final _Lookup lookup in lookups) {
      final List<String> candidates = <String>[
        for (final String name in lookup.classes)
          if (java.containsKey(name)) name,
      ];
      if (candidates.isEmpty) continue;

      final List<String> found = <String>[];
      bool matched = false;
      for (final String name in candidates) {
        final String? signature =
            _signatureOf(_declaredIn(java[name]!), lookup.name);
        if (signature == null) continue;
        found.add('$name declares ${lookup.name}$signature');
        if (signature == lookup.signature) matched = true;
      }
      if (matched) continue;
      problems.add(found.isEmpty
          ? '${lookup.file} looks up ${lookup.name}${lookup.signature}, and '
              'none of ${candidates.join(', ')} declares a public static '
              'method by that name'
          : '${lookup.file} looks up ${lookup.name}${lookup.signature}; '
              '${found.join('; ')}');
    }

    expect(problems, isEmpty,
        reason: 'a JNI lookup and the Java it is meant to reach have drifted '
            'apart. Neither language errors on this: the lookup throws on a '
            'device and the binding answers nothing.\n'
            '${problems.join('\n')}');
  });

  test('the classes the build writes are the ones Dart names', () {
    // The other half of the same failure. A class Dart looks up that no
    // generator writes is a NoClassDefFoundError on a phone and nothing at
    // all here.
    final Set<String> named = <String>{
      for (final _Lookup lookup in lookups) ...lookup.classes,
    };
    for (final String name in named) {
      expect(java.keys, contains(name),
          reason: 'the Flutter package looks up $name and no generator in '
              'dartvel_cli writes a class by that name');
    }
  });
}

/// Every `staticMethodId` in the Flutter package's Android sources, with the
/// Java classes its file names.
List<_Lookup> _lookupsInDartSource(Set<String> known) {
  final RegExp lookup =
      RegExp(r"staticMethodId\(\s*'([A-Za-z0-9_]+)'\s*,\s*'([^']+)'");
  // Both spellings of naming a class: the literal, and the shared constant.
  final RegExp literal = RegExp(r"JClass\.forName\(\s*'([^']+)'");
  final Map<String, String> constants = <String, String>{
    'dvAndroidCaptureBridgeClass': dvAndroidCaptureBridgeClass,
    'dvHomeWidgetAndroidClass': dvHomeWidgetAndroidClass,
    '_contextHolder': dvAndroidContextClass,
    '_widgetPublisher': dvHomeWidgetAndroidClass,
  };

  final Directory android = Directory('packages/dartvel_flutter/lib/src/'
      'platform/android');
  final List<_Lookup> found = <_Lookup>[];
  for (final FileSystemEntity entity in android.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // The generated jnigen bindings look up hundreds of methods on classes
    // from android.jar, which no generator here writes and which are not
    // this test's business.
    if (entity.path.contains('/generated/')) continue;
    final String source = entity.readAsStringSync();

    final Set<String> classes = <String>{
      for (final RegExpMatch match in literal.allMatches(source))
        match.group(1)!,
      for (final MapEntry<String, String> constant in constants.entries)
        if (source.contains(constant.key)) constant.value,
    }.where(known.contains).toSet();
    if (classes.isEmpty) continue;

    for (final RegExpMatch match in lookup.allMatches(source)) {
      found.add(_Lookup(
        entity.uri.pathSegments.last,
        match.group(1)!,
        match.group(2)!,
        classes,
      ));
    }
  }
  return found;
}

/// Every `public static` method a Java source declares.
List<_Declared> _declaredIn(String java) {
  final RegExp method = RegExp(
      r'public\s+static\s+([A-Za-z0-9_.\[\]<>]+)\s+([A-Za-z0-9_]+)\s*\(([^)]*)\)');
  final List<_Declared> out = <_Declared>[];
  for (final RegExpMatch match in method.allMatches(java)) {
    final String returns = match.group(1)!;
    // `public static final String EXTRA_ID = ...` is a field, and a field
    // with a name that happens to be followed by a parenthesis would be read
    // as a method. `final` never appears in a method's return position here.
    if (returns == 'final') continue;
    final List<String> parameters = match
        .group(3)!
        .split(',')
        .map((String each) => each.trim())
        .where((String each) => each.isNotEmpty)
        .map((String each) => each.split(RegExp(r'\s+')).first)
        .toList();
    out.add(_Declared(
      match.group(2)!,
      '(${parameters.map(_jniType).join()})${_jniType(returns)}',
    ));
  }
  return out;
}

String? _signatureOf(List<_Declared> declared, String name) {
  for (final _Declared each in declared) {
    if (each.name == name) return each.signature;
  }
  return null;
}

/// One Java type in JNI's spelling.
///
/// Unknown types throw rather than being guessed at. A guess would make this
/// whole file agree with itself and with nothing else.
String _jniType(String java) {
  const Map<String, String> types = <String, String>{
    'void': 'V',
    'int': 'I',
    'long': 'J',
    'float': 'F',
    'double': 'D',
    'boolean': 'Z',
    'byte': 'B',
    'char': 'C',
    'short': 'S',
    'String': 'Ljava/lang/String;',
    'Context': 'Landroid/content/Context;',
    'Activity': 'Landroid/app/Activity;',
    'Intent': 'Landroid/content/Intent;',
    'Uri': 'Landroid/net/Uri;',
    'Bundle': 'Landroid/os/Bundle;',
    'Cursor': 'Landroid/database/Cursor;',
    'Object': 'Ljava/lang/Object;',
  };
  if (java.endsWith('[]')) {
    return '[${_jniType(java.substring(0, java.length - 2))}';
  }
  final String? known = types[java];
  if (known == null) {
    throw StateError('this test does not know the JNI spelling of "$java". '
        'Add it to _jniType rather than letting the comparison pass on a '
        'type it cannot read.');
  }
  return known;
}
