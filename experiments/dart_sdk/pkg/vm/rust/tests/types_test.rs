// Port of test/transformations/type_flow/types_test.dart, as an oracle
// against upstream (see ../README.md), plus the generated lattice cases of
// oracle/types_lattice.dart.
//
// Upstream's test calls types.dart directly. oracle/build_types_inputs.dart
// runs it unchanged but for its `package:test` import, pointed at
// oracle/types_test_shim.dart, whose `expect` prints one line per
// expectation (`<ok|FAIL> | <test> | <reason> | <actual> | <expected>`)
// instead of stopping at the first failure. `upstream_types_test` below is
// the same test, statement for statement, on the port, printing the same
// lines through the same shim; the two texts must be identical.
//
// The test's classes are made in memory upstream; here they are the
// classes of the same names that oracle/types_lattice.dart writes to
// types.dill beside the mock SDK (`createMockSdkComponent`) the test
// uses: T1-T4 and C1-C3 in a `library dummy:` (upstream's `dummyLibrary`),
// and the 'types-builder' test's C1 and C2<E>, which have no library
// upstream and so print as their bare names (`TestTypeHierarchy.getTFClass`
// below names them so).
//
// `lattice_cases` replays oracle/types_lattice.dart's operations, over
// the same classes of types.dill, and must print its lattice_cases.txt.
//
// Environment:
//   DART       the Dart executable that runs oracle/build_types_inputs.dart
//              when the inputs are missing (default: `dart` on PATH; it has
//              to compile this checkout's pkg/front_end, so a Dart as new as
//              the checkout's).
//   TFA_ORACLE the inputs' directory (default: target/tfa_oracle under the
//              SDK root).
#![allow(non_snake_case, non_upper_case_globals)]

use std::cell::RefCell;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::rc::Rc;

use kernel::ast::*;
use kernel::binary::ast_from_binary::loadComponentFromBytes;
use kernel::class_hierarchy::ClassHierarchy;
use kernel::core_types::{CoreTypes, Nullability};
use kernel::reference_index::NodeIndex;
use kernel::src::printer::AstPrinter;
use kernel::type_environment::TypeEnvironment;
use vm::transformations::type_flow::Env;
use vm::transformations::type_flow::types::*;

fn sdk_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..").canonicalize().unwrap()
}

fn oracle_dir() -> PathBuf {
    match std::env::var("TFA_ORACLE") {
        Ok(dir) => {
            let dir = PathBuf::from(dir);
            if dir.is_absolute() { dir } else { sdk_root().join(dir) }
        }
        Err(_) => sdk_root().join("target/tfa_oracle"),
    }
}

fn inputs() -> PathBuf {
    let out = oracle_dir().join("types");
    if ["types_test.txt", "types.dill", "lattice_cases.txt"].iter().all(|f| out.join(f).exists()) {
        return out;
    }
    let dart = std::env::var("DART").unwrap_or_else(|_| "dart".into());
    let status = Command::new(dart)
        .arg(sdk_root().join("pkg/vm/rust/oracle/build_types_inputs.dart"))
        .arg(sdk_root())
        .arg(oracle_dir())
        .status()
        .expect("run oracle/build_types_inputs.dart");
    assert!(status.success(), "oracle/build_types_inputs.dart failed");
    out
}

/// Runs [f] on the environment of types.dill.
fn with_env<R>(f: impl FnOnce(&Env) -> R) -> R {
    let bytes = fs::read(inputs().join("types.dill")).unwrap();
    let component = loadComponentFromBytes(&bytes).unwrap();
    let index = NodeIndex::new(&component);
    let coreTypes = CoreTypes::newLenient(&index);
    let hierarchy = ClassHierarchy::new(&index, &coreTypes);
    let typeEnvironment = TypeEnvironment::new(&coreTypes, &hierarchy);
    let env = Env { index: &index, coreTypes: &coreTypes, hierarchy: &hierarchy, typeEnvironment: &typeEnvironment };
    f(&env)
}

/// The class [name] of the library [uri] in types.dill.
fn class(env: &Env, uri: &str, name: &str) -> CnId {
    kernel::core_types::getClass(env.index, uri, name).unwrap_or_else(|| panic!("no class {uri}::{name}"))
}

const dummyUri: &str = "dummy:";
const parentlessUri: &str = "org-dartlang-test:///parentless.dart";
const latticeUri: &str = "org-dartlang-test:///lattice.dart";

/// `nodeToText(classNode)`: classes of the parentless library stand for the
/// test's classes without a library, which print as their names.
fn classText(env: &Env, c: CnId) -> String {
    let library = env.index.classLibrary(c).unwrap();
    if env.index.importUri(library) == parentlessUri {
        env.index.string(env.index.class(c).unwrap().name)
    } else {
        AstPrinter::new(env.index, None).className(c)
    }
}

/// `TFClass(id, classNode, supertypes, recordShape)`.
fn tfClass(env: &Env, id: i64, c: CnId, supertypes: &[&Rc<TFClass>], recordShape: Option<RecordShape>) -> Rc<TFClass> {
    let mut ids = Vec::new();
    for s in supertypes {
        ids.extend(s.supertypes.iter().copied());
    }
    Rc::new(TFClass::new(id, c, ids, recordShape, classText(env, c)))
}

/// The shim's `expect`.
struct Expects {
    testName: String,
    lines: Vec<String>,
}

impl Expects {
    fn test(&mut self, name: &str) {
        self.testName = name.into();
    }

    fn expect(&mut self, actual: String, matches: bool, expected: String, reason: Option<String>) {
        let verdict = if matches { "ok" } else { "FAIL" };
        self.lines.push(format!("{verdict} | {} | {} | {actual} | {expected}", self.testName, reason.unwrap_or_default()));
    }

    /// `expect(actual, equals(expected), reason: reason)` on types.
    fn expectType(&mut self, env: &Env, actual: &Type, expected: &Type, reason: Option<String>) {
        self.expect(actual.toText(env), actual == expected, expected.toText(env), reason);
    }

    /// `expect(actual, isTrue/isFalse, reason: reason)`.
    fn expectBool(&mut self, actual: bool, expected: bool, reason: String) {
        self.expect(actual.to_string(), actual == expected, expected.to_string(), Some(reason));
    }
}

/// `TestTypeHierarchy`.
struct TestTypeHierarchy<'a> {
    env: &'a Env<'a>,
    classes: RefCell<HashMap<CnId, Rc<TFClass>>>,
    specializations: HashMap<CnId, Type>,
    classIdCounter: RefCell<i64>,
}

impl TypeHierarchy for TestTypeHierarchy<'_> {
    fn specializeTypeCone(&self, base: &Rc<TFClass>, _allowWideCone: bool) -> Type {
        self.specializations[&base.classNode].clone()
    }

    fn hasAllocatedSubtypes(&self, cls: &Rc<TFClass>) -> bool {
        !matches!(self.specializeTypeCone(cls, true), Type::Empty)
    }
}

impl TypesBuilder for TestTypeHierarchy<'_> {
    fn getTFClass(&self, c: CnId) -> Rc<TFClass> {
        if let Some(cls) = self.classes.borrow().get(&c) {
            return cls.clone();
        }
        *self.classIdCounter.borrow_mut() += 1;
        let cls = tfClass(self.env, *self.classIdCounter.borrow(), c, &[], None);
        self.classes.borrow_mut().insert(c, cls.clone());
        cls
    }

    fn getRecordClass(&self, _shape: &RecordShape) -> Rc<TFClass> {
        panic!("getRecordClass is not supported in the types test.")
    }
}

fn interfaceType(c: CnId, nullability: u8, typeArguments: Vec<DartType>) -> DartType {
    DartType::Interface { nullability, classReference: c, typeArguments }
}

/// test('types-builder').
fn typesBuilder(env: &Env, e: &mut Expects) {
    e.test("types-builder");
    let c1 = class(env, parentlessUri, "C1");
    let c2 = class(env, parentlessUri, "C2");

    let tb = TestTypeHierarchy {
        env,
        classes: RefCell::new(HashMap::new()),
        specializations: HashMap::new(),
        classIdCounter: RefCell::new(0),
    };
    let tfc1 = tb.getTFClass(c1);
    let tfc2 = tb.getTFClass(c2);
    let tfFunction = tb.getTFClass(env.coreTypes.functionClass);

    let t1 = interfaceType(c1, Nullability::nullable, vec![]);
    let t2Raw = interfaceType(c2, Nullability::nullable, vec![]);
    let t2Generic = interfaceType(c2, Nullability::nullable, vec![t1.clone()]);
    let t3 = DartType::Null;
    let f1 = DartType::Function(Box::new(FunctionType {
        nullability: Nullability::nullable,
        typeParameters: vec![],
        requiredParameterCount: 1,
        positionalParameters: vec![t1.clone()],
        namedParameters: vec![],
        returnType: Box::new(DartType::Void),
    }));

    let from = |t: &DartType, canBeNull: bool| fromStaticType(&tb, env, t, canBeNull);
    e.expectType(env, &from(&DartType::Never { nullability: Nullability::nonNullable }, false), &emptyType, None);
    e.expectType(env, &from(&DartType::Dynamic, true), &nullableAnyType(), None);
    e.expectType(env, &from(&DartType::Void, true), &nullableAnyType(), None);

    e.expectType(env, &from(&t1, false), &Type::Cone(tfc1.clone()), None);
    e.expectType(env, &from(&t2Raw, false), &Type::Cone(tfc2.clone()), None);
    e.expectType(env, &from(&t2Generic, false), &Type::Cone(tfc2.clone()), None);
    e.expectType(env, &from(&t3, false), &emptyType, None);
    e.expectType(env, &from(&f1, false), &Type::Cone(tfFunction.clone()), None);

    e.expectType(env, &from(&t1, true), &Type::Cone(tfc1.clone()).nullable(), None);
    e.expectType(env, &from(&t2Raw, true), &Type::Cone(tfc2.clone()).nullable(), None);
    e.expectType(env, &from(&t2Generic, true), &Type::Cone(tfc2.clone()).nullable(), None);
    e.expectType(env, &from(&t3, true), &nullableEmptyType(), None);
    e.expectType(env, &from(&f1, true), &Type::Cone(tfFunction.clone()).nullable(), None);

    e.expectType(env, &nullableAnyType(), &nullableAnyType(), None);
}

fn set(types: &[&Type]) -> Type {
    setType(types.iter().map(|t| t.concrete().unwrap().clone()).collect())
}

/// test('union-intersection').
fn unionIntersection(env: &Env, e: &mut Expects) {
    e.test("union-intersection");
    // T1 <: T3, T2 <: T3
    let c1 = class(env, dummyUri, "T1");
    let c2 = class(env, dummyUri, "T2");
    let c3 = class(env, dummyUri, "T3");
    let c4 = class(env, dummyUri, "T4");

    let tfc3 = tfClass(env, 3, c3, &[], None);
    let tfc1 = tfClass(env, 1, c1, &[&tfc3], None);
    let tfc2 = tfClass(env, 2, c2, &[&tfc3], None);
    let tfc4 = tfClass(env, 4, c4, &[], None);

    let empty = emptyType;
    let any = anyInstanceType;
    let concreteT1 = concreteType(&tfc1);
    let concreteT2 = concreteType(&tfc2);
    let concreteT3 = concreteType(&tfc3);
    let concreteT4 = concreteType(&tfc4);
    let coneT1 = Type::Cone(tfc1.clone());
    let coneT2 = Type::Cone(tfc2.clone());
    let coneT3 = Type::Cone(tfc3.clone());
    let coneT4 = Type::Cone(tfc4.clone());
    let setT12 = set(&[&concreteT1, &concreteT2]);
    let setT14 = set(&[&concreteT1, &concreteT4]);
    let setT23 = set(&[&concreteT2, &concreteT3]);
    let setT34 = set(&[&concreteT3, &concreteT4]);
    let setT123 = set(&[&concreteT1, &concreteT2, &concreteT3]);
    let setT124 = set(&[&concreteT1, &concreteT2, &concreteT4]);
    let setT1234 = set(&[&concreteT1, &concreteT2, &concreteT3, &concreteT4]);
    let nullableEmpty = empty.nullable();
    let nullableAny = any.nullable();
    let nullableConcreteT1 = concreteT1.nullable();
    let nullableConcreteT2 = concreteT2.nullable();
    let nullableConcreteT3 = concreteT3.nullable();
    let nullableConeT1 = coneT1.nullable();
    let nullableConeT3 = coneT3.nullable();
    let nullableConeT4 = coneT4.nullable();
    let nullableSetT12 = setT12.nullable();
    let nullableSetT14 = setT14.nullable();
    let nullableSetT23 = setT23.nullable();
    let nullableSetT34 = setT34.nullable();
    let nullableSetT123 = setT123.nullable();
    let nullableSetT124 = setT124.nullable();
    let nullableSetT1234 = setT1234.nullable();

    // [A, B, union, intersection]
    let testCases: Vec<[&Type; 4]> = vec![
        // empty
        [&empty, &empty, &empty, &empty],
        [&empty, &any, &any, &empty],
        [&empty, &concreteT1, &concreteT1, &empty],
        [&empty, &coneT1, &coneT1, &empty],
        [&empty, &setT12, &setT12, &empty],
        [&empty, &nullableEmpty, &nullableEmpty, &empty],
        [&empty, &nullableAny, &nullableAny, &empty],
        [&empty, &nullableConcreteT1, &nullableConcreteT1, &empty],
        [&empty, &nullableConeT1, &nullableConeT1, &empty],
        [&empty, &nullableSetT12, &nullableSetT12, &empty],
        // any
        [&any, &any, &any, &any],
        [&any, &concreteT1, &any, &concreteT1],
        [&any, &coneT1, &any, &coneT1],
        [&any, &setT12, &any, &setT12],
        [&any, &nullableEmpty, &nullableAny, &empty],
        [&any, &nullableAny, &nullableAny, &any],
        [&any, &nullableConcreteT1, &nullableAny, &concreteT1],
        [&any, &nullableConeT1, &nullableAny, &coneT1],
        [&any, &nullableSetT12, &nullableAny, &setT12],
        // nullableEmpty
        [&nullableEmpty, &concreteT1, &nullableConcreteT1, &empty],
        [&nullableEmpty, &coneT1, &nullableConeT1, &empty],
        [&nullableEmpty, &setT12, &nullableSetT12, &empty],
        [&nullableEmpty, &nullableEmpty, &nullableEmpty, &nullableEmpty],
        [&nullableEmpty, &nullableAny, &nullableAny, &nullableEmpty],
        [&nullableEmpty, &nullableConcreteT1, &nullableConcreteT1, &nullableEmpty],
        [&nullableEmpty, &nullableConeT1, &nullableConeT1, &nullableEmpty],
        [&nullableEmpty, &nullableSetT12, &nullableSetT12, &nullableEmpty],
        // nullableAny
        [&nullableAny, &concreteT1, &nullableAny, &concreteT1],
        [&nullableAny, &coneT1, &nullableAny, &coneT1],
        [&nullableAny, &setT12, &nullableAny, &setT12],
        [&nullableAny, &nullableAny, &nullableAny, &nullableAny],
        [&nullableAny, &nullableConcreteT1, &nullableAny, &nullableConcreteT1],
        [&nullableAny, &nullableConeT1, &nullableAny, &nullableConeT1],
        [&nullableAny, &nullableSetT12, &nullableAny, &nullableSetT12],
        // concrete
        [&concreteT1, &concreteT1, &concreteT1, &concreteT1],
        [&concreteT1, &concreteT2, &setT12, &empty],
        [&concreteT1, &coneT1, &coneT1, &concreteT1],
        [&concreteT1, &coneT2, &setT12, &empty],
        [&concreteT1, &coneT3, &coneT3, &concreteT1],
        [&concreteT1, &coneT4, &setT14, &empty],
        [&concreteT1, &setT12, &setT12, &concreteT1],
        [&concreteT1, &setT23, &setT123, &empty],
        [&concreteT1, &nullableConcreteT1, &nullableConcreteT1, &concreteT1],
        [&concreteT1, &nullableConcreteT2, &nullableSetT12, &empty],
        [&concreteT1, &nullableConeT1, &nullableConeT1, &concreteT1],
        [&concreteT1, &nullableConeT3, &nullableConeT3, &concreteT1],
        [&concreteT1, &nullableConeT4, &nullableSetT14, &empty],
        [&concreteT1, &nullableSetT12, &nullableSetT12, &concreteT1],
        [&concreteT1, &nullableSetT23, &nullableSetT123, &empty],
        // cone
        [&coneT1, &coneT1, &coneT1, &coneT1],
        [&coneT1, &coneT2, &setT12, &empty],
        [&coneT1, &coneT3, &coneT3, &coneT1],
        [&coneT3, &coneT4, &setT1234, &empty],
        [&coneT1, &setT12, &setT12, &concreteT1],
        [&coneT1, &setT23, &setT123, &empty],
        [&coneT3, &setT12, &setT123, &setT12],
        [&coneT3, &setT1234, &setT1234, &setT123],
        [&coneT1, &nullableConcreteT1, &nullableConeT1, &concreteT1],
        [&coneT1, &nullableConcreteT2, &nullableSetT12, &empty],
        [&coneT3, &nullableConcreteT2, &nullableConeT3, &concreteT2],
        [&coneT1, &nullableConeT1, &nullableConeT1, &coneT1],
        [&coneT1, &nullableConeT3, &nullableConeT3, &coneT1],
        [&coneT1, &nullableConeT4, &nullableSetT14, &empty],
        [&coneT1, &nullableSetT12, &nullableSetT12, &concreteT1],
        [&coneT3, &nullableSetT23, &nullableSetT123, &setT23],
        // set
        [&setT12, &setT12, &setT12, &setT12],
        [&setT12, &setT123, &setT123, &setT12],
        [&setT12, &setT23, &setT123, &concreteT2],
        [&setT12, &setT34, &setT1234, &empty],
        [&setT12, &nullableConcreteT1, &nullableSetT12, &concreteT1],
        [&setT12, &nullableConcreteT3, &nullableSetT123, &empty],
        [&setT12, &nullableConeT1, &nullableSetT12, &concreteT1],
        [&setT12, &nullableConeT3, &nullableSetT123, &setT12],
        [&setT12, &nullableConeT4, &nullableSetT124, &empty],
        [&setT12, &nullableSetT12, &nullableSetT12, &setT12],
        [&setT12, &nullableSetT123, &nullableSetT123, &setT12],
        [&setT12, &nullableSetT23, &nullableSetT123, &concreteT2],
        [&setT12, &nullableSetT34, &nullableSetT1234, &empty],
        // nullableConcrete
        [&nullableConcreteT1, &nullableConcreteT1, &nullableConcreteT1, &nullableConcreteT1],
        [&nullableConcreteT1, &nullableConcreteT2, &nullableSetT12, &nullableEmpty],
        [&nullableConcreteT1, &nullableConeT1, &nullableConeT1, &nullableConcreteT1],
        [&nullableConcreteT1, &nullableConeT3, &nullableConeT3, &nullableConcreteT1],
        [&nullableConcreteT1, &nullableConeT4, &nullableSetT14, &nullableEmpty],
        [&nullableConcreteT1, &nullableSetT12, &nullableSetT12, &nullableConcreteT1],
        [&nullableConcreteT1, &nullableSetT23, &nullableSetT123, &nullableEmpty],
        // nullableCone
        [&nullableConeT1, &nullableConeT1, &nullableConeT1, &nullableConeT1],
        [&nullableConeT1, &nullableConeT3, &nullableConeT3, &nullableConeT1],
        [&nullableConeT1, &nullableConeT4, &nullableSetT14, &nullableEmpty],
        [&nullableConeT1, &nullableSetT12, &nullableSetT12, &nullableConcreteT1],
        [&nullableConeT1, &nullableSetT23, &nullableSetT123, &nullableEmpty],
        [&nullableConeT3, &nullableSetT14, &nullableSetT1234, &nullableConcreteT1],
        // nullableSet
        [&nullableSetT12, &nullableSetT12, &nullableSetT12, &nullableSetT12],
        [&nullableSetT12, &nullableSetT23, &nullableSetT123, &nullableConcreteT2],
        [&nullableSetT12, &nullableSetT34, &nullableSetT1234, &nullableEmpty],
    ];

    let hierarchy = TestTypeHierarchy {
        env,
        // classes
        classes: RefCell::new(HashMap::from([(c1, tfc1.clone()), (c2, tfc2.clone()), (c3, tfc3.clone()), (c4, tfc4.clone())])),
        // specializations
        specializations: HashMap::from([
            (c1, concreteT1.clone()),
            (c2, concreteT2.clone()),
            (c3, setT123.clone()),
            (c4, concreteT4.clone()),
        ]),
        classIdCounter: RefCell::new(0),
    };

    for [a, b, union, intersection] in testCases {
        let t = |x: &Type| x.toText(env);
        e.expectType(env, &a.union(b, &hierarchy), union, Some(format!("Test case: UNION({}, {}) = {}", t(a), t(b), t(union))));
        e.expectType(env, &b.union(a, &hierarchy), union, Some(format!("Test case: UNION({}, {}) = {}", t(b), t(a), t(union))));
        e.expectType(
            env,
            &a.intersection(b, &hierarchy),
            intersection,
            Some(format!("Test case: INTERSECTION({}, {}) = {}", t(a), t(b), t(intersection))),
        );
        e.expectType(
            env,
            &b.intersection(a, &hierarchy),
            intersection,
            Some(format!("Test case: INTERSECTION({}, {}) = {}", t(b), t(a), t(intersection))),
        );
    }
}

/// A value the 'hashcode-equals' test compares: a kernel `InterfaceType`
/// or a type of the analysis.
enum Value<'a> {
    Kernel(&'a DartType),
    Tf(&'a Type),
}

impl Value<'_> {
    fn text(&self, env: &Env) -> String {
        match self {
            // `DartType.toString()` (the default `AstTextStrategy`, no
            // library names): what upstream's reasons print.
            Value::Kernel(DartType::Interface { nullability, classReference, typeArguments }) => {
                assert!(typeArguments.is_empty());
                let name = env.index.string(env.index.class(*classReference).unwrap().name);
                format!("InterfaceType({name}{})", kernel::src::printer::nullabilityToString(*nullability))
            }
            Value::Kernel(t) => panic!("not in the test: {t:?}"),
            Value::Tf(t) => t.toText(env),
        }
    }

    fn equals(&self, other: &Value) -> bool {
        match (self, other) {
            (Value::Kernel(a), Value::Kernel(b)) => a == b,
            (Value::Tf(a), Value::Tf(b)) => a == b,
            _ => false,
        }
    }

    /// `hashCode`. An `InterfaceType` hashes its class node by identity
    /// upstream; its reference stands in for it here.
    fn hashCode(&self) -> i64 {
        match self {
            Value::Kernel(DartType::Interface { nullability, classReference, .. }) => {
                combineHashes(combineHashes(0x3f2a, *classReference as i64), *nullability as i64)
            }
            Value::Kernel(t) => panic!("not in the test: {t:?}"),
            Value::Tf(t) => t.hashCode(),
        }
    }
}

/// test('hashcode-equals').
fn hashcodeEquals(env: &Env, e: &mut Expects) {
    e.test("hashcode-equals");
    let c1 = class(env, dummyUri, "C1");
    let c2 = class(env, dummyUri, "C2");
    let c3 = class(env, dummyUri, "C3");

    let tfc1 = tfClass(env, 1, c1, &[], None);
    let tfc2 = tfClass(env, 2, c2, &[], None);
    let tfc3 = tfClass(env, 3, c3, &[], None);

    let t1a = interfaceType(c1, Nullability::nonNullable, vec![]);
    let t1b = interfaceType(c1, Nullability::nonNullable, vec![]);
    let t2 = interfaceType(c2, Nullability::nonNullable, vec![]);

    let ne = |e: &mut Expects, a: Value, b: Value| {
        let (ta, tb) = (a.text(env), b.text(env));
        e.expectBool(a.equals(&b), false, format!("Test case: {ta} != {tb}"));
        // Hash codes can be the same, but it is unlikely.
        e.expectBool(a.hashCode() == b.hashCode(), false, format!("Test case: {ta}.hashCode != {tb}.hashCode"));
    };
    let eq = |e: &mut Expects, a: Value, b: Value| {
        let (ta, tb) = (a.text(env), b.text(env));
        e.expectBool(a.equals(&b), true, format!("Test case: {ta} == {tb}"));
        e.expectBool(a.hashCode() == b.hashCode(), true, format!("Test case: {ta}.hashCode == {tb}.hashCode"));
    };
    use Value::Tf;
    eq(e, Value::Kernel(&t1a), Value::Kernel(&t1b));
    ne(e, Value::Kernel(&t1a), Value::Kernel(&t2));

    let k1 = concreteType(&tfc1);
    let k2 = concreteType(&tfc2);
    let k3 = concreteType(&tfc3);
    let cone1 = Type::Cone(tfc1.clone());
    let cone2 = Type::Cone(tfc2.clone());
    let set12 = || set(&[&k1, &k2]);
    let set123 = || set(&[&k1, &k2, &k3]);
    let set13 = || set(&[&k1, &k3]);

    eq(e, Tf(&emptyType), Tf(&emptyType));
    ne(e, Tf(&emptyType), Tf(&anyInstanceType));
    ne(e, Tf(&emptyType), Tf(&k1));
    ne(e, Tf(&emptyType), Tf(&cone1));
    ne(e, Tf(&emptyType), Tf(&set12()));
    ne(e, Tf(&emptyType), Tf(&nullableEmptyType()));

    eq(e, Tf(&anyInstanceType), Tf(&anyInstanceType));
    ne(e, Tf(&anyInstanceType), Tf(&k1));
    ne(e, Tf(&anyInstanceType), Tf(&cone1));
    ne(e, Tf(&anyInstanceType), Tf(&set12()));
    ne(e, Tf(&anyInstanceType), Tf(&nullableEmptyType()));

    eq(e, Tf(&k1), Tf(&k1));
    ne(e, Tf(&k1), Tf(&k2));
    ne(e, Tf(&k1), Tf(&cone1));
    ne(e, Tf(&k1), Tf(&cone2));
    ne(e, Tf(&k1), Tf(&set12()));
    ne(e, Tf(&k1), Tf(&k1.nullable()));

    eq(e, Tf(&cone1), Tf(&cone1));
    ne(e, Tf(&cone1), Tf(&cone2));
    ne(e, Tf(&cone1), Tf(&set12()));
    ne(e, Tf(&cone1), Tf(&cone1.nullable()));

    eq(e, Tf(&set12()), Tf(&set12()));
    eq(e, Tf(&set123()), Tf(&set123()));
    ne(e, Tf(&set12()), Tf(&set123()));
    ne(e, Tf(&set12()), Tf(&set13()));
    ne(e, Tf(&set12()), Tf(&set12().nullable()));
}

#[test]
fn upstream_types_test() {
    let expected = fs::read_to_string(inputs().join("types_test.txt")).unwrap();
    let actual = with_env(|env| {
        let mut e = Expects { testName: String::new(), lines: Vec::new() };
        typesBuilder(env, &mut e);
        unionIntersection(env, &mut e);
        hashcodeEquals(env, &mut e);
        let mut text = e.lines.join("\n");
        text.push('\n');
        text
    });
    let _ = fs::write(inputs().join("types_test.rust.txt"), &actual);
    compare("types_test", &actual, &expected);
}

/// Compares line by line and reports the count of identical lines.
fn compare(name: &str, actual: &str, expected: &str) {
    let a: Vec<&str> = actual.lines().collect();
    let x: Vec<&str> = expected.lines().collect();
    let same = a.iter().zip(&x).filter(|(p, q)| p == q).count();
    eprintln!("{name}: {same} of {} lines identical (port printed {})", x.len(), a.len());
    let mut shown = 0;
    for (i, (p, q)) in a.iter().zip(&x).enumerate() {
        if p != q && shown < 20 {
            eprintln!("line {}:\n  port:     {p}\n  upstream: {q}", i + 1);
            shown += 1;
        }
    }
    assert!(actual == expected, "{name}: the port's text differs from upstream's");
}

/// The lattice's hierarchy (`LatticeTypeHierarchy` of
/// oracle/types_lattice.dart).
struct LatticeTypeHierarchy {
    specializations: RefCell<HashMap<i64, Type>>,
}

impl TypeHierarchy for LatticeTypeHierarchy {
    fn specializeTypeCone(&self, base: &Rc<TFClass>, _allowWideCone: bool) -> Type {
        self.specializations.borrow()[&base.id].clone()
    }

    fn hasAllocatedSubtypes(&self, cls: &Rc<TFClass>) -> bool {
        !matches!(self.specializeTypeCone(cls, true), Type::Empty)
    }
}

/// The type notation of oracle/types_lattice.dart.
struct Parser<'a, 'e> {
    env: &'a Env<'e>,
    classes: &'a HashMap<i64, Rc<TFClass>>,
    pool: &'a [Type],
}

impl Parser<'_, '_> {
    fn parse(&self, tokens: &mut std::collections::VecDeque<String>) -> Type {
        let env = self.env;
        let mut next = || tokens.pop_front().expect("more tokens");
        let head = next();
        let int = |tokens: &mut std::collections::VecDeque<String>| -> i64 { tokens.pop_front().unwrap().parse().unwrap() };
        match head.as_str() {
            "E" => emptyType,
            "A" => anyInstanceType,
            "U" => unknownType,
            "N" => self.parse(tokens).nullable(),
            "K" => concreteType(&self.classes[&int(tokens)]),
            "KC" => {
                let cls = &self.classes[&int(tokens)];
                constantConcreteType(cls, TFConstant::Int(int(tokens)), None, env)
            }
            "KT" => {
                let cls = &self.classes[&int(tokens)];
                let constant = tokens.pop_front().unwrap();
                let count = int(tokens);
                let args: Vec<Type> = (0..count).map(|_| self.parse(tokens)).collect();
                if constant == "-" {
                    classConcreteType(cls, args, None, env)
                } else {
                    constantConcreteType(cls, TFConstant::Int(constant.parse().unwrap()), Some(args), env)
                }
            }
            "C" => Type::Cone(self.classes[&int(tokens)].clone()),
            "W" => Type::WideCone(self.classes[&int(tokens)].clone()),
            "S" => {
                let count = int(tokens);
                setType((0..count).map(|_| self.parse(tokens).concrete().unwrap().clone()).collect())
            }
            "R" => {
                let cls = self.classes[&int(tokens)].clone();
                let count = int(tokens);
                recordConcreteType(&cls, (0..count).map(|_| self.parse(tokens)).collect())
            }
            "RT" => {
                let c = env.coreTypes;
                let t = match tokens.pop_front().unwrap().as_str() {
                    "dyn" => DartType::Dynamic,
                    "never" => DartType::Never { nullability: Nullability::nonNullable },
                    "null" => DartType::Null,
                    "int" => c.nonNullableRawType(c.intClass),
                    "intq" => c.nullableRawType(c.intClass),
                    "num" => c.nonNullableRawType(c.numClass),
                    "objq" => c.nullableRawType(c.objectClass),
                    other => panic!("unknown runtime type {other}"),
                };
                Type::Runtime(Rc::new(RuntimeType::new(t, None, env)))
            }
            "P" => self.pool[int(tokens) as usize].clone(),
            other => panic!("unknown type notation {other}"),
        }
    }

    fn parseAll(&self, text: &str) -> Type {
        let mut tokens: std::collections::VecDeque<String> = text.split(' ').map(String::from).collect();
        let t = self.parse(&mut tokens);
        assert!(tokens.is_empty(), "trailing tokens in {text}");
        t
    }
}

fn latticeCases(env: &Env, cases: &str) -> String {
    let mut classes: HashMap<i64, Rc<TFClass>> = HashMap::new();
    let hierarchy = LatticeTypeHierarchy { specializations: RefCell::new(HashMap::new()) };
    let mut pool: Vec<Type> = Vec::new();
    let mut typeSets: Vec<Type> = Vec::new();
    let mut out = String::new();
    for line in cases.lines() {
        let (input, _) = line.split_once(" = ").unwrap_or((line, ""));
        let words: Vec<&str> = input.split(' ').collect();
        let index = |i: usize| words[i].parse::<usize>().unwrap();
        let result: Option<String> = match words[0] {
            "class" => {
                let id: i64 = words[1].parse().unwrap();
                let c = class(env, latticeUri, words[2]);
                let supertypes: Vec<i64> = words[3..].iter().map(|w| w.parse().unwrap()).collect();
                classes.insert(id, Rc::new(TFClass::new(id, c, supertypes, None, classText(env, c))));
                None
            }
            "record" => {
                let id: i64 = words[1].parse().unwrap();
                let c = class(env, latticeUri, words[2]);
                let named: Vec<String> = if words[4] == "-" { vec![] } else { words[4].split(',').map(String::from).collect() };
                let shape = RecordShape { numPositionalFields: words[3].parse().unwrap(), namedFields: named };
                classes.insert(id, Rc::new(TFClass::new(id, c, [], Some(shape), classText(env, c))));
                None
            }
            "spec" => {
                let id: i64 = words[1].parse().unwrap();
                let parser = Parser { env, classes: &classes, pool: &pool };
                let spec = parser.parseAll(&words[2..].join(" "));
                let text = spec.toText(env);
                hierarchy.specializations.borrow_mut().insert(id, spec);
                Some(text)
            }
            "type" => {
                let parser = Parser { env, classes: &classes, pool: &pool };
                let t = parser.parseAll(&words[2..].join(" "));
                let text = t.toText(env);
                pool.push(t);
                Some(text)
            }
            "typeSet" => {
                let parser = Parser { env, classes: &classes, pool: &pool };
                let t = parser.parseAll(&words[2..].join(" "));
                let text = t.toText(env);
                typeSets.push(t);
                Some(text)
            }
            op => {
                let h = &hierarchy;
                let text = |t: Type| t.toText(env);
                Some(match op {
                    "nullable" => text(pool[index(1)].nullable()),
                    "isSpecialized" => pool[index(1)].isSpecialized().to_string(),
                    "specialize" => text(pool[index(1)].specialize(h)),
                    "hasEmptySpecialization" => pool[index(1)].hasEmptySpecialization(h).to_string(),
                    "isSubtypeOf" => pool[index(1)].isSubtypeOf(&classes[&(index(2) as i64)]).to_string(),
                    "hash" => pool[index(1)].hashCode().to_string(),
                    "eq" => (pool[index(1)] == pool[index(2)]).to_string(),
                    "union" => text(pool[index(1)].union(&pool[index(2)], h)),
                    "intersection" => text(pool[index(1)].intersection(&pool[index(2)], h)),
                    "union3" => text(pool[index(1)].union(&pool[index(2)], h).union(&pool[index(3)], h)),
                    "intersection3" => text(pool[index(1)].intersection(&pool[index(2)], h).intersection(&pool[index(3)], h)),
                    "unionIntersection" => text(pool[index(1)].union(&pool[index(2)], h).intersection(&pool[index(3)], h)),
                    "typeSetEq" => (typeSets[index(1)] == typeSets[index(2)]).to_string(),
                    "typeSetIntersection" => text(typeSets[index(1)].intersection(&typeSets[index(2)], h)),
                    "typeSetUnion" => text(typeSets[index(1)].union(&typeSets[index(2)], h)),
                    other => panic!("unknown operation {other}"),
                })
            }
        };
        out.push_str(input);
        if let Some(r) = result {
            out.push_str(" = ");
            out.push_str(&r);
        }
        out.push('\n');
    }
    out
}

#[test]
fn lattice_cases() {
    let expected = fs::read_to_string(inputs().join("lattice_cases.txt")).unwrap();
    let actual = with_env(|env| latticeCases(env, &expected));
    let _ = fs::write(inputs().join("lattice_cases.rust.txt"), &actual);
    compare("lattice_cases", &actual, &expected);
}
