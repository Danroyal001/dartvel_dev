// Generated coverage for the type lattice of
// lib/transformations/type_flow/types.dart (not a mirrored file; see
// ../README.md). Upstream's types_test.dart checks 98 union/intersection
// cases over four classes; this program runs the same operations of
// upstream's types.dart over a wider pool, so the Rust port
// (tests/types_test.rs) can be compared with it line by line.
//
// It writes, to <out dir>:
//
//   types.dill          the mock SDK upstream's test uses
//                       (createMockSdkComponent), the classes of upstream's
//                       types_test.dart (its `library dummy:` classes T1-T4
//                       and C1-C3, and its parentless C1 and C2<E> in a
//                       library of their own) and the lattice's classes;
//   lattice_cases.txt   the lattice (classes, supertypes, specializations),
//                       the pool of types, and every operation with the
//                       result upstream's types.dart gives.
//
// The lattice's classes are read back from types.dill before use, so both
// sides work on the same kernel. Each type of the pool is written in a
// small prefix notation that both sides parse:
//
//   E | A | U                  emptyType, anyInstanceType, unknownType
//   N d                        d.nullable()
//   K id                       tfClass(id).concreteType
//   KC id n                    tfClass(id).constantConcreteType(IntConstant(n))
//   KT id n|- k a1..ak         tfClass(id).constantConcreteType(IntConstant(n),
//                              [a1..ak]) or ClassConcreteType(cls, [a1..ak])
//   C id | W id                tfClass(id).coneType, WideConeType(tfClass(id))
//   S k d1..dk                 SetType([d1..dk])
//   R id k d1..dk              tfClass(id).recordConcreteType([d1..dk])
//   RT dyn|never|null|int|intq|num|objq
//                              RuntimeType of that type, no type arguments
//   P i                        the pool's type i (the same object)
//
// An operation line is `<op> <operands> = <result>`; the Rust test reads
// everything before ` = `, runs the operation on the port and prints the
// line again with its own result.
//
// Usage: dart types_lattice.dart <out dir>
import 'dart:core' hide Type;
import 'dart:io';
import 'dart:typed_data';

import 'package:kernel/ast.dart';
import 'package:kernel/binary/ast_from_binary.dart' show BinaryBuilder;
import 'package:kernel/binary/ast_to_binary.dart' show BinaryPrinter, BytesSink;
import 'package:kernel/core_types.dart';
import 'package:kernel/target/targets.dart' show TargetFlags;
import 'package:kernel/testing/mock_sdk_component.dart';
import 'package:vm/modular/target/vm.dart';
import 'package:vm/transformations/type_flow/types.dart';

/// The lattice's hierarchy: `TestTypeHierarchy` of types_test.dart, with
/// specializations keyed by class id (record classes share a class node).
class LatticeTypeHierarchy extends TypeHierarchy {
  final Map<int, TFClass> classes;
  final Map<int, Type> specializations;

  LatticeTypeHierarchy(
    CoreTypes coreTypes,
    this.classes,
    this.specializations,
  ) : super(coreTypes, VmTarget(TargetFlags()));

  @override
  Type specializeTypeCone(TFClass base, {required bool allowWideCone}) =>
      specializations[base.id]!;

  @override
  bool hasAllocatedSubtypes(TFClass cls) =>
      specializeTypeCone(cls, allowWideCone: true) is! EmptyType;

  @override
  TFClass getTFClass(Class c) => throw 'getTFClass is not used';

  @override
  TFClass getRecordClass(RecordShape shape) =>
      throw 'getRecordClass is not used';

  @override
  List<DartType> flattenedTypeArgumentsFor(Class klass) =>
      throw 'flattenedTypeArgumentsFor is not used';

  @override
  int genericInterfaceOffsetFor(Class klass, Class iface) =>
      throw 'genericInterfaceOffsetFor is not used';

  @override
  List<Type> flattenedTypeArgumentsForNonGeneric(Class klass) =>
      throw 'flattenedTypeArgumentsForNonGeneric is not used';
}

const String latticeUri = 'org-dartlang-test:///lattice.dart';

/// The lattice's classes: name, abstract, superclass, interfaces, number of
/// type parameters, class id. Ids are deliberately not in declaration
/// order, so sets are sorted by something other than creation order.
const List<(String, bool, String?, List<String>, int, int)> latticeClasses = [
  ('A', true, null, [], 0, 5),
  ('B', false, 'A', [], 0, 2),
  ('C', false, 'A', [], 0, 7),
  ('D', false, 'B', ['C'], 0, 1),
  ('G', false, 'B', [], 1, 4),
  ('H', false, null, ['A'], 2, 9),
  ('I', true, null, [], 0, 3),
  ('J', false, 'I', [], 0, 8),
  ('K', false, 'J', ['C'], 0, 6),
  ('E', true, null, [], 0, 12),
  ('Rec', false, null, [], 0, 11),
];

/// Record classes: id, positional fields, named fields (class node `Rec`).
const List<(int, int, List<String>)> recordClasses = [
  (10, 2, []),
  (14, 1, ['a']),
  (15, 0, []),
];

/// Cones wider than this specialize to a [WideConeType].
const int wideConeThreshold = 3;

const List<String> pool = [
  'E', 'A', 'N E', 'N A', //
  'K 1', 'K 2', 'K 4', 'K 6', 'K 7', 'K 8', 'K 9', //
  'C 5', 'C 2', 'C 7', 'C 1', 'C 4', 'C 9', 'C 3', 'C 8', 'C 6', 'C 12', //
  'W 5', 'W 3', 'N K 2', 'N C 5', 'N C 1', 'N C 3', //
  'S 2 K 1 K 2', 'S 3 K 1 K 6 K 7', 'S 2 K 6 K 8', 'S 4 K 1 K 2 K 4 K 9',
  'N S 2 K 6 K 8', //
  'KC 2 1', 'KC 2 1', 'KC 2 2', 'KC 7 1', 'N KC 2 1', 'S 2 P 32 K 7', //
  'KT 4 - 1 RT int', 'KT 4 - 1 RT int', 'KT 4 - 1 U', 'KT 4 7 1 RT int',
  'KT 4 7 1 RT int', 'KT 9 - 2 RT int U', 'KT 9 - 2 U RT num',
  'KT 9 - 2 RT int RT num', //
  'K 10', 'R 10 2 K 2 K 7', 'R 10 2 N K 2 K 7', 'R 10 2 S 2 K 1 K 2 E',
  'R 14 2 K 1 N A', 'K 14', 'R 15 0', 'R 10 2 P 47 K 2', 'R 10 2 P 53 K 7',
  'R 10 2 P 54 K 2', 'S 2 K 2 P 47', 'N P 47', 'R 10 2 K 2 E',
  'R 10 2 N A N A', //
  'W 2', 'S 2 P 41 K 9', 'KC 1 3', 'S 2 P 62 K 4', 'N P 61', 'N P 37',
];

/// Pool entries whose chained unions and intersections are also checked.
const List<int> chainPool = [
  0, 1, 2, 3, 4, 5, 8, 11, 12, 13, 14, 17, 20, 21, 23, 27, 28, 32, 36, 47, //
  48, 56, 60,
];

const List<String> typeSetPool = [
  'U', 'RT dyn', 'RT int', 'RT int', 'RT num', 'RT null', 'RT never',
  'RT objq', 'RT intq',
];

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('usage: types_lattice.dart <out dir>');
    exit(64);
  }
  final String out = arguments[0];
  Directory(out).createSync(recursive: true);

  final Component written = buildComponent();
  final BytesSink sink = BytesSink();
  BinaryPrinter(sink).writeComponentFile(written);
  final Uint8List bytes = sink.builder.takeBytes();
  File('$out/types.dill').writeAsBytesSync(bytes);

  final Component component = Component();
  BinaryBuilder(bytes).readComponent(component);
  final CoreTypes coreTypes = CoreTypes(component);
  final Library lattice = component.libraries.singleWhere(
    (Library l) => '${l.importUri}' == latticeUri,
  );
  Class classNamed(String name) =>
      lattice.classes.singleWhere((Class c) => c.name == name);

  final StringBuffer text = StringBuffer();
  void line(String s) => text.writeln(s);

  // Classes, in declaration order (supertypes first).
  final Map<int, TFClass> classes = {};
  final Map<String, TFClass> byName = {};
  for (final (name, _, superclass, interfaces, _, id) in latticeClasses) {
    if (name == 'Rec') continue;
    final Set<TFClass> supertypes = {};
    for (final String s in [?superclass, ...interfaces]) {
      supertypes.addAll(byName[s]!.supertypes);
    }
    final TFClass cls = TFClass(id, classNamed(name), supertypes, null);
    classes[id] = byName[name] = cls;
    final List<int> ids = cls.supertypes.map((TFClass t) => t.id).toList()
      ..sort();
    line('class $id $name ${ids.join(' ')}');
  }
  for (final (id, positional, named) in recordClasses) {
    final RecordShape shape = RecordShape(
      RecordType(
        DartTypeList.from([
          for (int i = 0; i < positional; i++) const DynamicType(),
        ]),
        NamedDartTypeList.from([
          for (final String n in named) NamedType(n, const DynamicType()),
        ]),
        Nullability.nonNullable,
      ),
    );
    classes[id] = TFClass(id, classNamed('Rec'), {}, shape);
    line('record $id Rec $positional ${named.isEmpty ? '-' : named.join(',')}');
  }

  // Specializations: the allocated (non-abstract) subtypes of each class.
  final Map<int, Type> specializations = {};
  final List<TFClass> allocated = [
    for (final (name, isAbstract, _, _, _, _) in latticeClasses)
      if (!isAbstract && name != 'Rec') byName[name]!,
  ]..sort((TFClass a, TFClass b) => a.id.compareTo(b.id));
  for (final TFClass cls in classes.values) {
    final Type spec;
    final String notation;
    if (cls.isRecord) {
      spec = cls.concreteType;
      notation = 'K ${cls.id}';
    } else {
      final List<ConcreteType> subtypes = [
        for (final TFClass t in allocated)
          if (t.isSubtypeOf(cls)) t.concreteType,
      ];
      if (subtypes.isEmpty) {
        spec = emptyType;
        notation = 'E';
      } else if (subtypes.length == 1) {
        spec = subtypes.single;
        notation = 'K ${subtypes.single.cls.id}';
      } else if (subtypes.length > wideConeThreshold) {
        spec = WideConeType(cls);
        notation = 'W ${cls.id}';
      } else {
        spec = SetType(subtypes);
        notation =
            'S ${subtypes.length} '
            '${subtypes.map((ConcreteType t) => 'K ${t.cls.id}').join(' ')}';
      }
    }
    specializations[cls.id] = spec;
    line('spec ${cls.id} $notation = $spec');
  }
  final LatticeTypeHierarchy hierarchy = LatticeTypeHierarchy(
    coreTypes,
    classes,
    specializations,
  );

  final List<Type> types = [];
  Type parse(List<String> tokens) {
    String next() => tokens.removeAt(0);
    Type rt(String name) => switch (name) {
      'dyn' => RuntimeType(const DynamicType(), null),
      'never' => RuntimeType(const NeverType.nonNullable(), null),
      'null' => RuntimeType(const NullType(), null),
      'int' => RuntimeType(coreTypes.intNonNullableRawType, null),
      'intq' => RuntimeType(coreTypes.intNullableRawType, null),
      'num' => RuntimeType(coreTypes.numNonNullableRawType, null),
      'objq' => RuntimeType(coreTypes.objectNullableRawType, null),
      _ => throw 'unknown runtime type $name',
    };
    final String head = next();
    switch (head) {
      case 'E':
        return emptyType;
      case 'A':
        return anyInstanceType;
      case 'U':
        return unknownType;
      case 'N':
        return parse(tokens).nullable();
      case 'K':
        return classes[int.parse(next())]!.concreteType;
      case 'KC':
        final TFClass cls = classes[int.parse(next())]!;
        return cls.constantConcreteType(IntConstant(int.parse(next())));
      case 'KT':
        final TFClass cls = classes[int.parse(next())]!;
        final String constant = next();
        final int count = int.parse(next());
        final List<Type> args = [for (int i = 0; i < count; i++) parse(tokens)];
        return constant == '-'
            ? ClassConcreteType(cls, args)
            : cls.constantConcreteType(IntConstant(int.parse(constant)), args);
      case 'C':
        return classes[int.parse(next())]!.coneType;
      case 'W':
        return WideConeType(classes[int.parse(next())]!);
      case 'S':
        final int count = int.parse(next());
        return SetType([
          for (int i = 0; i < count; i++) parse(tokens) as ConcreteType,
        ]);
      case 'R':
        final TFClass cls = classes[int.parse(next())]!;
        final int count = int.parse(next());
        return cls.recordConcreteType([
          for (int i = 0; i < count; i++) parse(tokens),
        ]);
      case 'RT':
        return rt(next());
      case 'P':
        return types[int.parse(next())];
    }
    throw 'unknown type notation $head';
  }

  String guarded(Object? Function() op) {
    try {
      return '${op()}';
    } catch (e) {
      return 'throws $e';
    }
  }

  for (int i = 0; i < pool.length; i++) {
    final List<String> tokens = pool[i].split(' ');
    final Type type = parse(tokens);
    if (tokens.isNotEmpty) throw 'trailing tokens in ${pool[i]}';
    types.add(type);
    line('type $i ${pool[i]} = $type');
  }
  final List<int> classIds = classes.keys.toList()..sort();
  for (int i = 0; i < types.length; i++) {
    final Type a = types[i];
    line('nullable $i = ${guarded(() => a.nullable())}');
    line('isSpecialized $i = ${guarded(() => a.isSpecialized)}');
    line('specialize $i = ${guarded(() => a.specialize(hierarchy))}');
    line(
      'hasEmptySpecialization $i = '
      '${guarded(() => a.hasEmptySpecialization(hierarchy))}',
    );
    for (final int c in classIds) {
      line('isSubtypeOf $i $c = ${guarded(() => a.isSubtypeOf(classes[c]!))}');
    }
    // Hash codes of types made of class ids only (constants and Dart types
    // hash by identity upstream).
    if (!pool[i].contains('KC') &&
        !pool[i].contains('KT') &&
        !pool[i].contains('P')) {
      line('hash $i = ${a.hashCode}');
    }
  }
  for (int i = 0; i < types.length; i++) {
    for (int j = 0; j < types.length; j++) {
      final Type a = types[i];
      final Type b = types[j];
      line('eq $i $j = ${a == b}');
      line('union $i $j = ${guarded(() => a.union(b, hierarchy))}');
      line(
        'intersection $i $j = ${guarded(() => a.intersection(b, hierarchy))}',
      );
    }
  }
  for (final int i in chainPool) {
    for (final int j in chainPool) {
      for (final int k in chainPool) {
        final Type a = types[i];
        final Type b = types[j];
        final Type c = types[k];
        line(
          'union3 $i $j $k = '
          '${guarded(() => a.union(b, hierarchy).union(c, hierarchy))}',
        );
        line(
          'intersection3 $i $j $k = '
          '${guarded(() => a.intersection(b, hierarchy).intersection(c, hierarchy))}',
        );
        line(
          'unionIntersection $i $j $k = '
          '${guarded(() => a.union(b, hierarchy).intersection(c, hierarchy))}',
        );
      }
    }
  }

  // Type arguments: unknownType and runtime types, which only intersect
  // (and unknownType unions).
  final List<Type> typeSets = [];
  for (int i = 0; i < typeSetPool.length; i++) {
    final Type type = parse(typeSetPool[i].split(' '));
    typeSets.add(type);
    line('typeSet $i ${typeSetPool[i]} = $type');
  }
  for (int i = 0; i < typeSets.length; i++) {
    for (int j = 0; j < typeSets.length; j++) {
      final Type a = typeSets[i];
      final Type b = typeSets[j];
      line('typeSetEq $i $j = ${a == b}');
      line(
        'typeSetIntersection $i $j = '
        '${guarded(() => a.intersection(b, hierarchy))}',
      );
      if (a is UnknownType) {
        line('typeSetUnion $i $j = ${guarded(() => a.union(b, hierarchy))}');
      }
    }
  }

  File('$out/lattice_cases.txt').writeAsStringSync('$text');
}

/// The mock SDK of upstream's types_test.dart, plus the test's classes and
/// the lattice's, each in a library.
Component buildComponent() {
  final Component component = createMockSdkComponent();
  final Class objectClass = component.libraries.first.classes.first;
  final InterfaceType objectType = InterfaceType(
    objectClass,
    Nullability.nonNullable,
  );

  Library library(Uri uri, String? name) {
    final Library l = Library(uri, name: name, fileUri: uri);
    component.libraries.add(l..parent = component);
    return l;
  }

  Class addClass(
    Library lib,
    String name, {
    bool isAbstract = false,
    Class? superclass,
    List<Class> interfaces = const [],
    List<String> typeParameters = const [],
  }) {
    final Class c = Class(
      name: name,
      isAbstract: isAbstract,
      supertype: (superclass ?? objectClass).asThisSupertype,
      implementedTypes: [for (final Class i in interfaces) i.asThisSupertype],
      typeParameters: typeParameters.isEmpty
          ? null
          : TypeParameterList.from([
              for (final String p in typeParameters)
                TypeParameter(p, objectType, const DynamicType()),
            ]),
      fileUri: lib.fileUri,
    );
    lib.addClass(c);
    return c;
  }

  // types_test.dart: `Class(name: ..., fileUri: dummyUri)..parent =
  // dummyLibrary` (dummyLibrary is `Library(Uri(scheme: 'dummy'))`).
  final Library dummy = library(Uri(scheme: 'dummy'), null);
  for (final String name in ['T1', 'T2', 'T3', 'T4', 'C1', 'C2', 'C3']) {
    addClass(dummy, name);
  }
  // types_test.dart's 'types-builder' classes have no parent.
  final Library parentless = library(
    Uri.parse('org-dartlang-test:///parentless.dart'),
    null,
  );
  addClass(parentless, 'C1');
  addClass(parentless, 'C2', typeParameters: ['E']);

  final Library lattice = library(Uri.parse(latticeUri), 'lattice');
  final Map<String, Class> byName = {};
  for (final (name, isAbstract, superclass, interfaces, typeParameterCount, _)
      in latticeClasses) {
    byName[name] = addClass(
      lattice,
      name,
      isAbstract: isAbstract,
      superclass: superclass == null ? null : byName[superclass],
      interfaces: [for (final String i in interfaces) byName[i]!],
      typeParameters: ['X', 'Y'].sublist(0, typeParameterCount),
    );
  }
  return component;
}
