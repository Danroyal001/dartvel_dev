// Oracle for the Rust port of the analyzer's element model (see
// ../README.md).
//
// For every library among the `.dart` files under one or more corpus roots,
// asks the analyzer for the library's element (`getLibraryByUri`: the
// library is linked from its declarations, its bodies are not resolved) and
// writes the element tree in the text format that
// `cargo run --release --bin element_dump` writes for the Rust port. The two
// outputs are compared byte for byte. Part files are skipped: their
// declarations are in the dump of the library that includes them.
//
// Usage:
//   dart --packages=<package_config.json> \
//     pkg/analyzer/rust/oracle/element_dump.dart --sdk <dir> \
//     [--types] [--bench=N] --out <dir> <root>...
//
// The package config (written by tests/element_oracle.rs) is both the one
// this program runs with and the one the analyzed files are resolved
// against; `--sdk` is a Dart SDK directory whose `lib/` holds the sources of
// the `dart:` libraries (linked from source, as the analyzer does when no
// summary is given).
//
// A dump is, for the library:
//   library <uri>
//     name "<name>" <nameOffset>+<nameLength>
//   then each of its fragments (units) as `fragment u<i> <source uri>`,
//   followed by the fragment's imports, exports and part includes, each
//   with its keyword offset, its directive URI (the runtime class of the
//   `DirectiveUri` and what it carries), its combinators, an import's prefix
//   and the names of an import's namespace;
//   then the elements of the library, by kind (classes, enums, extensions,
//   extension types, mixins, type aliases, top-level functions, top-level
//   variables, getters, setters), each as `<ElementKind> <name>` followed by
//   its fragments (`fragment u<i> <firstTokenOffset>/<nameOffset>` and the
//   fragment's flags that are set, as `flagsForTesting` names them) and its
//   children, indented;
//   and the export namespace.
// A name in a namespace is followed by the element it names:
// `<ElementKind> <library uri> <firstTokenOffset>/<nameOffset>` of the first
// fragment. Flags computed after the declarations are built (field
// promotability) are left out, as are the constructors of mixin
// applications, which need the supertypes, and the default values super
// formal parameters get from the super constructor.
//
// `--types` adds what resolving the declared types gives: the display
// string (`getDisplayString()`) of every declared type: bounds, supertypes,
// interfaces, mixins, superclass constraints, extended types, aliased types,
// return types, and the types of variables and parameters. A type that is
// left to inference (`hasImplicitType`, `hasImplicitReturnType`) is written
// `implicit`.
//
// Only `dart:` libraries and package libraries are imported.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/src/dart/element/element.dart';

Future<void> main(List<String> args) async {
  String? out;
  String? sdk;
  String? packages = Platform.packageConfig;
  int bench = 0;
  bool types = false;
  List<String> roots = [];
  for (int i = 0; i < args.length; i++) {
    String arg = args[i];
    if (arg.startsWith('--bench=')) {
      bench = int.parse(arg.substring('--bench='.length));
    } else if (arg == '--types') {
      types = true;
    } else if (arg == '--out') {
      out = args[++i];
    } else if (arg == '--sdk') {
      sdk = args[++i];
    } else if (arg == '--packages') {
      // For a compiled oracle, which has no package config of its own.
      packages = new File(args[++i]).absolute.uri.toString();
    } else {
      roots.add(arg);
    }
  }
  if (roots.isEmpty || packages == null || sdk == null || (out == null && bench == 0)) {
    stderr.writeln(
      'usage: element_dump.dart --sdk <dir> [--packages <file>] [--types] '
      '[--bench=N] '
      '--out <dir> <root>...',
    );
    exit(64);
  }
  String packageConfig = Uri.parse(packages).toFilePath();
  List<(String, String)> inputs = corpusFiles(roots);
  List<String> absoluteRoots = [
    for (String root in roots) new Directory(root).absolute.path,
  ];

  if (bench > 0) {
    List<int> times = [];
    for (int round = 0; round < bench; round++) {
      Stopwatch watch = new Stopwatch()..start();
      int count = 0;
      AnalysisContextCollectionImpl collection = newCollection(
        absoluteRoots,
        sdk,
        packageConfig,
      );
      for (var (String path, String _) in inputs) {
        var session = collection.contextFor(path).currentSession;
        var uri = session.uriConverter.pathToUri(path);
        var result = await session.getLibraryByUri(uri.toString());
        if (result is LibraryElementResult) count++;
      }
      watch.stop();
      times.add(watch.elapsedMicroseconds);
      stderr.writeln('round $round: ${watch.elapsedMicroseconds / 1000} ms, '
          '$count libraries');
    }
    times.sort();
    print('fastest ${times.first / 1000} ms, '
        'median ${times[times.length ~/ 2] / 1000} ms, '
        'peak RSS ${(peakRss() / (1024 * 1024)).toStringAsFixed(1)} MiB');
    return;
  }

  AnalysisContextCollectionImpl collection = newCollection(
    absoluteRoots,
    sdk,
    packageConfig,
  );
  for (var (String path, String relative) in inputs) {
    var session = collection.contextFor(path).currentSession;
    var uri = session.uriConverter.pathToUri(path);
    var result = await session.getLibraryByUri(uri.toString());
    if (result is! LibraryElementResult) continue;
    String dump = new ElementDumper(types).dumpLibrary(
      result.element as LibraryElementImpl,
    );
    File target = new File('$out/$relative.elements');
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(utf8.encode(dump));
  }
}

AnalysisContextCollectionImpl newCollection(
  List<String> roots,
  String sdk,
  String packageConfig,
) {
  return new AnalysisContextCollectionImpl(
    includedPaths: roots,
    packageConfigFile: packageConfig,
    resourceProvider: PhysicalResourceProvider.INSTANCE,
    sdkPath: new Directory(sdk).absolute.path,
  );
}

/// Every `.dart` file under [roots] as (path, label/relative path), sorted
/// by relative path within each root, as oracle/ast_dump.dart lists them.
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

/// Fragment flags that are computed after the declarations are built.
const Set<String> laterFlags = {'isPromotable'};

class ElementDumper {
  final bool types;
  final StringBuffer sb = new StringBuffer();
  late List<LibraryFragmentImpl> units;

  new(this.types);

  void line(int depth, String text) {
    for (int i = 0; i < depth; i++) {
      sb.write('  ');
    }
    sb.write(text);
    sb.write('\n');
  }

  String opt(int? value) => value == null ? '-' : '$value';

  String name(String? name) => name == null ? '-' : '"${escape(name)}"';

  String dumpLibrary(LibraryElementImpl library) {
    units = library.internal.fragments;
    line(0, 'library ${library.uri}');
    line(
      1,
      'name ${name(library.name)} '
      '${library.nameOffset}+${library.nameLength}',
    );
    if (library.isSynthetic) line(1, 'isSynthetic');
    for (var (int i, LibraryFragmentImpl unit) in units.indexed) {
      line(0, 'fragment u$i ${unit.source.uri}');
      if (unit.isOriginNotExistingFile) line(1, 'isOriginNotExistingFile');
      for (LibraryImportImpl import in unit.libraryImports) {
        line(1, 'import ${import.importKeywordOffset} ${directiveUri(import.uri)}');
        if (import.isSynthetic) line(2, 'isSynthetic');
        if (import.prefix case PrefixFragmentImpl prefix?) {
          line(
            2,
            'prefix ${name(prefix.name)} ${opt(prefix.nameOffset)} '
            '${prefix.offset}${prefix.isDeferred ? ' deferred' : ''}',
          );
        }
        combinators(import.combinators);
        namespace(2, 'namespace', import.namespace.definedNames2);
      }
      for (LibraryExportImpl export in unit.libraryExports) {
        line(1, 'export ${export.exportKeywordOffset} ${directiveUri(export.uri)}');
        combinators(export.combinators);
      }
      for (PartIncludeImpl part in unit.parts) {
        line(1, 'part ${part.partKeywordOffset} ${directiveUri(part.uri)}');
      }
    }
    for (var e in library.classes) element(0, e);
    for (var e in library.enums) element(0, e);
    for (var e in library.extensions) element(0, e);
    for (var e in library.extensionTypes) element(0, e);
    for (var e in library.mixins) element(0, e);
    for (var e in library.typeAliases) element(0, e);
    for (var e in library.topLevelFunctions) element(0, e);
    for (var e in library.topLevelVariables) element(0, e);
    for (var e in library.getters) element(0, e);
    for (var e in library.setters) element(0, e);
    namespace(0, 'exportNamespace', library.exportNamespace.definedNames2);
    return sb.toString();
  }

  String directiveUri(DirectiveUri uri) {
    switch (uri) {
      case DirectiveUriWithLibraryImpl():
        return 'DirectiveUriWithLibrary "${escape(uri.relativeUriString)}" '
            '${uri.library.uri}';
      case DirectiveUriWithUnitImpl():
        return 'DirectiveUriWithUnit "${escape(uri.relativeUriString)}" '
            '${uri.libraryFragment.source.uri}';
      case DirectiveUriWithSourceImpl():
        return 'DirectiveUriWithSource "${escape(uri.relativeUriString)}" '
            '${uri.source.uri}';
      case DirectiveUriWithRelativeUriImpl():
        return 'DirectiveUriWithRelativeUri "${escape(uri.relativeUriString)}" '
            '${uri.relativeUri}';
      case DirectiveUriWithRelativeUriStringImpl():
        return 'DirectiveUriWithRelativeUriString '
            '"${escape(uri.relativeUriString)}"';
      default:
        return 'DirectiveUri';
    }
  }

  void combinators(List<NamespaceCombinator> combinators) {
    for (NamespaceCombinator combinator in combinators) {
      switch (combinator) {
        case ShowElementCombinator():
          line(
            2,
            'show ${combinator.offset}-${combinator.end} '
            '${combinator.shownNames.join(' ')}',
          );
        case HideElementCombinator():
          line(
            2,
            'hide ${combinator.offset}-${combinator.end} '
            '${combinator.hiddenNames.join(' ')}',
          );
      }
    }
  }

  void namespace(int depth, String title, Map<String, Element> names) {
    List<String> keys = names.keys.toList()..sort(compareBytes);
    line(depth, '$title ${keys.length}');
    for (String key in keys) {
      line(depth + 1, '${escape(key)} ${reference(names[key]!)}');
    }
  }

  String reference(Element element) {
    String library = element.library?.uri.toString() ?? '-';
    var fragment = element.firstFragment as FragmentImpl;
    return '${element.kind.name} $library '
        '${opt(fragment.firstTokenOffset)}/${opt(fragment.nameOffset)}';
  }

  String unitOf(FragmentImpl fragment) {
    FragmentImpl? current = fragment;
    while (current != null && current is! LibraryFragmentImpl) {
      current = current.enclosingFragment;
    }
    if (current == null) return 'u-';
    int index = units.indexOf(current as LibraryFragmentImpl);
    return 'u$index';
  }

  void fragments(int depth, Element element) {
    for (Fragment f in element.fragments) {
      var fragment = f as FragmentImpl;
      List<String> flags = [
        for (var MapEntry(:key, :value) in flagsOf(fragment).entries)
          if (value && !laterFlags.contains(key)) key,
      ]..sort(compareBytes);
      String flagText = flags.isEmpty ? '' : ' ${flags.join(' ')}';
      line(
        depth,
        'fragment ${unitOf(fragment)} '
        '${opt(fragment.firstTokenOffset)}/${opt(fragment.nameOffset)}'
        '$flagText',
      );
    }
  }

  Map<String, bool> flagsOf(FragmentImpl fragment) {
    return switch (fragment) {
      ClassFragmentImpl() => fragment.flagsForTesting,
      ConstructorFragmentImpl() => fragment.flagsForTesting,
      ExecutableFragmentImpl() => fragment.flagsForTesting,
      FieldFragmentImpl() => fragment.flagsForTesting,
      FormalParameterFragmentImpl() => fragment.flagsForTesting,
      PropertyInducingFragmentImpl() => fragment.flagsForTesting,
      VariableFragmentImpl() => fragment.flagsForTesting,
      TypeParameterFragmentImpl() => fragment.flagsForTesting,
      MixinFragmentImpl() => fragment.flagsForTesting,
      _ => fragment.flagsForTesting,
    };
  }

  String type(DartType? type) => type == null ? '-' : type.getDisplayString();

  void typeLine(int depth, String title, DartType? type) {
    if (types) line(depth, '$title ${this.type(type)}');
  }

  void typesLine(int depth, String title, List<DartType> list) {
    if (types && list.isNotEmpty) {
      line(depth, '$title ${list.map(type).join(', ')}');
    }
  }

  void element(int depth, Element element) {
    line(depth, '${element.kind.name} ${name(element.name)}');
    int d = depth + 1;
    fragments(d, element);
    switch (element) {
      case InterfaceElementImpl():
        typeParameters(d, element.typeParameters);
        if (element is! MixinElementImpl) {
          typeLine(d, 'supertype', element.supertype);
        } else {
          typesLine(d, 'superclassConstraints', element.superclassConstraints);
        }
        typesLine(d, 'mixins', element.mixins);
        typesLine(d, 'interfaces', element.interfaces);
        if (element is ExtensionTypeElementImpl) {
          typeLine(d, 'representationType', element.representation.type);
        }
        for (var e in element.fields) this.element(d, e);
        for (var e in element.getters) this.element(d, e);
        for (var e in element.setters) this.element(d, e);
        for (var e in element.constructors) {
          if (e.isOriginMixinApplication) continue;
          this.element(d, e);
        }
        for (var e in element.methods) this.element(d, e);
      case ExtensionElementImpl():
        typeParameters(d, element.typeParameters);
        typeLine(d, 'extendedType', element.extendedType);
        for (var e in element.fields) this.element(d, e);
        for (var e in element.getters) this.element(d, e);
        for (var e in element.setters) this.element(d, e);
        for (var e in element.methods) this.element(d, e);
      case TypeAliasElementImpl():
        typeParameters(d, element.typeParameters);
        typeLine(d, 'aliasedType', element.aliasedType);
      case PropertyAccessorElementImpl():
        if (element.isExtensionTypeMember) line(d, 'isExtensionTypeMember');
        var variable = element.variable;
        line(d, 'variable ${variable.kind.name} ${name(variable.name)}');
        executable(d, element);
      case ExecutableElementImpl():
        if (element.isExtensionTypeMember) line(d, 'isExtensionTypeMember');
        executable(d, element);
      case PropertyInducingElementImpl():
        var getter = element.getter;
        var setter = element.setter;
        if (getter != null) line(d, 'getter ${name(getter.name)}');
        if (setter != null) line(d, 'setter ${name(setter.name)}');
        if (types && element.isOriginDeclaration) {
          line(
            d,
            'type ${element.hasImplicitType ? 'implicit' : type(element.type)}',
          );
        }
      default:
        throw new StateError('${element.runtimeType}');
    }
  }

  void executable(int d, ExecutableElementImpl element) {
    typeParameters(d, element.typeParameters);
    formalParameters(d, element.formalParameters);
    if (types &&
        element is! ConstructorElementImpl &&
        !(element is PropertyAccessorElementImpl &&
            !element.firstFragment.isOriginDeclaration)) {
      line(
        d,
        'returnType ${element.hasImplicitReturnType ? 'implicit' : type(element.returnType)}',
      );
    }
  }

  void typeParameters(int depth, List<TypeParameterElement> list) {
    for (var e in list) {
      var element = e as TypeParameterElementImpl;
      line(depth, '${element.kind.name} ${name(element.name)}');
      fragments(depth + 1, element);
      if (types && element.bound != null) {
        line(depth + 1, 'bound ${type(element.bound)}');
      }
    }
  }

  void formalParameters(int depth, List<FormalParameterElement> list) {
    for (var e in list) {
      var element = e as FormalParameterElementImpl;
      line(depth, '${element.kind.name} ${name(element.name)}');
      int d = depth + 1;
      fragments(d, element);
      String kind = element.isRequiredPositional
          ? 'requiredPositional'
          : element.isOptionalPositional
          ? 'optionalPositional'
          : element.isRequiredNamed
          ? 'requiredNamed'
          : 'optionalNamed';
      line(d, 'kind $kind');
      if (element is FieldFormalParameterElementImpl) {
        line(d, 'fieldFormal');
        if (element.privateName case var privateName?) {
          line(d, 'privateName ${name(privateName)}');
        }
      }
      if (element is SuperFormalParameterElementImpl) line(d, 'superFormal');
      // A super formal parameter without a default value of its own gets
      // the one of the super constructor's parameter, which needs the
      // super constructor resolved; only its own is written.
      String? code = element is SuperFormalParameterElementImpl
          ? (element.isRequired
                ? null
                : element.constantInitializer2?.toSource())
          : element.defaultValueCode;
      if (code != null) {
        line(d, 'default ${name(code)}');
      }
      if (types) {
        line(
          d,
          'type ${element.hasImplicitType ? 'implicit' : type(element.type)}',
        );
      }
    }
  }
}

/// The peak resident set size of this process (`VmHWM`), in bytes.
int peakRss() {
  for (String line in new File('/proc/self/status').readAsLinesSync()) {
    if (line.startsWith('VmHWM:')) {
      return int.parse(line.substring(6).trim().split(' ').first) * 1024;
    }
  }
  return 0;
}
