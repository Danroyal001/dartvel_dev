import 'package:flutter/material.dart';

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

  /// Scan [source] into coloured spans.
  static List<TextSpan> spans(String source) {
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
