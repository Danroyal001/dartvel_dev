/// Retracing an R8 / ProGuard `mapping.txt`.
///
/// A release build of an Android app renames every class and method and
/// collapses line numbers, so a stack from a user's phone says
/// `a.a.a.onCreate(SourceFile:2)`. The mapping file R8 writes beside the
/// build is the only way back, and it is per build: a mapping from last
/// week's release is a plausible-looking wrong answer for this week's. That is
/// why the symbols bundle is versioned by release.
///
/// This is the part of the format a crash report needs -- classes, methods
/// with line ranges, and inlined chains -- and not a replacement for R8's
/// `retrace` tool (it does not resolve fields, or R8's partial-compilation
/// outline frames). A line it cannot place is returned as it came, never
/// guessed at.
library;

/// One frame of an original stack, after retracing.
final class DVRetracedFrame {
  const DVRetracedFrame({
    required this.className,
    required this.methodName,
    this.fileName,
    this.line,
  });

  final String className;
  final String methodName;

  /// The source file, from the mapping or derived from the outer class.
  final String? fileName;
  final int? line;

  @override
  String toString() => '$className.$methodName(${fileName ?? 'Unknown Source'}'
      '${line == null ? '' : ':$line'})';
}

class _Range {
  const _Range(this.from, this.to);
  final int from;
  final int to;

  bool contains(int line) => line >= from && line <= to;
}

class _Member {
  _Member({
    required this.originalName,
    required this.originalClass,
    required this.minified,
    required this.original,
    required this.originalIsSingleLine,
  });

  final String originalName;

  /// The class the original method is declared in when it is not the class
  /// the member is listed under: R8 writes an inlined method as
  /// `com.example.Other.helper`, and a frame for it is in `Other`.
  final String? originalClass;

  /// R8 marks code it made up (a lambda's bridge, an outline) with a
  /// `synthesized` metadata line; a retraced stack leaves those frames out.
  bool synthetic = false;

  final _Range? minified;
  final _Range? original;

  /// `:30` rather than `:30:34`: every minified line in the range is line 30.
  final bool originalIsSingleLine;
}

class _MappedClass {
  _MappedClass(this.original);
  final String original;
  String? sourceFile;

  /// A class R8 made up (a lambda, an API-level outline). Its frames are not
  /// in the source, and a retraced stack leaves them out.
  bool synthetic = false;

  /// Members by minified name, in file order: for one minified range, the
  /// order is an inlining chain, innermost first.
  final Map<String, List<_Member>> members = <String, List<_Member>>{};
  _Member? lastMember;
}

/// A parsed mapping.
class DVProguardMapping {
  DVProguardMapping._(this._classes, [Map<String, String>? files])
      : _files = files ?? const <String, String>{};

  final Map<String, _MappedClass> _classes;
  final Map<String, String> _files;

  /// An empty mapping, which retraces nothing.
  factory DVProguardMapping.empty() =>
      DVProguardMapping._(<String, _MappedClass>{});

  // `com.example.A -> a.a.a:`
  static final RegExp _classLine = RegExp(r'^(\S+) -> (\S+):$');
  // `    1:3:void onCreate(android.os.Bundle):12:14 -> onCreate`
  // `    void reset() -> c`
  static final RegExp _methodLine = RegExp(
      r'^\s+(?:(\d+):(\d+):)?[^\s()]+\s+([^\s()]+)\(([^)]*)\)(?::(\d+)(?::(\d+))?)?\s+->\s+(\S+)$');
  static final RegExp _sourceFile =
      RegExp(r'"id"\s*:\s*"sourceFile"\s*,\s*"fileName"\s*:\s*"([^"]+)"');
  static final RegExp _synthesized =
      RegExp(r'"id"\s*:\s*"com\.android\.tools\.r8\.synthesized"');

  /// Parses [text]. Lines it does not understand are skipped: a mapping with
  /// a member line from a newer R8 is still good for every line it can read.
  factory DVProguardMapping.parse(String text) {
    final Map<String, _MappedClass> classes = <String, _MappedClass>{};
    _MappedClass? current;
    for (final String raw in LineSplitterLite.split(text)) {
      if (raw.isEmpty) continue;
      if (raw.startsWith('#')) {
        // R8 writes a class's own metadata as a comment line directly under
        // it, at the left margin.
        final RegExpMatch? file = _sourceFile.firstMatch(raw);
        if (file != null && current != null) current.sourceFile = file.group(1);
        if (current != null && _synthesized.hasMatch(raw)) {
          current.synthetic = true;
        }
        continue;
      }
      if (!raw.startsWith(' ') && !raw.startsWith('\t')) {
        final RegExpMatch? match = _classLine.firstMatch(raw);
        if (match == null) {
          current = null;
          continue;
        }
        current = _MappedClass(match.group(1)!);
        classes[match.group(2)!] = current;
        continue;
      }
      if (current == null) continue;
      final String line = raw.trimLeft();
      if (line.startsWith('#')) {
        final RegExpMatch? file = _sourceFile.firstMatch(line);
        if (file != null) current.sourceFile = file.group(1);
        if (_synthesized.hasMatch(line)) current.lastMember?.synthetic = true;
        continue;
      }
      final RegExpMatch? match = _methodLine.firstMatch(raw);
      if (match == null) continue;
      final String? minStart = match.group(1);
      final String? minEnd = match.group(2);
      final String? origStart = match.group(5);
      final String? origEnd = match.group(6);
      // `com.example.Other.helper` is a method inlined from another class.
      final String qualified = match.group(3)!;
      final int lastDot = qualified.lastIndexOf('.');
      final _Member member = _Member(
            originalName:
                lastDot < 0 ? qualified : qualified.substring(lastDot + 1),
            originalClass: lastDot < 0 ? null : qualified.substring(0, lastDot),
            minified: minStart == null
                ? null
                : _Range(int.parse(minStart), int.parse(minEnd!)),
            original: origStart == null
                ? null
                : _Range(int.parse(origStart),
                    int.parse(origEnd ?? origStart)),
            // `:30` and `:30:30` both say every minified line in the range is
            // line 30.
            originalIsSingleLine:
                origStart != null && (origEnd == null || origEnd == origStart),
          );
      current.members.putIfAbsent(match.group(7)!, () => <_Member>[]).add(member);
      current.lastMember = member;
    }
    // Source files by original class, for frames of a class that is not the
    // one the stack named.
    final Map<String, String> files = <String, String>{
      for (final _MappedClass mapped in classes.values)
        if (mapped.sourceFile != null) mapped.original: mapped.sourceFile!,
    };
    return DVProguardMapping._(classes, files);
  }

  /// How many classes the mapping renames.
  int get classCount => _classes.length;

  /// Whether the mapping renames nothing.
  bool get isEmpty => _classes.isEmpty;

  /// The original name of [minified], or [minified] when the mapping does not
  /// rename it.
  String originalClass(String minified) =>
      _classes[minified]?.original ?? minified;

  /// The original frames for a call at [line] of [className].[methodName].
  ///
  /// More than one when the method was inlined: innermost first, as in a
  /// stack. [line] is null for a frame the VM reported without one.
  List<DVRetracedFrame> retraceFrame(
    String className,
    String methodName,
    int? line,
  ) {
    final _MappedClass? mapped = _classes[className];
    if (mapped == null) {
      return <DVRetracedFrame>[
        DVRetracedFrame(
            className: className,
            methodName: methodName,
            fileName: null,
            line: line),
      ];
    }
    final String file = mapped.sourceFile ?? _fileOf(mapped.original);
    final List<_Member> candidates = mapped.members[methodName] ?? const <_Member>[];
    if (candidates.isEmpty) {
      return <DVRetracedFrame>[
        DVRetracedFrame(
            className: mapped.original,
            methodName: methodName,
            fileName: file,
            line: line),
      ];
    }

    // The members whose minified range holds the line: an inlining chain when
    // there is more than one. Members with no range hold every line.
    final List<_Member> matching = <_Member>[
      for (final _Member member in candidates)
        if (member.minified == null ||
            (line != null && member.minified!.contains(line)))
          member,
    ];
    if (matching.isEmpty) {
      // The line is in no range: the method is still known, the line is not.
      return <DVRetracedFrame>[
        DVRetracedFrame(
            className: mapped.original,
            methodName: candidates.first.originalName,
            fileName: file,
            line: line),
      ];
    }
    // When ranged members match, an unranged one is not part of the chain.
    final bool anyRanged = matching.any((_Member m) => m.minified != null);
    final List<_Member> chain = <_Member>[
      for (final _Member member in matching)
        if (!anyRanged || member.minified != null) member,
    ];
    // Code R8 made up is not in the source; a trace shows the frames that are.
    // A chain that is nothing but such code keeps all of it rather than
    // vanishing.
    //
    // A synthetic class's own methods are such code (a lambda's `apply`), but
    // the real methods inlined into them are not: those frames stay.
    final List<_Member> real = chain
        .where((_Member m) =>
            !m.synthetic && !(mapped.synthetic && _isOwn(mapped, m)))
        .toList(growable: false);
    if (real.isEmpty && mapped.synthetic) return const <DVRetracedFrame>[];
    return _withoutRepeats(<DVRetracedFrame>[
      for (final _Member member in real.isEmpty ? chain : real)
        _frameOf(mapped, member, line),
    ]);
  }

  /// R8 lists the method that contains inlined code a second time, with no
  /// line (`:0`), after the inlined frames. It is the same method as the one
  /// the line did place, not another frame of the stack: keep one, the one
  /// with a line.
  static List<DVRetracedFrame> _withoutRepeats(List<DVRetracedFrame> frames) {
    final List<DVRetracedFrame> out = <DVRetracedFrame>[];
    for (final DVRetracedFrame frame in frames) {
      final int index = out.indexWhere((DVRetracedFrame kept) =>
          kept.className == frame.className &&
          kept.methodName == frame.methodName &&
          (kept.line == null || frame.line == null));
      if (index < 0) {
        out.add(frame);
      } else if (out[index].line == null && frame.line != null) {
        out[index] = frame;
      }
    }
    return out;
  }

  /// Whether [member] is a method of the class it is listed under, rather
  /// than one inlined from another. R8 qualifies a member's original name with
  /// its class, and for a class it generated it uses the short name, so a
  /// member is its own class's when the qualifier is that class's name or the
  /// end of it.
  static bool _isOwn(_MappedClass mapped, _Member member) {
    final String? qualifier = member.originalClass;
    return qualifier == null ||
        qualifier == mapped.original ||
        mapped.original.endsWith('.$qualifier');
  }

  DVRetracedFrame _frameOf(_MappedClass mapped, _Member member, int? line) {
    // An inlined method is a frame of the class it was written in.
    final bool own = _isOwn(mapped, member);
    final String className = own ? mapped.original : member.originalClass!;
    // A frame inlined from another class is in that class's file when the
    // mapping names it, and in the file its name implies when it does not.
    final String file = own
        ? (mapped.sourceFile ?? _fileOf(mapped.original))
        : (_files[className] ?? _fileOf(className));
    final int? original = _originalLine(member, line);
    return DVRetracedFrame(
      className: className,
      methodName: member.originalName,
      fileName: file,
      // R8 writes 0 for "no line information", and a trace shows none.
      line: original != null && original > 0 ? original : null,
    );
  }

  static int? _originalLine(_Member member, int? line) {
    final _Range? original = member.original;
    if (original == null || line == null) return line;
    if (member.originalIsSingleLine) return original.from;
    final _Range? minified = member.minified;
    if (minified == null) return line;
    return original.from + (line - minified.from);
  }

  /// `Outer$Inner` is declared in `Outer.java`; Kotlin's `FooKt` facade is
  /// `Foo.kt`.
  static String _fileOf(String className) {
    final String simple = className.substring(className.lastIndexOf('.') + 1);
    final int dollar = simple.indexOf(r'$');
    final String outer = dollar < 0 ? simple : simple.substring(0, dollar);
    return outer.length > 2 && outer.endsWith('Kt')
        ? '${outer.substring(0, outer.length - 2)}.kt'
        : '$outer.java';
  }

  // `\tat a.a.a.onCreate(SourceFile:2)`
  static final RegExp _frame =
      RegExp(r'^(\s*at\s+)([^\s(]+)\.([^\s.(]+)\(([^)]*)\)\s*$');
  // `Caused by: a.b: message`, `a.b.C: message`, `Suppressed: a.b`
  static final RegExp _exception = RegExp(
      r'^(\s*(?:Caused by:\s+|Suppressed:\s+)?)([A-Za-z_$][\w$]*(?:\.[\w$]+)*)(:.*)?$');

  /// [trace], a Java stack trace, with every class and frame it can retrace
  /// written back as the original.
  String retrace(String trace) {
    if (isEmpty) return trace;
    final StringBuffer out = StringBuffer();
    bool first = true;
    for (final String line in LineSplitterLite.split(trace)) {
      final String? retraced = _retraceLine(line);
      if (retraced == null) continue;
      if (!first) out.write('\n');
      first = false;
      out.write(retraced);
    }
    return out.toString();
  }

  String? _retraceLine(String line) {
    final RegExpMatch? frame = _frame.firstMatch(line);
    if (frame != null) {
      final String where = frame.group(4)!;
      final int? number = int.tryParse(where.split(':').last);
      final List<DVRetracedFrame> frames =
          retraceFrame(frame.group(2)!, frame.group(3)!, number);
      if (frames.length == 1 && frames.single.fileName == null) return line;
      // Every frame was R8's own (a lambda's bridge): nothing of the source.
      if (frames.isEmpty) return null;
      return frames
          .map((DVRetracedFrame f) => '${frame.group(1)}$f')
          .join('\n');
    }
    final RegExpMatch? exception = _exception.firstMatch(line);
    if (exception != null && !line.trimLeft().startsWith('at ')) {
      final String name = exception.group(2)!;
      final String original = originalClass(name);
      if (original == name) return line;
      return '${exception.group(1)}$original${exception.group(3) ?? ''}';
    }
    return line;
  }
}

/// `LineSplitter` without importing `dart:convert` into a file that is
/// otherwise pure string handling, and tolerant of `\r\n`.
abstract final class LineSplitterLite {
  static Iterable<String> split(String text) sync* {
    int start = 0;
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0a) {
        int end = i;
        if (end > start && text.codeUnitAt(end - 1) == 0x0d) end--;
        yield text.substring(start, end);
        start = i + 1;
      }
    }
    if (start < text.length) yield text.substring(start);
  }
}
