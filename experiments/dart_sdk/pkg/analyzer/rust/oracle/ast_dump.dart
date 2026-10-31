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
//     pkg/analyzer/rust/oracle/ast_dump.dart [--api] [--bench=N | --retain] \
//     --out <dir> <root>...
//
// `--api` writes the API dump (see dumpApi below) instead of the tree; with
// `--bench=N` it times `toSource` of every unit instead of parsing.
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
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/ast/utilities.dart';

import 'ast_api_recorders.g.dart';

void main(List<String> args) {
  String? out;
  int bench = 0;
  bool retain = false;
  bool api = false;
  bool walk = false;
  List<String> roots = [];
  for (int i = 0; i < args.length; i++) {
    String arg = args[i];
    if (arg.startsWith('--bench=')) {
      bench = int.parse(arg.substring('--bench='.length));
    } else if (arg == '--api') {
      api = true;
    } else if (arg == '--walk') {
      walk = true;
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
      'usage: ast_dump.dart [--api] [--bench=N | --retain] --out| --retain] --out <dir> <root>...',
    );
    exit(64);
  }

  List<(String, String)> inputs = corpusFiles(roots);

  if (bench > 0 && walk) {
    runWalkBench(inputs, bench);
    return;
  }
  if (bench > 0 && api) {
    runToSourceBench(inputs, bench);
    return;
  }
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
    String dump = api ? dumpApi(source) : dumpFile(source);
    File target = new File('$out/$relative.${api ? 'api' : 'ast'}');
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

// ---------------------------------------------------------------------------
// The API oracle (`--api`): what the public AST API returns on the tree.
//
// Every node is numbered in the pre-order of the tree dump (the named child
// entities). The dump of a file is:
//
//   toSource "<the unit's toSource>"
//   node <i> <runtime type> v=<visit method> p=<parent2> s=<toSource>
//     ... one line per node; `v` is the AstVisitor2 method `accept2` calls,
//     `p` the number of `parent2` (`-` for null, `?<type>` for a node that
//     is not numbered), `s` the node's toSource, quoted when at most 60
//     code units long and `#<length>:<FNV-1a 64 of the code units>`
//     otherwise.
//   recursive <visits>   the nodes a RecursiveAstVisitor2 visits from the
//                        unit, in order
//   unifying <visits>    the same for UnifyingAstVisitor2.visitNode
//   delegating <visits>  the visits of a SimpleAstVisitor2 delegate of a
//                        DelegatingAstVisitor2
//   locate <a>-<b> <n>   NodeLocator2(a, b).searchWithin(unit) at offsets
//                        drawn from a generator seeded by the file length
//   diagnostic <uniqueName>@<offset>+<length> "<message>" "<correction>"
//   cover <a>-<b> <n>    unit.nodeCovering2(offset: a, length: b - a)
//   timed2 <visits>      a RecursiveAstVisitor2 behind a TimedAstVisitor2
//   replace <i> <j> <r>  a fresh parse's node i replaced by node j (the next
//                        node of the same type outside i's parent's subtree
//                        and ancestors) in its parent2: `r` is the parent's
//                        toSource and then the parent2 of j and of i, or
//                        the error thrown (`!ArgumentError:<message>`, ...)
//   remove <i> <r>       node i of a fresh parse removed from its parent2:
//                        the parent's toSource, or the error thrown
//
// The V1 view follows. Its nodes are numbered in the pre-order of the V1
// named child entities (`namedChildEntities`), walked once from the unit
// before anything else is asked of the view, which links the V1 parents:
//
//   v1node <j> <runtime type> <offset>+<length> v=<visit method> p=<parent>
//     r=<root> w=<the node's number in the V2 view, or -> s=<toSource>
//     c=<the named child entities: name@offset for a token, name#j for a
//     node, name[n] then the elements for a list>
//   v1recursive, v1generalizing, v1unifying, v1delegating <visits>
//                        as above, for RecursiveAstVisitor,
//                        GeneralizingAstVisitor (every visit method each
//                        node goes through), UnifyingAstVisitor and a
//                        SimpleAstVisitor delegate of DelegatingAstVisitor
//   v1breadth <visits>   BreadthFirstVisitor.visitAllNodes(unit)
//   v1timed <visits>     a RecursiveAstVisitor behind a TimedAstVisitor
//   v1locate <a>-<b> <n> NodeLocator(a, b).searchWithin(unit)
//   v1cover <a>-<b> <n>  unit.nodeCovering(offset: a, length: b - a)
//   v1replace <j> <k> <r> V1 node j of a fresh parse replaced by V1 node k
//                        (chosen as for `replace`) in its V1 parent, as
//                        for `replace` with V1 numbers
//
// A visit list is node numbers, `<i>:<method>` when the method is not the
// node's `v`, with runs of consecutive numbers as `<a>-<b>`. Anything that
// throws prints `!throw` in place of its value.
// ---------------------------------------------------------------------------

String guard(String Function() f) {
  try {
    return f();
  } catch (_) {
    return '!throw';
  }
}

/// [guard], naming the error: `!<class>:<message>` for the errors whose
/// messages upstream writes, `!TypeError` for a failed cast.
String guardError(String Function() f) {
  try {
    return f();
  } on ArgumentError catch (e) {
    return '!ArgumentError:${escape('${e.message}')}';
  } on UnsupportedError catch (e) {
    return '!UnsupportedError:${escape('${e.message}')}';
  } on StateError catch (e) {
    return '!StateError:${escape(e.message)}';
  } on TypeError {
    return '!TypeError';
  } catch (_) {
    return '!throw';
  }
}

String fnv(String s) {
  int h = 0xcbf29ce484222325;
  for (int i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h *= 0x100000001b3;
  }
  return '${(h >>> 32).toRadixString(16).padLeft(8, '0')}'
      '${(h & 0xffffffff).toRadixString(16).padLeft(8, '0')}';
}

String summary(String s) =>
    s.length <= 60 ? '"${escape(s)}"' : '#${s.length}:${fnv(s)}';

class UnifyingRecorder1 extends UnifyingAstVisitor<void> {
  final void Function(String, AstNode) log;

  UnifyingRecorder1(this.log);

  @override
  void visitNode(AstNode node) {
    log('visitNode', node);
    super.visitNode(node);
  }
}

class BreadthFirstRecorder extends BreadthFirstVisitor<void> {
  final void Function(String, AstNode) log;

  BreadthFirstRecorder(this.log);

  @override
  void visitNode(AstNode node) {
    log('visitNode', node);
    super.visitNode(node);
  }
}

class UnifyingRecorder extends UnifyingAstVisitor2<void> {
  final void Function(String, AstNode) log;

  UnifyingRecorder(this.log);

  @override
  void visitNode(AstNode node) {
    log('visitNode', node);
    super.visitNode(node);
  }
}

/// Number of every node: the pre-order of the named child entities.
List<AstNodeImpl> numberNodes(AstNodeImpl unit) {
  List<AstNodeImpl> nodes = [];
  void visit(AstNodeImpl node) {
    nodes.add(node);
    for (ChildEntity child in node.namedChildEntities2) {
      Object value = child.value;
      if (value is AstNodeImpl) {
        visit(value);
      } else if (value is List) {
        for (Object? element in value) {
          if (element is AstNodeImpl) visit(element);
        }
      }
    }
  }

  visit(unit);
  return nodes;
}

/// Number of every node of the V1 view: the pre-order of the V1 named child
/// entities.
List<AstNodeImpl> numberNodes1(AstNodeImpl unit) {
  List<AstNodeImpl> nodes = [];
  void visit(AstNodeImpl node) {
    nodes.add(node);
    for (ChildEntity child in node.namedChildEntities) {
      Object value = child.value;
      if (value is AstNodeImpl) {
        visit(value);
      } else if (value is List) {
        for (Object? element in value) {
          if (element is AstNodeImpl) visit(element);
        }
      }
    }
  }

  visit(unit);
  return nodes;
}

/// The number of [node] in [nodes], as `ref` writes it.
String refIn(List<AstNodeImpl> nodes, AstNode? node) {
  if (node == null) return '-';
  for (int i = 0; i < nodes.length; i++) {
    if (identical(nodes[i], node)) return '$i';
  }
  return '?${node.runtimeType}';
}

/// The node after [i] in [nodes] (cyclically) with the runtime type of node
/// [i] that is neither [parent] or one of its ancestors nor in [parent]'s
/// subtree in the view [parentOf] walks, or null: one that cannot make the
/// tree a cycle.
int? replacementFor(
  List<AstNodeImpl> nodes,
  int i,
  AstNode parent,
  AstNode? Function(AstNode) parentOf,
) {
  Set<AstNode> ancestors = new Set.identity();
  for (AstNode? p = parent; p != null; p = parentOf(p)) {
    ancestors.add(p);
  }
  bool inParent(AstNode node) {
    for (AstNode? p = node; p != null; p = parentOf(p)) {
      if (identical(p, parent)) return true;
    }
    return false;
  }

  for (int k = 1; k < nodes.length; k++) {
    int j = (i + k) % nodes.length;
    if (nodes[j].runtimeType == nodes[i].runtimeType &&
        !ancestors.contains(nodes[j]) &&
        !inParent(nodes[j])) {
      return j;
    }
  }
  return null;
}

String dumpApi(String source) {
  StringBuffer sb = new StringBuffer();
  ParseStringResult result;
  try {
    result = parseString(content: source, throwIfDiagnostics: false);
  } catch (e) {
    sb.write('crash\n');
    return sb.toString();
  }
  AstNodeImpl unit = result.unit as AstNodeImpl;
  List<AstNodeImpl> nodes = numberNodes(unit);
  Map<AstNode, int> index = new Map.identity();
  for (int i = 0; i < nodes.length; i++) {
    index[nodes[i]] = i;
  }
  String ref(AstNode? node) {
    if (node == null) return '-';
    int? i = index[node];
    return i == null ? '?${node.runtimeType}' : '$i';
  }

  sb.write('toSource ${guard(() => '"${escape(unit.toSource())}"')}\n');
  List<String> dispatch = [];
  for (int i = 0; i < nodes.length; i++) {
    AstNodeImpl node = nodes[i];
    String v = guard(() {
      String name = '-';
      node.accept2(new SimpleRecorder((String visit, _) => name = visit));
      return name;
    });
    dispatch.add(v);
    String p = guard(() => ref(node.parent2));
    String s = guard(() => summary(node.toSource()));
    sb.write('node $i ${node.runtimeType} v=$v p=$p s=$s\n');
  }

  String visits(void Function(void Function(String, AstNode)) run) {
    List<String> entries = [];
    int? runStart;
    int? runEnd;
    void flush() {
      if (runStart != null) {
        entries.add(runStart == runEnd ? '$runStart' : '$runStart-$runEnd');
        runStart = null;
      }
    }

    void log(String visit, AstNode node) {
      int? i = index[node];
      if (i != null && (visit == 'visitNode' || visit == dispatch[i])) {
        if (runStart != null && runEnd! + 1 == i) {
          runEnd = i;
          return;
        }
        flush();
        runStart = i;
        runEnd = i;
        return;
      }
      flush();
      entries.add('${i ?? '?${node.runtimeType}'}:$visit');
    }

    try {
      run(log);
    } catch (_) {
      flush();
      entries.add('!throw');
    }
    flush();
    return entries.join(' ');
  }

  sb.write(
    'recursive ${visits((log) => unit.accept2(new RecursiveRecorder(log)))}\n',
  );
  sb.write(
    'unifying ${visits((log) => unit.accept2(new UnifyingRecorder(log)))}\n',
  );
  sb.write(
    'delegating ${visits((log) => unit.accept2(new DelegatingAstVisitor2<void>([new SimpleRecorder(log)])))}\n',
  );

  int length = source.length;
  int seed = length;
  int next() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed;
  }

  for (int k = 0; k < 32; k++) {
    int a = next() % (length + 1);
    int b = k < 16 ? a : a + next() % 40;
    String found = guard(() => ref(new NodeLocator2(a, b).searchWithin(unit)));
    sb.write('locate $a-$b $found\n');
  }

  for (Diagnostic diagnostic in result.errors) {
    String? correction = diagnostic.correctionMessage;
    sb.write(
      'diagnostic ${diagnostic.diagnosticCode.uniqueName}'
      '@${diagnostic.offset}+${diagnostic.length}'
      ' "${escape(diagnostic.message)}"'
      ' ${correction == null ? '-' : '"${escape(correction)}"'}\n',
    );
  }

  seed = length;
  for (int k = 0; k < 32; k++) {
    int a = next() % (length + 1);
    int b = k < 16 ? a : a + next() % 40;
    String found = guard(
      () => ref((unit as CompilationUnitImpl).nodeCovering2(
        offset: a,
        length: b - a,
      )),
    );
    sb.write('cover $a-$b $found\n');
  }
  sb.write(
    'timed2 ${visits((log) => unit.accept2(new TimedAstVisitor2<void>(new RecursiveRecorder(log))))}\n',
  );

  // Mutations, each on a fresh parse.
  for (int k = 0; k < 4; k++) {
    AstNodeImpl fresh = parseString(
      content: source,
      throwIfDiagnostics: false,
    ).unit as AstNodeImpl;
    List<AstNodeImpl> freshNodes = numberNodes(fresh);
    int i = next() % nodes.length;
    AstNodeImpl node = freshNodes[i];
    AstNodeImpl? parent = node.parent2;
    if (parent == null) {
      sb.write('replace $i -\n');
      continue;
    }
    int? j = replacementFor(freshNodes, i, parent, (n) => n.parent2);
    if (j == null) {
      sb.write('replace $i -\n');
      continue;
    }
    AstNodeImpl other = freshNodes[j];
    String r = guardError(() {
      parent.replaceChild(node, other);
      return '${summary(parent.toSource())} '
          '${guard(() => refIn(freshNodes, other.parent2))} '
          '${guard(() => refIn(freshNodes, node.parent2))}';
    });
    sb.write('replace $i $j $r\n');
  }
  for (int k = 0; k < 4; k++) {
    AstNodeImpl fresh = parseString(
      content: source,
      throwIfDiagnostics: false,
    ).unit as AstNodeImpl;
    List<AstNodeImpl> freshNodes = numberNodes(fresh);
    int i = next() % nodes.length;
    AstNodeImpl node = freshNodes[i];
    AstNodeImpl? parent = node.parent2;
    if (parent == null) {
      sb.write('remove $i -\n');
      continue;
    }
    String r = guardError(() {
      parent.removeChild(node);
      return summary(parent.toSource());
    });
    sb.write('remove $i $r\n');
  }

  dumpApi1(sb, source, unit, index, visits);
  return sb.toString();
}

/// The V1 view of [unit] (see the format above).
void dumpApi1(
  StringBuffer sb,
  String source,
  AstNodeImpl unit,
  Map<AstNode, int> index2,
  String Function(void Function(void Function(String, AstNode))) visits2,
) {
  List<AstNodeImpl> nodes;
  try {
    nodes = numberNodes1(unit);
  } catch (_) {
    sb.write('v1 !throw\n');
    return;
  }
  Map<AstNode, int> index = new Map.identity();
  for (int i = 0; i < nodes.length; i++) {
    index[nodes[i]] = i;
  }
  String ref(AstNode? node) {
    if (node == null) return '-';
    int? i = index[node];
    return i == null ? '?${node.runtimeType}' : '$i';
  }

  List<String> dispatch = [];
  for (int i = 0; i < nodes.length; i++) {
    AstNodeImpl node = nodes[i];
    String v = guard(() {
      String name = '-';
      node.accept(new SimpleRecorder1((String visit, _) => name = visit));
      return name;
    });
    dispatch.add(v);
    String p = guard(() => ref(node.parent));
    String r = guard(() => ref(node.root));
    String w = index2[node]?.toString() ?? '-';
    String s = guard(() => summary(node.toSource()));
    String c = guard(() {
      List<String> entities = [];
      for (ChildEntity child in node.namedChildEntities) {
        Object value = child.value;
        if (value is Token) {
          entities.add('${child.name}@${value.offset}');
        } else if (value is AstNodeImpl) {
          entities.add('${child.name}#${ref(value)}');
        } else if (value is List) {
          entities.add('${child.name}[${value.length}]');
          for (Object? element in value) {
            entities.add(
              element is Token ? '@${element.offset}' : '#${ref(element as AstNode)}',
            );
          }
        }
      }
      return entities.join(',');
    });
    sb.write(
      'v1node $i ${node.runtimeType} '
      '${guard(() => '${node.offset}+${node.length}')} v=$v p=$p r=$r w=$w '
      's=$s c=$c\n',
    );
  }

  String visits(void Function(void Function(String, AstNode)) run) {
    List<String> entries = [];
    int? runStart;
    int? runEnd;
    void flush() {
      if (runStart != null) {
        entries.add(runStart == runEnd ? '$runStart' : '$runStart-$runEnd');
        runStart = null;
      }
    }

    void log(String visit, AstNode node) {
      int? i = index[node];
      if (i != null && (visit == 'visitNode' || visit == dispatch[i])) {
        if (runStart != null && runEnd! + 1 == i) {
          runEnd = i;
          return;
        }
        flush();
        runStart = i;
        runEnd = i;
        return;
      }
      flush();
      entries.add('${i ?? '?${node.runtimeType}'}:$visit');
    }

    try {
      run(log);
    } catch (_) {
      flush();
      entries.add('!throw');
    }
    flush();
    return entries.join(' ');
  }

  sb.write(
    'v1recursive ${visits((log) => unit.accept(new RecursiveRecorder1(log)))}\n',
  );
  sb.write(
    'v1generalizing ${visits((log) => unit.accept(new GeneralizingRecorder(log)))}\n',
  );
  sb.write(
    'v1unifying ${visits((log) => unit.accept(new UnifyingRecorder1(log)))}\n',
  );
  sb.write(
    'v1delegating ${visits((log) => unit.accept(new DelegatingAstVisitor<void>([new SimpleRecorder1(log)])))}\n',
  );
  sb.write(
    'v1breadth ${visits((log) => new BreadthFirstRecorder(log).visitAllNodes(unit))}\n',
  );
  sb.write(
    'v1timed ${visits((log) => unit.accept(new TimedAstVisitor<void>(new RecursiveRecorder1(log))))}\n',
  );

  int length = source.length;
  int seed = length;
  int next() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed;
  }

  for (int k = 0; k < 32; k++) {
    int a = next() % (length + 1);
    int b = k < 16 ? a : a + next() % 40;
    String found = guard(() => ref(new NodeLocator(a, b).searchWithin(unit)));
    String covering = guard(
      () => ref((unit as CompilationUnitImpl).nodeCovering(
        offset: a,
        length: b - a,
      )),
    );
    sb.write('v1locate $a-$b $found\n');
    sb.write('v1cover $a-$b $covering\n');
  }

  for (int k = 0; k < 4; k++) {
    AstNodeImpl fresh = parseString(
      content: source,
      throwIfDiagnostics: false,
    ).unit as AstNodeImpl;
    List<AstNodeImpl> freshNodes = numberNodes1(fresh);
    int i = next() % nodes.length;
    AstNodeImpl node = freshNodes[i];
    AstNodeImpl? parent = node.parent;
    if (parent == null) {
      sb.write('v1replace $i -\n');
      continue;
    }
    int? j = replacementFor(freshNodes, i, parent, (n) => n.parent);
    if (j == null) {
      sb.write('v1replace $i -\n');
      continue;
    }
    AstNodeImpl other = freshNodes[j];
    String r = guardError(() {
      parent.replaceChild(node, other);
      return '${summary(parent.toSource())} '
          '${guard(() => refIn(freshNodes, other.parent))} '
          '${guard(() => refIn(freshNodes, node.parent))}';
    });
    sb.write('v1replace $i $j $r\n');
  }
}

/// Parses every file once, then calls `toSource` on every unit [rounds]
/// times, timing only `toSource`.
void runToSourceBench(List<(String, String)> inputs, int rounds) {
  List<CompilationUnit> units = [
    for (var (String path, _) in inputs)
      parseString(content: readSource(path), throwIfDiagnostics: false).unit,
  ];
  Stopwatch watch = new Stopwatch();
  List<int> times = [];
  int chars = 0;
  for (int round = 0; round < rounds; round++) {
    watch
      ..reset()
      ..start();
    for (CompilationUnit unit in units) {
      chars += unit.toSource().length;
    }
    watch.stop();
    times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  stdout.writeln(
    'dart toSource files=${units.length} rounds=$rounds '
    'min_us=${times.first} median_us=${times[times.length ~/ 2]} '
    'chars=$chars max_rss=${ProcessInfo.maxRss}',
  );
}

/// Counts the identifiers a RecursiveAstVisitor walk of the V1 view meets.
class IdentifierCounter extends RecursiveAstVisitor<void> {
  int count = 0;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    count++;
    super.visitSimpleIdentifier(node);
  }
}

/// `--walk --bench=N`: each round parses every file (untimed), then times a
/// RecursiveAstVisitor walk of the V1 view of every unit, which projects the
/// V1 nodes from the parsed (V2) ones as it goes.
void runWalkBench(List<(String, String)> inputs, int rounds) {
  List<String> sources = [
    for (var (String path, _) in inputs) readSource(path),
  ];
  Stopwatch watch = new Stopwatch();
  List<int> times = [];
  int identifiers = 0;
  for (int round = 0; round < rounds; round++) {
    List<CompilationUnit> units = [
      for (String source in sources)
        parseString(content: source, throwIfDiagnostics: false).unit,
    ];
    watch
      ..reset()
      ..start();
    for (CompilationUnit unit in units) {
      IdentifierCounter counter = new IdentifierCounter();
      unit.accept(counter);
      identifiers += counter.count;
    }
    watch.stop();
    times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  stdout.writeln(
    'dart walk files=${sources.length} rounds=$rounds '
    'min_us=${times.first} median_us=${times[times.length ~/ 2]} '
    'identifiers=$identifiers max_rss=${ProcessInfo.maxRss}',
  );
}
