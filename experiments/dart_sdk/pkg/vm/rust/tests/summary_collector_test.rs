// Port of test/transformations/type_flow/summary_collector_test.dart, as an
// oracle against upstream (see ../README.md).
//
// Upstream's test compiles each program under
// testcases/transformations/type_flow/summary_collector, prints the summary
// of every member of its main library (and of every local function in it)
// with `PrintSummaries`, and compares the text with the program's `.expect`
// file. Here the program's kernel comes from oracle/build_inputs.dart, which
// compiles it the same way, writes it to a `.dill` and checks that
// upstream's own `PrintSummaries` reproduces the `.expect` file both from
// the component in memory and from the `.dill` read back. The Rust port
// reads that `.dill` and must print the `.expect` file byte for byte; the
// `.expect` files are upstream's, unchanged.
//
// Environment:
//   DART       the Dart executable that runs oracle/build_inputs.dart when
//              the inputs are missing (default: `dart` on PATH).
//   TFA_ORACLE the inputs' directory (default: target/tfa_oracle under the
//              SDK root).
#![allow(non_snake_case)]

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use kernel::ast::*;
use kernel::binary::ast_from_binary::loadComponentFromBytes;
use kernel::class_hierarchy::{ClassHierarchy, PROCEDURE_ABSTRACT};
use kernel::core_types::CoreTypes;
use kernel::reference_index::{MemberNode, NodeIndex};
use kernel::src::printer::AstPrinter;
use kernel::type_environment::TypeEnvironment;
use kernel::visitor::{Node, children};
use vm::modular::target::vm::VmTarget;
use vm::transformations::type_flow::Env;
use vm::transformations::type_flow::analysis::{EntryPointsListener, GenericInterfacesInfoImpl};
use vm::transformations::type_flow::calls::Selector;
use vm::transformations::type_flow::summary_collector::{LocalFunction, SharedVariableBuilder, SummaryCollector};
use vm::transformations::type_flow::types::*;

fn sdk_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .canonicalize()
        .unwrap()
}

fn testcases_dir() -> PathBuf {
    sdk_root().join("pkg/vm/testcases/transformations/type_flow/summary_collector")
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

/// The testcases, as the test finds them: every `.dart` file in the
/// directory, by path.
fn testcases() -> Vec<String> {
    let mut names: Vec<String> = fs::read_dir(testcases_dir())
        .unwrap()
        .map(|e| e.unwrap().file_name().into_string().unwrap())
        .filter(|n| n.ends_with(".dart"))
        .map(|n| n.trim_end_matches(".dart").to_string())
        .collect();
    names.sort();
    names
}

fn ensure_inputs() {
    let out = oracle_dir().join("summary_collector");
    if testcases().iter().all(|n| out.join(format!("{n}.dill")).exists()) {
        return;
    }
    let dart = std::env::var("DART").unwrap_or_else(|_| "dart".into());
    let status = Command::new(dart)
        .arg(sdk_root().join("pkg/vm/rust/oracle/build_inputs.dart"))
        .arg(sdk_root())
        .arg(oracle_dir())
        .status()
        .expect("run oracle/build_inputs.dart");
    assert!(status.success(), "oracle/build_inputs.dart failed");
}

/// `FakeTypesBuilder`: a class per kernel class (and per record shape), with
/// ids in the order they are asked for.
struct FakeTypesBuilder<'a> {
    env: &'a Env<'a>,
    classes: RefCell<HashMap<CnId, Rc<TFClass>>>,
    recordClasses: RefCell<Vec<(RecordShape, Rc<TFClass>)>>,
    classIdCounter: RefCell<i64>,
}

impl TypesBuilder for FakeTypesBuilder<'_> {
    fn getTFClass(&self, c: CnId) -> Rc<TFClass> {
        if let Some(cls) = self.classes.borrow().get(&c) {
            return cls.clone();
        }
        *self.classIdCounter.borrow_mut() += 1;
        let cls = Rc::new(TFClass { id: *self.classIdCounter.borrow(), classNode: c, recordShape: None });
        self.classes.borrow_mut().insert(c, cls.clone());
        cls
    }

    fn getRecordClass(&self, shape: &RecordShape) -> Rc<TFClass> {
        if let Some((_, cls)) = self.recordClasses.borrow().iter().find(|(s, _)| s == shape) {
            return cls.clone();
        }
        *self.classIdCounter.borrow_mut() += 1;
        let record = VmTarget::new(self.env.index).getRecordImplementationClass();
        let cls = Rc::new(TFClass { id: *self.classIdCounter.borrow(), classNode: record, recordShape: Some(shape.clone()) });
        self.recordClasses.borrow_mut().push((shape.clone(), cls.clone()));
        cls
    }
}

/// `FakeEntryPointsListener`.
struct FakeEntryPointsListener<'a> {
    typesBuilder: &'a FakeTypesBuilder<'a>,
}

impl EntryPointsListener for FakeEntryPointsListener<'_> {
    fn addRawCall(&self, _selector: Selector) {}
    fn addFieldUsedInConstant(&self, _field: &MemberId, _instance: &Type, _value: &Type) {}
    fn addAllocatedClass(&self, c: CnId) -> Type {
        concreteType(&self.typesBuilder.getTFClass(c))
    }
    fn addAllocatedRecord(&self, shape: &RecordShape) -> Type {
        concreteType(&self.typesBuilder.getRecordClass(shape))
    }
    fn getRecordPositionalField(&self, shape: &RecordShape, pos: usize) -> MemberId {
        self.getRecordNamedField(shape, &shape.fieldName(pos))
    }
    fn getRecordNamedField(&self, _shape: &RecordShape, name: &str) -> MemberId {
        MemberId::SyntheticField(name.to_string())
    }
    fn recordMemberCalledViaThis(&self, _target: &MemberId) {}
    fn recordTearOff(&self, _target: CnId) {}
    fn getClosureCallMethod(&self, closure: &Closure) -> MemberId {
        MemberId::ClosureCall(Box::new(closure.clone()))
    }
}

/// `FakeSharedVariableBuilder`.
struct FakeSharedVariableBuilder;

impl SharedVariableBuilder for FakeSharedVariableBuilder {
    fn getSharedVariable(&self, variable: &Variable, env: &Env) -> String {
        let name = env.index.string(variable.name);
        if name.is_empty() { "__tmp".into() } else { name }
    }
    fn getSharedCapturedThis(&self, member: CnId, env: &Env) -> String {
        format!("{}::this", MemberId::Node(member).toText(env))
    }
}

/// `PrintSummaries.print`: the summaries of the main library's members, and
/// of every local function in them, in visiting order.
fn print_summaries(component: &Component) -> String {
    let index = NodeIndex::new(component);
    let coreTypes = CoreTypes::new(&index);
    let hierarchy = ClassHierarchy::new(&index, &coreTypes);
    let typeEnvironment = TypeEnvironment::new(&coreTypes, &hierarchy);
    let env = Env { index: &index, coreTypes: &coreTypes, hierarchy: &hierarchy, typeEnvironment: &typeEnvironment };
    let typesBuilder = FakeTypesBuilder {
        env: &env,
        classes: RefCell::new(HashMap::new()),
        recordClasses: RefCell::new(Vec::new()),
        classIdCounter: RefCell::new(0),
    };
    let listener = FakeEntryPointsListener { typesBuilder: &typesBuilder };
    let gii = GenericInterfacesInfoImpl::new(&env);
    let shared = FakeSharedVariableBuilder;
    let mut collector = SummaryCollector::new(&env, &listener, &typesBuilder, &gii, &shared);

    let library = index.enclosingLibrary(component.mainMethod.expect("main")).unwrap();
    let mut members: Vec<MemberNode> = Vec::new();
    for class in &library.classes {
        members.extend(class.constructors.iter().map(MemberNode::Constructor));
        members.extend(class.procedures.iter().map(MemberNode::Procedure));
        members.extend(class.fields.iter().map(MemberNode::Field));
    }
    for declaration in &library.extensionTypeDeclarations {
        members.extend(declaration.procedures.iter().map(MemberNode::Procedure));
    }
    members.extend(library.procedures.iter().map(MemberNode::Procedure));
    members.extend(library.fields.iter().map(MemberNode::Field));

    let mut buf = String::new();
    for member in members {
        let isAbstract = matches!(member, MemberNode::Procedure(p) if p.flags & PROCEDURE_ABSTRACT != 0);
        let isFieldWithoutInitializer = matches!(member, MemberNode::Field(f) if f.initializer.is_none());
        if isAbstract || isFieldWithoutInitializer {
            continue;
        }
        let name = AstPrinter::new(&index, None).qualifiedMemberName(member.reference(), false);
        buf.push_str(&format!("------------ {name} ------------\n"));
        buf.push_str(&collector.createSummary(member, None).toText(&env));
        buf.push('\n');
        // visitFunctionExpression / visitFunctionDeclaration, in visiting
        // order, nested ones after their enclosing one.
        let mut locals = Vec::new();
        let root = match member {
            MemberNode::Field(f) => Node::Expression(f.initializer.as_ref().unwrap()),
            MemberNode::Procedure(p) => Node::FunctionNode(&p.function),
            MemberNode::Constructor(_) => Node::FunctionNode(member.function().unwrap()),
        };
        let mut roots = Vec::new();
        if let MemberNode::Constructor(c) = member {
            for a in &c.annotations {
                roots.push(Node::Expression(a));
            }
            for i in &c.initializers {
                roots.push(Node::Initializer(i));
            }
            roots.push(root);
        } else {
            for a in member.annotations() {
                roots.push(Node::Expression(a));
            }
            roots.push(root);
        }
        fn walk<'a>(node: Node<'a>, out: &mut Vec<LocalFunction<'a>>) {
            match node {
                Node::Expression(Expression::FunctionExpression { function, fileOffset, .. }) => {
                    out.push(LocalFunction { function, fileOffset: *fileOffset, variable: None });
                }
                Node::Statement(Statement::FunctionDeclaration { variable, function, fileOffset, .. }) => {
                    out.push(LocalFunction { function, fileOffset: *fileOffset, variable: Some(variable) });
                }
                _ => {}
            }
            for c in children(node) {
                walk(c, out);
            }
        }
        for r in roots {
            walk(r, &mut locals);
        }
        for local in locals {
            buf.push_str(&format!("------------ {} ------------\n", local.name(&env, member.fileUri())));
            buf.push_str(&collector.createSummary(member, Some(local)).toText(&env));
            buf.push('\n');
        }
    }
    buf
}

/// `findFirstDifference` of test/common_test_utils.dart.
fn first_difference(actual: &str, expected: &str) -> String {
    let a: Vec<&str> = actual.split('\n').collect();
    let e: Vec<&str> = expected.split('\n').collect();
    let mut i = 0;
    while i < a.len() && i < e.len() {
        if a[i] != e[i] {
            return format!("line {}:\n  actual:   {}\n  expected: {}", i + 1, a[i], e[i]);
        }
        i += 1;
    }
    format!(
        "line {}:\n  actual:   {}\n  expected: {}",
        i + 1,
        a.get(i).copied().unwrap_or("<END>"),
        e.get(i).copied().unwrap_or("<END>")
    )
}

#[test]
fn collect_summary() {
    ensure_inputs();
    let out = oracle_dir().join("summary_collector");
    let names = testcases();
    let mut passed = Vec::new();
    let mut failed = Vec::new();
    for name in &names {
        let expect_path = testcases_dir().join(format!("{name}.dart.expect"));
        let expected = fs::read_to_string(&expect_path).unwrap_or_default();
        // The harness: upstream printed exactly the .expect file from this
        // .dill (oracle/build_inputs.dart checks it; this re-checks the
        // copy it left).
        let upstream = fs::read_to_string(out.join(format!("{name}.upstream.txt"))).unwrap();
        assert_eq!(upstream, expected, "{name}: upstream's output from the .dill is not the .expect file");

        let bytes = fs::read(out.join(format!("{name}.dill"))).unwrap();
        let component = loadComponentFromBytes(&bytes).unwrap();
        let actual = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| print_summaries(&component)));
        match actual {
            Ok(actual) if actual == expected => {
                let _ = fs::write(out.join(format!("{name}.rust.txt")), &actual);
                passed.push(name.clone())
            }
            Ok(actual) => {
                let _ = fs::write(out.join(format!("{name}.rust.txt")), &actual);
                failed.push(format!("{name}: first difference at {}", first_difference(&actual, &expected)));
            }
            Err(panic) => {
                let message = panic
                    .downcast_ref::<String>()
                    .cloned()
                    .or_else(|| panic.downcast_ref::<&str>().map(|s| s.to_string()))
                    .unwrap_or_default();
                failed.push(format!("{name}: panicked: {message}"));
            }
        }
    }
    eprintln!("summary_collector: {} of {} testcases identical to their .expect", passed.len(), names.len());
    for f in &failed {
        eprintln!("FAIL {f}");
    }
    assert!(failed.is_empty(), "{} of {} testcases differ", failed.len(), names.len());
}
