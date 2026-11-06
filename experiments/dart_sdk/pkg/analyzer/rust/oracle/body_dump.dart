// Resolved-body oracle using the real upstream analyzer (not a port).
// Full mode records every V1 expression's static type and identifier element.
// --literals selects context-independent literal kinds only; integers need
// downward inference and are deliberately outside that first slice.
import 'dart:io';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'element_dump.dart' as elements;

Future<void> main(List<String> args) async {
  String? sdk;
  String? out;
  String? packages = Platform.packageConfig;
  bool literals = false;
  List<String> roots = [];
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--sdk': sdk = args[++i];
      case '--out': out = args[++i];
      case '--packages': packages = new File(args[++i]).absolute.uri.toString();
      case '--literals': literals = true;
      default: roots.add(args[i]);
    }
  }
  if (sdk == null || out == null || packages == null || roots.isEmpty) {
    stderr.writeln('usage: body_dump.dart --sdk <dir> [--literals] --out <dir> <root>...');
    exit(64);
  }
  var collection = elements.newCollection(
    [for (var root in roots) new Directory(root).absolute.path],
    sdk, Uri.parse(packages).toFilePath(),
  );
  for (var (path, relative) in elements.corpusFiles(roots)) {
    var session = collection.contextFor(path).currentSession;
    var result = await session.getResolvedUnit(path);
    if (result is! ResolvedUnitResult) {
      throw new StateError('Cannot resolve $path: ${result.runtimeType}');
    }
    var buffer = new StringBuffer();
    void visit(AstNodeImpl node) {
      bool selected = node is BooleanLiteral || node is DoubleLiteral ||
          node is NullLiteral || node is SimpleStringLiteral ||
          node is AdjacentStrings || node is StringInterpolation ||
          node is SymbolLiteral;
      if (node is Expression && (!literals || selected)) {
        buffer.writeln('${node.runtimeType} ${node.offset}+${node.length} '
            'type=${(node as Expression).staticType?.getDisplayString() ?? '-'}');
      }
      if (!literals && node is Identifier) {
        Element? element = (node as Identifier).element;
        var fragment = element?.firstFragment;
        buffer.writeln('identifier ${node.offset}+${node.length} '
            'element=${element == null ? '-' : '${element.kind.name} '
            '${element.library?.uri} ${fragment?.nameOffset} ${element.name}'}');
      }
      for (var child in node.namedChildEntities) {
        var value = child.value;
        if (value is AstNodeImpl) visit(value);
        if (value is List) {
          for (var item in value) {
            if (item is AstNodeImpl) visit(item);
          }
        }
      }
    }
    visit(result.unit as AstNodeImpl);
    var target = new File('$out/$relative.body');
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(buffer.toString());
  }
}
