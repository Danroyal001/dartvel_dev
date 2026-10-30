// Corpus builder for the API oracle (see ../README.md).
//
// Writes the inputs of the analyzer's own AST tests as a corpus, so that the
// oracle checks what those tests check (toSource of the nodes they find,
// parents, locating nodes) on the code they parse. Every test file is copied
// as is, and the value of every string literal in it is written as a file of
// its own: a literal whose interpolations name only local variables holding
// string literals (`var code = 'E(0)';` ... `'''$code.foo();'''`), as most
// tests build their code, is written with those values substituted; a
// literal with any other interpolation is skipped.
//
// Usage:
//   dart --packages=<package_config.json> \
//     pkg/analyzer/rust/oracle/extract_test_inputs.dart --out <dir> <test file>...
//
// Output: <dir>/<test basename>/source.dart and <dir>/<test basename>/<n>.dart.

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Collects the string values of a test file: every literal, with the
/// values of local string variables substituted where it interpolates them.
class Collector extends RecursiveAstVisitor2<void> {
  final List<String> values = [];

  /// The string-literal locals of the enclosing function bodies.
  final List<Map<String, String>> scopes = [{}];

  String? value(Expression e) {
    if (e is SimpleStringLiteral) return e.value;
    if (e is AdjacentStrings) {
      StringBuffer sb = StringBuffer();
      for (StringLiteral s in e.strings) {
        String? v = value(s);
        if (v == null) return null;
        sb.write(v);
      }
      return sb.toString();
    }
    if (e is StringInterpolation) {
      StringBuffer sb = StringBuffer();
      for (InterpolationElement element in e.elements) {
        if (element is InterpolationString) {
          sb.write(element.value);
        } else if (element is InterpolationExpression) {
          var inner = element.expression2;
          String? name = switch (inner) {
            ParsedUnqualifiedName(:var name) => name.lexeme,
            _ => null,
          };
          String? local = name == null ? null : lookup(name);
          if (local == null) return null;
          sb.write(local);
        }
      }
      return sb.toString();
    }
    return null;
  }

  String? lookup(String name) {
    for (Map<String, String> scope in scopes.reversed) {
      if (scope.containsKey(name)) return scope[name];
    }
    return null;
  }

  @override
  void visitBlockFunctionBody(BlockFunctionBody node) {
    scopes.add({});
    super.visitBlockFunctionBody(node);
    scopes.removeLast();
  }

  @override
  void visitLocalVariable(LocalVariable node) {
    var initializer = node.initializer;
    if (initializer != null) {
      String? v = value(initializer);
      if (v != null) scopes.last[node.name.lexeme] = v;
    }
    super.visitLocalVariable(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    values.add(node.value);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    String? v = value(node);
    if (v != null) values.add(v);
    super.visitStringInterpolation(node);
  }
}

void main(List<String> args) {
  String? out;
  List<String> files = [];
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--out') {
      out = args[++i];
    } else {
      files.add(args[i]);
    }
  }
  if (out == null || files.isEmpty) {
    stderr.writeln('usage: extract_test_inputs.dart --out <dir> <file>...');
    exit(64);
  }
  int total = 0;
  for (String path in files) {
    String name = path.split('/').last.replaceAll('.dart', '');
    Directory dir = Directory('$out/$name')..createSync(recursive: true);
    String source = File(path).readAsStringSync();
    File('${dir.path}/source.dart').writeAsStringSync(source);
    Collector collector = Collector();
    parseString(
      content: source,
      throwIfDiagnostics: false,
    ).unit.accept2(collector);
    int n = 0;
    for (String value in collector.values) {
      File('${dir.path}/${n++}.dart').writeAsStringSync(value);
    }
    total += n;
  }
  stdout.writeln('$total inputs from ${files.length} files');
}
