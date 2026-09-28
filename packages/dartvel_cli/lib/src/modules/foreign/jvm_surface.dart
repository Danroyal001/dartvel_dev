/// What a JVM library offers a module, read from its compiled classes.
///
/// A jar is read as the JVM reads it: each `.class` file's constant pool and
/// method table, so the signatures are the ones the bytecode actually has,
/// not the ones documentation says it has, and nothing needs a JDK. The
/// binding is JNI (`DVJniBinding`), made through `package:jni` rather than
/// a platform channel.
///
/// What crosses: the public static methods of the classes asked for, taking
/// and returning `int`, `long`, `boolean`, `float`, `double`, `String` or
/// nothing. An instance method needs an object whose JNI reference the
/// module would own across calls, and an overloaded name has no Dart
/// spelling, so both are left out with the reason.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'dart_surface.dart';

/// One static method and the operation that calls it.
class DVJvmMethod {
  const DVJvmMethod({
    required this.className,
    required this.name,
    required this.descriptor,
    required this.returnJni,
    required this.operation,
    required this.paramJni,
  });

  /// The class, slash-separated as JNI names it: `com/acme/Scanner`.
  final String className;
  final String name;

  /// The JVM descriptor: `(II)I`.
  final String descriptor;

  /// How the answer is read: `int`, `long`, `boolean`, `float`, `double`,
  /// `String` or `void`.
  final String returnJni;

  /// How each argument is passed, in order, in the same words.
  final List<String> paramJni;

  final DVModuleOperation operation;
}

class DVJvmSurface {
  const DVJvmSurface({
    required this.methods,
    required this.skipped,
    required this.classes,
  });

  final List<DVJvmMethod> methods;
  final Map<String, String> skipped;

  /// Every public class the jar holds, dotted.
  final List<String> classes;
}

/// Reads the jar at [jar]. [only] names the classes to expose, dotted; when
/// empty, every public class is read, which a jar of more than a few classes
/// is refused for, since a module is a surface and not a copy of an SDK.
DVJvmSurface dvScanJar(String jar, {List<String> only = const <String>[]}) {
  final Directory into = Directory.systemTemp.createTempSync('dv_jar_');
  try {
    final ProcessResult unzipped = Process.runSync(
        'unzip', <String>['-q', '-o', jar, '*.class', '-d', into.path]);
    if (unzipped.exitCode > 1) {
      throw DVDartSurfaceRefused('$jar could not be read as a jar: '
          '${unzipped.stderr}');
    }
    final Map<String, _Class> classes = <String, _Class>{};
    for (final FileSystemEntity e in into.listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.class')) continue;
      final _Class? c = _readClass(e.readAsBytesSync());
      if (c != null && c.public && !c.name.contains(r'$')) classes[c.name] = c;
    }
    final List<String> names = classes.keys
        .map((String n) => n.replaceAll('/', '.'))
        .toList()
      ..sort();
    final List<String> wanted = only.isNotEmpty
        ? only
        : (names.length <= 3
            ? names
            : throw DVDartSurfaceRefused('${p.basename(jar)} has '
                '${names.length} public classes. Name the ones the module '
                'exposes with --class, for example --class ${names.first} '
                '(DV-MODULE-010).'));
    final List<DVJvmMethod> methods = <DVJvmMethod>[];
    final Map<String, String> skipped = <String, String>{};
    final bool prefix = wanted.length > 1;
    for (final String dotted in wanted) {
      final _Class? c = classes[dotted.replaceAll('.', '/')];
      if (c == null) {
        throw DVDartSurfaceRefused('${p.basename(jar)} has no public class '
            '$dotted.');
      }
      final String simple = dotted.split('.').last;
      final Map<String, int> counts = <String, int>{};
      for (final _Method m in c.methods) {
        if (m.public && !m.synthetic && m.name != '<init>' && m.name != '<clinit>') {
          counts[m.name] = (counts[m.name] ?? 0) + 1;
        }
      }
      for (final _Method m in c.methods) {
        if (!m.public || m.synthetic || m.name.startsWith('<')) continue;
        final String label = prefix ? '$simple.${m.name}' : m.name;
        if (!m.isStatic) {
          skipped[label] = 'is an instance method, and its object would be a '
              'JNI reference the module owns across calls';
          continue;
        }
        if (counts[m.name]! > 1) {
          skipped[label] = 'is overloaded, and Dart has no overloading';
          continue;
        }
        final (List<String>, String)? types = _descriptor(m.descriptor);
        if (types == null) {
          skipped[label] = 'takes or returns an object other than a String';
          continue;
        }
        final (List<String> params, String result) = types;
        final String opName = prefix
            ? '${simple[0].toLowerCase()}${simple.substring(1)}'
                '${m.name[0].toUpperCase()}${m.name.substring(1)}'
            : m.name;
        methods.add(DVJvmMethod(
          className: c.name,
          name: m.name,
          descriptor: m.descriptor,
          returnJni: result,
          paramJni: params,
          operation: DVModuleOperation(
            name: opName,
            returnType: _dart(result),
            params: <DVModuleParam>[
              for (int i = 0; i < params.length; i++)
                DVModuleParam(name: 'a$i', type: _dart(params[i])),
            ],
            doc: '`$dotted.${m.name}${m.descriptor}`.',
          ),
        ));
      }
    }
    if (methods.isEmpty) {
      throw DVDartSurfaceRefused('${p.basename(jar)} has no public static '
          'method a module can call (DV-MODULE-010).');
    }
    methods.sort((DVJvmMethod a, DVJvmMethod b) =>
        a.operation.name.compareTo(b.operation.name));
    return DVJvmSurface(methods: methods, skipped: skipped, classes: names);
  } finally {
    into.deleteSync(recursive: true);
  }
}

String _dart(String jni) => switch (jni) {
      'int' || 'long' => 'int',
      'boolean' => 'bool',
      'float' || 'double' => 'double',
      'String' => 'String',
      _ => 'void',
    };

(List<String>, String)? _descriptor(String d) {
  final int close = d.indexOf(')');
  final List<String> params = <String>[];
  int i = 1;
  while (i < close) {
    final (String?, int) t = _type(d, i);
    if (t.$1 == null) return null;
    params.add(t.$1!);
    i = t.$2;
  }
  final (String?, int) r = _type(d, close + 1);
  if (r.$1 == null) return null;
  return (params, r.$1!);
}

(String?, int) _type(String d, int i) {
  switch (d[i]) {
    case 'I':
      return ('int', i + 1);
    case 'J':
      return ('long', i + 1);
    case 'Z':
      return ('boolean', i + 1);
    case 'F':
      return ('float', i + 1);
    case 'D':
      return ('double', i + 1);
    case 'V':
      return ('void', i + 1);
    case 'L':
      final int end = d.indexOf(';', i);
      final String cls = d.substring(i + 1, end);
      return (cls == 'java/lang/String' ? 'String' : null, end + 1);
    default:
      return (null, d.length);
  }
}

class _Class {
  _Class(this.name, this.public, this.methods);
  final String name;
  final bool public;
  final List<_Method> methods;
}

class _Method {
  _Method(this.name, this.descriptor, this.access);
  final String name;
  final String descriptor;
  final int access;
  bool get public => access & 0x0001 != 0;
  bool get isStatic => access & 0x0008 != 0;
  bool get synthetic => access & 0x1000 != 0 || access & 0x0040 != 0;
}

/// Reads a class file's name, access and methods.
_Class? _readClass(Uint8List b) {
  if (b.length < 10 || b[0] != 0xCA || b[1] != 0xFE) return null;
  final ByteData data = ByteData.sublistView(b);
  int o = 8;
  final int count = data.getUint16(o);
  o += 2;
  final List<Object?> pool = List<Object?>.filled(count, null);
  for (int i = 1; i < count; i++) {
    final int tag = b[o++];
    switch (tag) {
      case 1:
        final int len = data.getUint16(o);
        pool[i] = utf8.decode(b.sublist(o + 2, o + 2 + len), allowMalformed: true);
        o += 2 + len;
      case 7:
      case 8:
      case 16:
      case 19:
      case 20:
        pool[i] = data.getUint16(o);
        o += 2;
      case 3:
      case 4:
      case 9:
      case 10:
      case 11:
      case 12:
      case 17:
      case 18:
        o += 4;
      case 5:
      case 6:
        o += 8;
        i++;
      case 15:
        o += 3;
      default:
        return null;
    }
  }
  final int access = data.getUint16(o);
  final int thisClass = data.getUint16(o + 2);
  o += 6;
  final int interfaces = data.getUint16(o);
  o += 2 + interfaces * 2;
  final String name = pool[pool[thisClass]! as int]! as String;

  int skipMembers(int at) {
    final int n = data.getUint16(at);
    at += 2;
    for (int i = 0; i < n; i++) {
      at += 6;
      final int attrs = data.getUint16(at);
      at += 2;
      for (int j = 0; j < attrs; j++) {
        at += 2;
        final int len = data.getUint32(at);
        at += 4 + len;
      }
    }
    return at;
  }

  o = skipMembers(o); // fields
  final int n = data.getUint16(o);
  o += 2;
  final List<_Method> methods = <_Method>[];
  for (int i = 0; i < n; i++) {
    final int flags = data.getUint16(o);
    final String mName = pool[data.getUint16(o + 2)]! as String;
    final String desc = pool[data.getUint16(o + 4)]! as String;
    o += 6;
    final int attrs = data.getUint16(o);
    o += 2;
    for (int j = 0; j < attrs; j++) {
      o += 2;
      final int len = data.getUint32(o);
      o += 4 + len;
    }
    methods.add(_Method(mName, desc, flags));
  }
  return _Class(name, access & 0x0001 != 0, methods);
}
