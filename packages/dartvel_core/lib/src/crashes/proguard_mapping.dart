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
    required this.minified,
    required this.original,
    required this.originalIsSingleLine,
  });

  final String originalName;
  final _Range? minified;
  final _Range? original;

  /// `:30` rather than `:30:34`: every minified line in the range is line 30.
  final bool originalIsSingleLine;
}

class _MappedClass {
  _MappedClass(this.original);
  final String original;
  String? sourceFile;

  /// Members by minified name, in file order: for one minified range, the
  /// order is an inlining chain, innermost first.
  final Map<String, List<_Member>> members = <String, List<_Member>>{};
}

/// A parsed mapping.
class DVProguardMapping {
  DVProguardMapping._(this._classes);

  final Map<String, _MappedClass> _classes;

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
        continue;
      }
      final RegExpMatch? match = _methodLine.firstMatch(raw);
      if (match == null) continue;
      final String? minStart = match.group(1);
      final String? minEnd = match.group(2);
      final String? origStart = match.group(5);
      final String? origEnd = match.group(6);
      current.members
          .putIfAbsent(match.group(7)!, () => <_Member>[])
          .add(_Member(
            originalName: match.group(3)!,
            minified: minStart == null
                ? null
                : _Range(int.parse(minStart), int.parse(minEnd!)),
            original: origStart == null
                ? null
                : _Range(int.parse(origStart),
                    int.parse(origEnd ?? origStart)),
            originalIsSingleLine: origStart != null && origEnd == null,
          ));
    }
    return DVProguardMapping._(classes);
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
    return <DVRetracedFrame>[
      for (final _Member member in matching)
        if (!anyRanged || member.minified != null)
          DVRetracedFrame(
            className: mapped.original,
            methodName: member.originalName,
            fileName: file,
            line: _originalLine(member, line),
          ),
    ];
  }

  static int? _originalLine(_Member member, int? line) {
    final _Range? original = member.original;
    if (original == null || line == null) return line;
    if (member.originalIsSingleLine) return original.from;
    final _Range? minified = member.minified;
    if (minified == null) return line;
    return original.from + (line - minified.from);
  }

  /// `Outer$Inner` is declared in `Outer.java`.
  static String _fileOf(String className) {
    final String simple = className.substring(className.lastIndexOf('.') + 1);
    final int dollar = simple.indexOf(r'$');
    return '${dollar < 0 ? simple : simple.substring(0, dollar)}.java';
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
    final List<String> lines = LineSplitterLite.split(trace).toList();
    for (int i = 0; i < lines.length; i++) {
      if (i > 0) out.write('\n');
      out.write(_retraceLine(lines[i]));
    }
    return out.toString();
  }

  String _retraceLine(String line) {
    final RegExpMatch? frame = _frame.firstMatch(line);
    if (frame != null) {
      final String where = frame.group(4)!;
      final int? number = int.tryParse(where.split(':').last);
      final List<DVRetracedFrame> frames =
          retraceFrame(frame.group(2)!, frame.group(3)!, number);
      if (frames.length == 1 && frames.single.fileName == null) return line;
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
