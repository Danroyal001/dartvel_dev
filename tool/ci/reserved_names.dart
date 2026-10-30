/// Names the specification closed, and how to find a use of one.
///
/// The check that runs this over the tree is `reserved_names_check.dart`;
/// the reasons for each closed set are written there.
library;

/// A reserved name, and why.
typedef DVReserved = (String name, String because);

/// One use of a reserved name in Dart source.
typedef DVReservedUse = ({int line, String name, String because});

const List<DVReserved> dvReservedNames = <DVReserved>[
  // A second namespace for what DV.Modules already is.
  (
    'DVModuleManager',
    'DV.Modules is the surface; a manager beside it is a '
        'second name for one concept',
  ),
  (
    'DVBindingManager',
    'bindings are internal machinery beneath modules and '
        'have no manager an application names',
  ),
  (
    'DVBindings',
    'internal means internal; a public DV.Bindings would make a '
        'binding a thing developers manage',
  ),
  ('DVIntegrations', 'an integration is a module'),
  (
    'DVPackages',
    'a package is a package; what an application composes is a '
        'module',
  ),
  (
    'DVPlugins',
    'Dartvel has no plugin tier, which is the whole point of '
        'having one composition unit',
  ),
  // Per-language and per-platform binding classes.
  ('DVSwiftBinding', 'Swift reaches Dart across the C ABI: DVFfiBinding'),
  ('DVRustBinding', 'Rust reaches Dart across the C ABI: DVFfiBinding'),
  ('DVKotlinBinding', 'Kotlin is reached through the JVM: DVJniBinding'),
  ('DVObjCBinding', 'Objective-C reaches Dart across the C ABI: DVFfiBinding'),
  ('DVAppleBinding', 'a target is not a binding kind: DVFfiBinding'),
  ('DVWindowsBinding', 'a target is not a binding kind: DVFfiBinding'),
  ('DVLinuxBinding', 'a target is not a binding kind: DVFfiBinding'),
  (
    'DVAndroidBinding',
    'a target is not a binding kind: DVJniBinding or '
        'DVFfiBinding, and an Android module may carry both',
  ),
  ('DVJvmBinding', 'JNI is the boundary being crossed, so DVJniBinding'),
];

const String _channelBecause =
    'is a Flutter platform channel. Dartvel binds '
    'natively through generated FFI/ffigen and JNI/jnigen.';

/// Flutter's platform channels, which Dartvel never uses.
const List<DVReserved> dvPlatformChannels = <DVReserved>[
  ('MethodChannel', _channelBecause),
  ('EventChannel', _channelBecause),
  ('BasicMessageChannel', _channelBecause),
];

/// Every use of a reserved name or a platform channel in [source].
///
/// A use is a name in code. Comments and the text of string literals are
/// prose -- a docs page saying no `MethodChannel` is used, the pattern the
/// conventions check finds one with, a test asserting generated Java has none
/// -- and naming what the rule forbids is how the rule is kept. An
/// interpolated expression inside a string is code again.
List<DVReservedUse> dvReservedNameUses(String source) {
  final List<DVReservedUse> uses = <DVReservedUse>[];
  final List<String> lines = dvDartCodeOnly(source).split('\n');
  for (int i = 0; i < lines.length; i++) {
    final String code = lines[i];
    if (code.trim().isEmpty) continue;
    for (final DVReserved name in <DVReserved>[
      ...dvReservedNames,
      ...dvPlatformChannels,
    ]) {
      if (!RegExp('\\b${name.$1}\\b').hasMatch(code)) continue;
      uses.add((line: i + 1, name: name.$1, because: name.$2));
    }
  }
  return uses;
}

/// [source] with every comment and the text of every string literal replaced
/// by spaces, line breaks kept so line numbers still hold. Interpolated
/// expressions (`${...}` and `$name`) stay, because they are code.
String dvDartCodeOnly(String source) => _DartBlanker(source).run();

final class _DartBlanker {
  _DartBlanker(this.source) : out = source.split('');

  final String source;
  final List<String> out;
  int i = 0;

  String run() {
    _code(untilBrace: false);
    return out.join();
  }

  bool _at(String s) => source.startsWith(s, i);

  void _blank(int from, int to) {
    for (int k = from; k < to && k < out.length; k++) {
      if (out[k] != '\n') out[k] = ' ';
    }
  }

  static bool _isIdent(String c) => RegExp(r'[A-Za-z0-9_$]').hasMatch(c);

  void _code({required bool untilBrace}) {
    int depth = 0;
    while (i < source.length) {
      final String c = source[i];
      if (_at('//')) {
        final int end = source.indexOf('\n', i);
        final int stop = end < 0 ? source.length : end;
        _blank(i, stop);
        i = stop;
      } else if (_at('/*')) {
        _blockComment();
      } else if (c == '{') {
        depth++;
        i++;
      } else if (c == '}') {
        if (untilBrace && depth == 0) {
          i++;
          return;
        }
        depth--;
        i++;
      } else if (c == "'" || c == '"') {
        _string(raw: false);
      } else if (c == 'r' &&
          i + 1 < source.length &&
          (source[i + 1] == "'" || source[i + 1] == '"') &&
          (i == 0 || !_isIdent(source[i - 1]))) {
        i++;
        _string(raw: true);
      } else {
        i++;
      }
    }
  }

  void _blockComment() {
    final int start = i;
    int depth = 0;
    while (i < source.length) {
      if (_at('/*')) {
        depth++;
        i += 2;
      } else if (_at('*/')) {
        depth--;
        i += 2;
        if (depth == 0) break;
      } else {
        i++;
      }
    }
    _blank(start, i);
  }

  void _string({required bool raw}) {
    final String q = source[i];
    final String quote = _at('$q$q$q') ? '$q$q$q' : q;
    i += quote.length;
    int textStart = i;
    while (i < source.length) {
      if (_at(quote)) {
        _blank(textStart, i);
        i += quote.length;
        return;
      }
      final String c = source[i];
      if (quote.length == 1 && c == '\n') {
        // An unterminated single-line string: stop at the line end.
        _blank(textStart, i);
        return;
      }
      if (!raw && c == r'\') {
        i += 2;
      } else if (!raw && _at(r'${')) {
        _blank(textStart, i);
        i += 2;
        _code(untilBrace: true);
        textStart = i;
      } else if (!raw &&
          c == r'$' &&
          i + 1 < source.length &&
          RegExp(r'[A-Za-z_]').hasMatch(source[i + 1])) {
        _blank(textStart, i);
        i++;
        while (i < source.length &&
            RegExp(r'[A-Za-z0-9_]').hasMatch(source[i])) {
          i++;
        }
        textStart = i;
      } else {
        i++;
      }
    }
    _blank(textStart, i);
  }
}
