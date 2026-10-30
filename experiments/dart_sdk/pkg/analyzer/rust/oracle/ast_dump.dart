// Oracle for the Rust port of the analyzer's syntax tree (see ../README.md).
//
// Parses every `.dart` file under one or more corpus roots with the
// analyzer's `parseString` and writes the whole syntax tree the AstBuilder
// built, followed by the parse diagnostics, in the text format that
// `cargo run --release --bin ast_dump` writes for the Rust port. The two
// outputs are compared byte for byte.
//
// Usage:
//   dart --packages=<package_config.json> \
//     pkg/analyzer/rust/oracle/ast_dump.dart [--bench=N | --retain] \
//     --out <dir> <root>...
//
// The package config is written by tests/ast_oracle.rs (see ../README.md):
// the analyzer's dependencies that are not in this checkout come from the
// pub cache.
//
// Each file is read as UTF-8 (malformed sequences replaced) and parsed with
// `parseString(content: source, throwIfDiagnostics: false)`, which scans with
// the analyzer's `Scanner` and parses with its `Parser` (the upstream parser
// driving an `AstBuilder`) under the latest language version.
//
// The tree is the one the AstBuilder builds (the "V2" view): every node in
// pre-order, as `<child name>: <runtime type> <offset>+<length>`, followed
// by each of its named child entities (`_childEntities2`) in order, tokens as
// `<name>: TYPE@offset"lexeme"` (`~` when synthetic). Node lists and token
// lists print their length and then their elements as `<name>[i]`. Values
// the AstBuilder computes that are not tokens (literal values, a doc
// comment's code blocks, directives and doc imports) follow the node's line
// as `~` lines. The parse diagnostics end the file, in the order reported,
// as `diagnostic <uniqueName>@<offset>+<length>`.
//
// Only `dart:` libraries and package libraries are imported.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/doc_comment.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/src/dart/ast/ast.dart';

void main(List<String> args) {
  String? out;
  int bench = 0;
  bool retain = false;
  List<String> roots = [];
  for (int i = 0; i < args.length; i++) {
    String arg = args[i];
    if (arg.startsWith('--bench=')) {
      bench = int.parse(arg.substring('--bench='.length));
    } else if (arg == '--retain') {
      retain = true;
    } else if (arg == '--out') {
      out = args[++i];
    } else {
      roots.add(arg);
    }
  }
  if (roots.isEmpty || (out == null && bench == 0 && !retain)) {
    stderr.writeln(
      'usage: ast_dump.dart [--bench=N | --retain] --out <dir> <root>...',
    );
    exit(64);
  }

  List<(String, String)> inputs = corpusFiles(roots);

  if (bench > 0) {
    runBench(inputs, bench);
    return;
  }
  if (retain) {
    runRetain(inputs);
    return;
  }

  for (var (String path, String relative) in inputs) {
    String source = readSource(path);
    String dump = dumpFile(source);
    File target = new File('$out/$relative.ast');
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(utf8.encode(dump));
  }
}

String readSource(String path) =>
    utf8.decode(new File(path).readAsBytesSync(), allowMalformed: true);

/// Every `.dart` file under [roots] as (path, label/relative path), sorted
/// by relative path within each root. The label is the root's basename, and
/// a repeated basename gets `~2`, `~3`, ...
List<(String, String)> corpusFiles(List<String> roots) {
  Map<String, int> seen = {};
  List<(String, String)> result = [];
  for (String root in roots) {
    Directory dir = new Directory(root);
    String base = dir.absolute.uri.pathSegments
        .where((s) => s.isNotEmpty)
        .last;
    int count = (seen[base] ?? 0) + 1;
    seen[base] = count;
    String label = count == 1 ? base : '$base~$count';
    String prefix = dir.absolute.path;
    if (!prefix.endsWith('/')) prefix = '$prefix/';
    List<(String, String)> files = [];
    for (FileSystemEntity entity in dir.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && entity.path.endsWith('.dart')) {
        String abs = entity.absolute.path;
        files.add((abs, '$label/${abs.substring(prefix.length)}'));
      }
    }
    files.sort((a, b) => compareBytes(a.$2, b.$2));
    result.addAll(files);
  }
  return result;
}

int compareBytes(String a, String b) {
  List<int> x = utf8.encode(a);
  List<int> y = utf8.encode(b);
  for (int i = 0; i < x.length && i < y.length; i++) {
    if (x[i] != y[i]) return x[i] - y[i];
  }
  return x.length - y.length;
}

String escape(String s) {
  StringBuffer sb = new StringBuffer();
  for (int i = 0; i < s.length; i++) {
    int c = s.codeUnitAt(i);
    if (c >= 0x20 && c < 0x7f && c != 0x5c && c != 0x22) {
      sb.writeCharCode(c);
    } else {
      sb.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
    }
  }
  return sb.toString();
}

String formatToken(Token token) {
  String synthetic = token.isSynthetic ? '~' : '';
  return '${token.type.name}@${token.offset}"${escape(token.lexeme)}"'
      '$synthetic';
}

String dumpFile(String source) {
  StringBuffer sb = new StringBuffer();
  ParseStringResult result;
  try {
    result = parseString(content: source, throwIfDiagnostics: false);
  } catch (e) {
    // The Rust port panics where upstream throws; neither message is
    // compared, only that it happened.
    sb.write('crash\n');
    return sb.toString();
  }
  new AstDumper(sb).node('unit', result.unit as AstNodeImpl, 0);
  for (Diagnostic diagnostic in result.errors) {
    sb.write(
      'diagnostic ${diagnostic.diagnosticCode.uniqueName}'
      '@${diagnostic.offset}+${diagnostic.length}\n',
    );
  }
  return sb.toString();
}

class AstDumper {
  final StringBuffer sb;

  new(this.sb);

  void indent(int depth) {
    for (int i = 0; i < depth; i++) {
      sb.write('  ');
    }
  }

  void node(String name, AstNodeImpl node, int depth) {
    indent(depth);
    sb.write('$name: ${node.runtimeType} ${node.offset}+${node.length}\n');
    extras(node, depth + 1);
    for (ChildEntity child in node.namedChildEntities2) {
      Object value = child.value;
      if (value is AstNodeImpl) {
        this.node(child.name, value, depth + 1);
      } else if (value is Token) {
        indent(depth + 1);
        sb.write('${child.name}: ${formatToken(value)}\n');
      } else if (value is List) {
        indent(depth + 1);
        sb.write('${child.name}: [${value.length}]\n');
        for (int i = 0; i < value.length; i++) {
          Object element = value[i] as Object;
          if (element is AstNodeImpl) {
            this.node('${child.name}[$i]', element, depth + 2);
          } else {
            indent(depth + 2);
            sb.write('${child.name}[$i]: ${formatToken(element as Token)}\n');
          }
        }
      } else {
        throw new StateError('unexpected child entity ${value.runtimeType}');
      }
    }
  }

  void line(int depth, String text) {
    indent(depth);
    sb.write('~$text\n');
  }

  void extras(AstNodeImpl node, int depth) {
    switch (node) {
      case SimpleStringLiteralImpl():
        line(depth, 'value "${escape(node.value)}"');
      case InterpolationStringImpl():
        line(depth, 'value "${escape(node.value)}"');
      case IntegerLiteralImpl():
        line(depth, 'value ${node.value ?? '-'}');
      case DoubleLiteralImpl():
        line(depth, 'value ${node.value}');
      case CommentReferenceImpl():
        line(depth, 'isSynthetic ${node.isSynthetic}');
      case CommentImpl():
        line(depth, 'hasNodoc ${node.hasNodoc}');
        for (MdCodeBlock block in node.codeBlocks) {
          String info = block.infoString == null
              ? '-'
              : '"${escape(block.infoString!)}"';
          String lines = [
            for (MdCodeBlockLine l in block.lines) '${l.offset}+${l.length}',
          ].join(' ');
          line(depth, 'codeBlock ${block.type.name} $info [$lines]');
        }
        for (DocDirective directive in node.docDirectives) {
          switch (directive) {
            case SimpleDocDirective():
              line(depth, 'docDirective simple ${tag(directive.tag)}');
            case BlockDocDirective():
              String closing = directive.closingTag == null
                  ? '-'
                  : tag(directive.closingTag!);
              line(
                depth,
                'docDirective block ${tag(directive.openingTag)} $closing',
              );
          }
        }
        for (DocImport docImport in node.docImports) {
          line(depth, 'docImport ${docImport.offset}');
          this.node('import', docImport.import as AstNodeImpl, depth + 1);
        }
      default:
    }
  }

  String tag(DocDirectiveTag tag) {
    String argument(DocDirectiveArgument a) =>
        '"${escape(a.value)}"@${a.offset}-${a.end}';
    String positional = [
      for (DocDirectiveArgument a in tag.positionalArguments) argument(a),
    ].join(' ');
    String named = [
      for (DocDirectiveNamedArgument a in tag.namedArguments)
        '${a.name}=${argument(a)}',
    ].join(' ');
    return '${tag.type.name}@${tag.offset}-${tag.end}'
        '(${tag.nameOffset}-${tag.nameEnd})[$positional][$named]';
  }
}

/// Reads every file once, then parses the sources [rounds] times, timing
/// scanning and building the tree (`parseString`) and nothing else.
void runBench(List<(String, String)> inputs, int rounds) {
  List<String> sources = [
    for (var (String path, _) in inputs) readSource(path),
  ];
  int totalBytes = 0;
  for (var (String path, _) in inputs) {
    totalBytes += new File(path).lengthSync();
  }
  Stopwatch watch = new Stopwatch();
  List<int> times = [];
  int nodes = 0;
  for (int round = 0; round < rounds; round++) {
    watch
      ..reset()
      ..start();
    for (String source in sources) {
      ParseStringResult result = parseString(
        content: source,
        throwIfDiagnostics: false,
      );
      nodes += result.unit.endToken.offset & 1;
    }
    watch.stop();
    times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  stdout.writeln(
    'dart ast files=${sources.length} bytes=$totalBytes rounds=$rounds '
    'min_us=${times.first} median_us=${times[times.length ~/ 2]} '
    'check=$nodes max_rss=${ProcessInfo.maxRss}',
  );
}

/// Reads every file, then parses them all once and keeps every result (the
/// tokens, the tree and the diagnostics), printing the resident set size
/// before and after parsing: the memory the parsed corpus takes.
void runRetain(List<(String, String)> inputs) {
  List<String> sources = [
    for (var (String path, _) in inputs) readSource(path),
  ];
  int before = ProcessInfo.currentRss;
  List<ParseStringResult> results = [
    for (String source in sources)
      parseString(content: source, throwIfDiagnostics: false),
  ];
  int after = ProcessInfo.currentRss;
  stdout.writeln(
    'dart retain files=${results.length} rss_sources=$before '
    'rss_parsed=$after delta=${after - before} max_rss=${ProcessInfo.maxRss}',
  );
}
