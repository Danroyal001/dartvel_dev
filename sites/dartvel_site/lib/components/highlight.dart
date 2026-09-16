import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';
import 'site.dart';

/// Colouring Dart, because on a framework's site the code is the demo.
///
/// Every sample here was one colour on navy, which is the same amount of
/// information as a screenshot of a wall. Annotations are the whole argument
/// of a page about annotations, and they read as ordinary text.
///
/// Small on purpose. This is not an analyser: it is a scanner that knows the
/// six things worth telling apart in a twelve-line sample, and it never has to
/// be right about code it is not shown.
class Code {
  const Code._();

  /// Words Dart reserves, plus the ones that carry meaning in these samples.
  static const Set<String> _keywords = <String>{
    'abstract', 'as', 'async', 'await', 'break', 'case', 'catch', 'class',
    'const', 'continue', 'covariant', 'default', 'deferred', 'do', 'dynamic',
    'else', 'enum', 'export', 'extends', 'extension', 'external', 'factory',
    'false', 'final', 'finally', 'for', 'get', 'if', 'implements', 'import',
    'in', 'interface', 'is', 'late', 'library', 'mixin', 'new', 'null', 'on',
    'operator', 'part', 'required', 'rethrow', 'return', 'sealed', 'set',
    'show', 'static', 'super', 'switch', 'sync', 'this', 'throw', 'true',
    'try', 'typedef', 'var', 'void', 'while', 'with', 'yield',
  };

  /// Types common enough in these samples to be worth a colour.
  static const Set<String> _types = <String>{
    'bool', 'double', 'int', 'num', 'String', 'List', 'Map', 'Set', 'Future',
    'Stream', 'Widget', 'BuildContext', 'Object', 'Iterable', 'Duration',
    'DateTime', 'Uri',
  };

  /// A Tokyo-Night-ish palette: it sits on the navy these blocks already use
  /// and keeps enough contrast for the dim comment colour to still be
  /// readable, which is where most code themes fail.
  static const Color _plain = Color(0xFFC0CAF5);
  static const Color _comment = Color(0xFF7080A8);
  static const Color _string = Color(0xFF9ECE6A);
  static const Color _keyword = Color(0xFFBB9AF7);
  static const Color _type = Color(0xFF7DCFFF);
  static const Color _annotation = Color(0xFFE0AF68);
  static const Color _number = Color(0xFFFF9E64);
  static const Color _call = Color(0xFF7AA2F7);

  /// What a terminal prints back, dimmer than what you type into it.
  static const Color _output = Color(0xFF9AA5CE);

  /// The first words that make a line a command someone types.
  static const Set<String> _commands = <String>{
    'dartvel', 'brew', 'cd', 'flutter', 'dart', 'npm', 'npx', 'curl', 'scp',
    'ssh', 'git', 'export', 'sudo', 'docker', 'cp', 'mkdir', 'chmod',
  };

  /// Whether [source] is a terminal session rather than Dart.
  ///
  /// A line at a `$ ` prompt makes it one. So does a block where every line
  /// is a comment or starts with a command: the install block has no prompt,
  /// and through the Dart scanner "Danroyal001" was coloured as a type.
  static bool isSession(String source) {
    final List<String> lines = <String>[
      for (final String line in source.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (lines.any((String line) => line.startsWith(r'$ '))) return true;
    final List<String> commands = <String>[
      for (final String line in lines)
        if (!line.startsWith('#')) line,
    ];
    return commands.isNotEmpty &&
        commands.every((String line) =>
            _commands.contains(line.split(RegExp(r'\s+')).first));
  }

  /// A terminal session: the prompt, what is typed, what is printed back,
  /// and comments. None of Dart's rules apply, so a URL's `//` is part of the
  /// URL and "on" in a sentence is a word.
  static List<TextSpan> _session(String source) {
    final bool prompted = source
        .split('\n')
        .any((String line) => line.trimLeft().startsWith(r'$ '));
    final List<TextSpan> out = <TextSpan>[];
    final List<String> lines = source.split('\n');
    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];
      final String newline = i + 1 < lines.length ? '\n' : '';
      if (line.trimLeft().startsWith('#')) {
        out.add(TextSpan(
            text: '$line$newline', style: const TextStyle(color: _comment)));
        continue;
      }
      final bool typed = !prompted || line.trimLeft().startsWith(r'$ ');
      if (!typed) {
        out.add(TextSpan(
            text: '$line$newline', style: const TextStyle(color: _output)));
        continue;
      }
      if (line.trimLeft().startsWith(r'$ ')) {
        final int at = line.indexOf(r'$ ');
        out.add(TextSpan(
            text: line.substring(0, at + 2),
            style: const TextStyle(color: _string)));
        line = line.substring(at + 2);
      }
      final int hash = line.indexOf(RegExp(r'\s#'));
      out.add(TextSpan(
          text: hash < 0 ? line : line.substring(0, hash),
          style: const TextStyle(color: _plain)));
      if (hash >= 0) {
        out.add(TextSpan(
            text: line.substring(hash), style: const TextStyle(color: _comment)));
      }
      if (newline.isNotEmpty) {
        out.add(const TextSpan(text: '\n'));
      }
    }
    return out;
  }

  /// Scan [source] into coloured spans.
  static List<TextSpan> spans(String source) {
    if (isSession(source)) return _session(source);
    final List<TextSpan> out = <TextSpan>[];
    final StringBuffer plain = StringBuffer();

    void flush() {
      if (plain.isEmpty) return;
      out.add(TextSpan(text: plain.toString(),
          style: const TextStyle(color: _plain)));
      plain.clear();
    }

    void emit(String text, Color colour) {
      flush();
      out.add(TextSpan(text: text, style: TextStyle(color: colour)));
    }

    var i = 0;
    while (i < source.length) {
      final String c = source[i];

      // A comment runs to the end of its line, and everything in it is a
      // comment -- including quotes, which is why this is checked first.
      if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
        final int end = source.indexOf('\n', i);
        final int stop = end == -1 ? source.length : end;
        emit(source.substring(i, stop), _comment);
        i = stop;
        continue;
      }

      // A string, to its closing quote of the same kind. An unterminated one
      // runs to the end rather than throwing: a sample is often a fragment.
      if (c == "'" || c == '"') {
        var j = i + 1;
        while (j < source.length && source[j] != c) {
          if (source[j] == r'\' && j + 1 < source.length) j++;
          j++;
        }
        final int stop = j < source.length ? j + 1 : source.length;
        emit(source.substring(i, stop), _string);
        i = stop;
        continue;
      }

      // An annotation, which is what most of these samples are about.
      if (c == '@') {
        var j = i + 1;
        while (j < source.length && _isWord(source[j])) {
          j++;
        }
        emit(source.substring(i, j), _annotation);
        i = j;
        continue;
      }

      if (_isDigit(c)) {
        var j = i;
        while (j < source.length &&
            (_isDigit(source[j]) || source[j] == '.' || source[j] == 'x')) {
          j++;
        }
        emit(source.substring(i, j), _number);
        i = j;
        continue;
      }

      if (_isWordStart(c)) {
        var j = i;
        while (j < source.length && _isWord(source[j])) {
          j++;
        }
        final String word = source.substring(i, j);
        if (_keywords.contains(word)) {
          emit(word, _keyword);
        } else if (_types.contains(word) || _looksLikeType(word)) {
          emit(word, _type);
        } else if (j < source.length && source[j] == '(') {
          // Called, so it is a function or a constructor. Worth its own
          // colour: these samples are mostly calls.
          emit(word, _call);
        } else {
          plain.write(word);
        }
        i = j;
        continue;
      }

      plain.write(c);
      i++;
    }

    flush();
    return out;
  }

  /// `DVBox` and `Post` are types; `dartvel` and `title` are not.
  ///
  /// Capitalisation is the convention Dart actually follows, and in a sample
  /// it is right often enough to be worth using. A wrong guess colours a word
  /// slightly differently, which is the cheapest possible mistake.
  static bool _looksLikeType(String word) =>
      word.length > 1 &&
      word[0].toUpperCase() == word[0] &&
      word[0].toLowerCase() != word[0];

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  static bool _isWordStart(String c) {
    final int code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        c == '_' || c == r'$';
  }

  static bool _isWord(String c) => _isWordStart(c) || _isDigit(c);
}


/// A block of code: coloured, monospaced, selectable, and copyable.
///
/// The copy button goes through `DV.Platform.clipboard`, which is bound by
/// FFI on the desktops, JNI on Android and the browser clipboard API on web --
/// no Flutter platform channel anywhere. A framework's own site reaching for
/// one would be the clearest possible argument that the rule is unworkable.
@DVFunctionalWidget()
Widget _codeSample(BuildContext context, List<String> lines) {
  final String source = lines.join('\n');
  final DVSignal<bool> copied = context.signal(false);

  return DVBox(
    // The Copy button's corner is kept clear of the code. Stacked straight
    // over the text, a first line that reached the right edge ran under the
    // button on every phone. Beside the code where the block is wide, and
    // above it where it is narrow, since a gutter on a phone would wrap
    // every line.
    LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
      final bool narrow = box.maxWidth < 560;
      return DVBox.stack(<Widget>[
      Padding(
        padding: narrow
            ? const EdgeInsets.only(top: 52)
            : const EdgeInsets.only(right: 80),
        child:
      // Labelled, because Flutter renders SelectableText as a textarea whose
      // value it manages: without this the code is absent from the semantics
      // tree entirely, so a crawler never sees the install commands and a
      // screen reader never reads them.
      Semantics(
        identifier: 'dartvel:code',
        label: source,
        excludeSemantics: true,
        child: SelectableText.rich(
          TextSpan(children: Code.spans(source)),
          style: const TextStyle(
            // Bundled, not named. Flutter web cannot resolve the generic
            // "monospace" family and silently falls back to the body font, so
            // every Dart sample on this site rendered in proportional text --
            // on a page whose whole argument is what the code looks like.
            fontFamily: 'RobotoMono',
            fontFamilyFallback: <String>['Menlo', 'Consolas', 'monospace'],
            fontSize: 13.5,
            height: 1.65,
          ),
        ),
      ),
      ),
      DVBox(
        CopyButton(source, copied),
        const DVModifier().align(Alignment.topRight),
      ),
      ]);
    }),
    const DVModifier()
        .width(double.infinity)
        .maxWidth(680)
        .padding(18)
        .backgroundColor(Palette.of(context).dark
            ? const Color(0xFF0E141D)
            : const Color(0xFF0B1020))
        .rounded(10),
  );
}

/// The copy affordance itself.
///
/// [copied] is the caller's signal rather than one of its own, so the label
/// belongs to the block being copied: two blocks on a page must not both say
/// "Copied" because one of them was.
@DVFunctionalWidget()
Widget _copyButton(BuildContext context, String source, DVSignal<bool> copied) {
  final bool done = copied.value;
  return DVBox(
    DVText(done ? 'Copied' : 'Copy').modifier(
      const DVModifier()
          .fontSize(12)
          .fontWeight(FontWeight.w600)
          .color(done ? const Color(0xFF9ECE6A) : const Color(0xFF7080A8)),
    ),
    const DVModifier()
        .paddingSymmetric(horizontal: 10, vertical: 6)
        .rounded(6)
        .border(Border.all(color: const Color(0xFF222A38)))
        .animate(const Duration(milliseconds: 140))
        .hover(const DVModifier().backgroundColor(const Color(0xFF161E33)))
        .semanticLabel(done ? 'Code copied' : 'Copy code to clipboard')
        .semanticButton()
        // 44 square is the smallest target a finger reliably hits, and a
        // 12pt label is nowhere near it.
        .minimumTapTarget()
        .onTap(() async {
          // Not silent on failure. A browser refuses the clipboard outside a
          // secure context, and a button that appears to work and does not is
          // worse than one that says so.
          try {
            await DV.Platform.clipboard.copy(source);
            copied.value = true;
          } on Object {
            copied.value = false;
          }
        }),
  );
}
