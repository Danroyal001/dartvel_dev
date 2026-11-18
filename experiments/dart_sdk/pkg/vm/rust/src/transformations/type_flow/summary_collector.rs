// Port of lib/transformations/type_flow/summary_collector.dart: builds the
// summary of a member (or of a local function in it) from its kernel, and
// normalizes it (`_SummaryNormalizer`), with the variable analysis
// (`_VariablesInfoCollector`), `RuntimeTypeTranslatorImpl` and
// `ConstantAllocationCollector` it uses. The `simplify` methods of
// summary.dart's statements are ported here too, beside the normalizer
// that calls them.
//
// Not ported yet: native procedures (`NativeCodeOracle`), the protobuf
// handler, `UsedFieldsCollector`, field guard summaries, and the side
// tables the transformer reads (`callSites`, `explicitCasts`, ...).
use std::collections::{HashMap, HashSet};
use std::rc::Rc;

use kernel::ast::*;
use kernel::binary::tag::Tag;
use kernel::core_types::{Nullability, getMember};
use kernel::reference_index::MemberNode;
use kernel::src::printer::{AstPrinter, VariableFlags};
use kernel::type_algebra::{Substitution, nullability};
use kernel::type_environment::{StaticTypeContext, constantType};
use kernel::visitor::{Node, children};

use super::Env;
use super::analysis::{EntryPointsListener, GenericInterfacesInfoImpl};
use super::calls::{Args, CallKind, Selector};
use super::summary::{BinaryOp, Statement as SStatement, StatementKind, StmtId, Summary, TypeExpr, UnaryOp};
use super::types::*;
use crate::modular::target::vm::VmTarget;

/// `SharedVariableBuilder`: names the variables shared between a function
/// and its closures (summaries print a shared variable by its name).
pub trait SharedVariableBuilder {
    fn getSharedVariable(&self, variable: &Variable, env: &Env) -> String;
    fn getSharedCapturedThis(&self, member: CnId, env: &Env) -> String;
}

/// A local function (`FunctionDeclaration` or `FunctionExpression`), by
/// identity, with what the analysis prints for it.
#[derive(Debug, Clone, Copy)]
pub struct LocalFunction<'a> {
    pub function: &'a FunctionNode,
    pub fileOffset: Offset,
    /// The declared variable of a `FunctionDeclaration`.
    pub variable: Option<&'a Variable>,
}

impl<'a> LocalFunction<'a> {
    pub fn key(&self) -> usize {
        self.function as *const FunctionNode as usize
    }

    /// `localFunctionName`.
    pub fn name(&self, env: &Env, fileUri: UriId) -> String {
        match self.variable {
            Some(v) => env.index.string(v.name),
            None => {
                let component = env.index.component;
                let uri = String::from_utf8_lossy(component.uris.get(fileUri)).into_owned();
                let file = uri.rsplit('/').next().unwrap_or("").to_string();
                match component.sources.get(fileUri as usize).and_then(|s| s.as_ref()) {
                    Some(source) if self.fileOffset >= 0 && !source.lineStarts.is_empty() => {
                        let offset = self.fileOffset as u32;
                        let line = source.lineStarts.partition_point(|&start| start <= offset);
                        format!("<anonymous closure at {file}:{line}>")
                    }
                    _ => "<anonymous closure>".into(),
                }
            }
        }
    }
}

fn ptr<T>(t: &T) -> usize {
    t as *const T as usize
}

/// `_VariablesInfoCollector`.
#[derive(Default)]
struct VariablesInfo {
    varIndex: HashMap<VarId, usize>,
    varDeclarations: Vec<VarId>,
    captured: HashSet<VarId>,
    modifiedSets: HashMap<usize, Vec<usize>>,
    numVariablesAtFunctionEntry: usize,
    activeStatements: Option<Vec<usize>>,
    numVariablesAtActiveStatements: Option<Vec<usize>>,
    isInsideLocalFunction: bool,
    isReceiverCaptured: bool,
    summaryFunction: Option<usize>,
    numVariablesAtSummaryFunctionEntry: usize,
}

impl VariablesInfo {
    fn numVariables(&self) -> usize {
        self.varDeclarations.len()
    }

    fn isCaptured(&self, v: VarId) -> bool {
        self.captured.contains(&v)
    }

    fn getModifiedVariables(&self, st: usize) -> Vec<usize> {
        self.modifiedSets.get(&st).cloned().unwrap_or_default()
    }

    fn useVariable(&mut self, v: VarId, isVarAssignment: bool) {
        let index = *self.varIndex.get(&v).expect("variable declared before use");
        if index < self.numVariablesAtFunctionEntry {
            self.captured.insert(v);
            return;
        }
        if isVarAssignment {
            if let Some(active) = &self.activeStatements {
                let nums = self.numVariablesAtActiveStatements.as_ref().unwrap();
                for i in (0..active.len()).rev() {
                    if index < nums[i] {
                        let set = self.modifiedSets.entry(active[i]).or_default();
                        if !set.contains(&index) {
                            set.push(index);
                        }
                    } else {
                        break;
                    }
                }
            }
        }
    }

    fn start(&mut self, st: usize) {
        let n = self.numVariables();
        self.activeStatements.get_or_insert_with(Vec::new).push(st);
        self.numVariablesAtActiveStatements.get_or_insert_with(Vec::new).push(n);
    }

    fn end(&mut self) {
        self.activeStatements.as_mut().unwrap().pop();
        self.numVariablesAtActiveStatements.as_mut().unwrap().pop();
    }

    fn useReceiver(&mut self) {
        if self.isInsideLocalFunction {
            self.isReceiverCaptured = true;
        }
    }

    fn visitFunction(&mut self, function: &FunctionNode, env: &Env, vars: &HashMap<VarId, &Variable>) {
        let savedActive = self.activeStatements.take();
        let savedNums = self.numVariablesAtActiveStatements.take();
        let savedEntry = self.numVariablesAtFunctionEntry;
        self.numVariablesAtFunctionEntry = self.numVariables();
        let savedInside = self.isInsideLocalFunction;
        self.isInsideLocalFunction = true;
        if Some(ptr(function)) == self.summaryFunction {
            self.numVariablesAtSummaryFunctionEntry = self.numVariablesAtFunctionEntry;
        }
        self.visitChildren(Node::FunctionNode(function), env, vars);
        self.activeStatements = savedActive;
        self.numVariablesAtActiveStatements = savedNums;
        self.numVariablesAtFunctionEntry = savedEntry;
        self.isInsideLocalFunction = savedInside;
    }

    fn visitChildren(&mut self, node: Node, env: &Env, vars: &HashMap<VarId, &Variable>) {
        for child in children(node) {
            self.visit(child, env, vars);
        }
    }

    fn visit(&mut self, node: Node, env: &Env, vars: &HashMap<VarId, &Variable>) {
        match node {
            Node::Statement(s) => match s {
                Statement::FunctionDeclaration { variable, function, .. } => {
                    self.visit(Node::Variable(variable), env, vars);
                    self.visitFunction(function, env, vars);
                }
                Statement::TryCatch { body, catches, .. } => {
                    self.start(ptr(s));
                    self.visit(Node::Statement(body), env, vars);
                    self.end();
                    for c in catches {
                        self.visit(Node::Catch(c), env, vars);
                    }
                }
                Statement::TryFinally { body, finalizer, .. } => {
                    self.start(ptr(s));
                    self.visit(Node::Statement(body), env, vars);
                    self.end();
                    self.visit(Node::Statement(finalizer), env, vars);
                }
                Statement::While { .. } | Statement::Do { .. } => {
                    self.start(ptr(s));
                    self.visitChildren(node, env, vars);
                    self.end();
                }
                Statement::For { variables, condition, updates, body, .. } => {
                    for v in variables {
                        self.visit(Node::Variable(&v.variable), env, vars);
                    }
                    self.start(ptr(s));
                    if let Some(c) = condition {
                        self.visit(Node::Expression(c), env, vars);
                    }
                    self.visit(Node::Statement(body), env, vars);
                    for u in updates {
                        self.visit(Node::Expression(u), env, vars);
                    }
                    self.end();
                }
                Statement::ForIn { variable, iterable, body, .. } => {
                    self.visit(Node::Expression(iterable), env, vars);
                    self.start(ptr(s));
                    self.visit(Node::Variable(variable), env, vars);
                    self.visit(Node::Statement(body), env, vars);
                    self.end();
                }
                Statement::Switch { expression, cases, .. } => {
                    self.visit(Node::Expression(expression), env, vars);
                    self.start(ptr(s));
                    for c in cases {
                        self.visit(Node::SwitchCase(c), env, vars);
                    }
                    self.end();
                }
                _ => self.visitChildren(node, env, vars),
            },
            Node::Expression(e) => match e {
                Expression::FunctionExpression { function, .. } => self.visitFunction(function, env, vars),
                Expression::VariableGet { variable, .. } => {
                    self.visitChildren(node, env, vars);
                    if vars.get(variable).map(|v| v.kind) != Some(Tag::LocalFunctionVariable) {
                        self.useVariable(*variable, false);
                    }
                }
                Expression::VariableSet { variable, .. } => {
                    self.visitChildren(node, env, vars);
                    self.useVariable(*variable, true);
                }
                Expression::SuperMethodInvocation { .. }
                | Expression::SuperPropertyGet { .. }
                | Expression::SuperPropertySet { .. }
                | Expression::ThisExpression { .. } => {
                    self.useReceiver();
                    self.visitChildren(node, env, vars);
                }
                _ => self.visitChildren(node, env, vars),
            },
            Node::Variable(v) => {
                if v.kind != Tag::LocalFunctionVariable {
                    let index = self.numVariables();
                    self.varDeclarations.push(v.id);
                    self.varIndex.insert(v.id, index);
                }
                self.visitChildren(node, env, vars);
            }
            Node::DartType(DartType::TypeParameter { parameter, .. }) => {
                if let Some(kernel::reference_index::TypeParameterDeclaration::Class(_)) =
                    env.index.typeParameterDeclaration(*parameter)
                {
                    self.useReceiver();
                }
                self.visitChildren(node, env, vars);
            }
            _ => self.visitChildren(node, env, vars),
        }
    }

    fn visitMember(&mut self, member: MemberNode, env: &Env, vars: &HashMap<VarId, &Variable>) {
        match member {
            MemberNode::Constructor(c) => {
                for p in &c.function.positionalParameters {
                    self.visit(Node::Variable(p), env, vars);
                }
                for p in &c.function.namedParameters {
                    self.visit(Node::Variable(p), env, vars);
                }
                for i in &c.initializers {
                    self.visit(Node::Initializer(i), env, vars);
                }
                if let Some(b) = &c.function.body {
                    self.visit(Node::Statement(b), env, vars);
                }
            }
            MemberNode::Procedure(p) => {
                for a in &p.annotations {
                    self.visit(Node::Expression(a), env, vars);
                }
                self.visit(Node::FunctionNode(&p.function), env, vars);
            }
            MemberNode::Field(f) => {
                for a in &f.annotations {
                    self.visit(Node::Expression(a), env, vars);
                }
                self.visit(Node::DartType(&f.r#type), env, vars);
                if let Some(i) = &f.initializer {
                    self.visit(Node::Expression(i), env, vars);
                }
            }
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
enum JumpKey {
    Label(LabelId),
    SwitchCase(SwitchCaseId),
}

#[derive(Debug, Clone)]
enum JumpHandler {
    /// `states.add` of a labeled statement: the slot in `jumpStates`.
    Labeled(usize),
    /// A switch case's joins.
    Switch(Vec<Option<StmtId>>),
    /// A jump out of a `try` with a `finally`: the slot in `takenJumps`.
    TryFinally(usize),
}

type State = Vec<Option<TypeExpr>>;

pub struct SummaryCollector<'a> {
    env: &'a Env<'a>,
    target: VmTarget<'a>,
    epl: &'a dyn EntryPointsListener,
    tb: &'a dyn TypesBuilder,
    gii: &'a GenericInterfacesInfoImpl<'a>,
    svb: &'a dyn SharedVariableBuilder,
    summary: Summary,
    vi: VariablesInfo,
    variableValues: State,
    aggregateVariable: Vec<bool>,
    capturedVariableReads: Option<HashMap<VarId, StmtId>>,
    variableVersions: Vec<usize>,
    jumpHandlers: Option<Vec<(JumpKey, JumpHandler)>>,
    jumpStates: Vec<Vec<State>>,
    takenJumps: Vec<Vec<JumpKey>>,
    returnValue: Option<StmtId>,
    enclosingMember: Option<CnId>,
    enclosingFileUri: UriId,
    receiver: Option<TypeExpr>,
    currentCondition: Option<TypeExpr>,
    ctx: Option<StaticTypeContext<'a>>,
    localFunctions: HashMap<VarId, LocalFunction<'a>>,
    functionTypeVariables: Option<Vec<(TypeParamId, TypeExpr)>>,
    typesCache: Vec<(DartType, TypeExpr)>,
    constants: Vec<(TFConstant, Type)>,
    nullMethodsAndGetters: Vec<Name>,
    nullSetters: Vec<Name>,
    cachedHasOverriddenEquals: HashMap<CnId, bool>,
}

impl<'a> SummaryCollector<'a> {
    pub fn new(
        env: &'a Env<'a>,
        epl: &'a dyn EntryPointsListener,
        tb: &'a dyn TypesBuilder,
        gii: &'a GenericInterfacesInfoImpl<'a>,
        svb: &'a dyn SharedVariableBuilder,
    ) -> Self {
        let nullClass = env.coreTypes.deprecatedNullClass;
        SummaryCollector {
            env,
            target: VmTarget::new(env.index),
            epl,
            tb,
            gii,
            svb,
            summary: Summary::new(0, 0, 0),
            vi: VariablesInfo::default(),
            variableValues: vec![],
            aggregateVariable: vec![],
            capturedVariableReads: None,
            variableVersions: vec![],
            jumpHandlers: None,
            jumpStates: vec![],
            takenJumps: vec![],
            returnValue: None,
            enclosingMember: None,
            enclosingFileUri: 0,
            receiver: None,
            currentCondition: None,
            ctx: None,
            localFunctions: HashMap::new(),
            functionTypeVariables: None,
            typesCache: vec![],
            constants: vec![],
            nullMethodsAndGetters: env.hierarchy.getInterfaceMemberNames(nullClass, false),
            nullSetters: env.hierarchy.getInterfaceMemberNames(nullClass, true),
            cachedHasOverriddenEquals: HashMap::new(),
        }
    }

    fn ctx(&self) -> &StaticTypeContext<'a> {
        self.ctx.as_ref().expect("static type context")
    }

    fn add(&mut self, kind: StatementKind) -> StmtId {
        let mut s = SStatement::new(kind);
        s.condition = self.currentCondition.clone();
        self.summary.addNew(s)
    }

    fn fromStaticType(&self, t: &DartType, canBeNull: bool) -> Type {
        fromStaticType(self.tb, self.env, t, canBeNull)
    }

    fn nullType() -> Type {
        nullableEmptyType()
    }

    fn boolType(&self) -> Type {
        boolType(self.tb, self.env)
    }

    fn coneOf(&self, c: CnId) -> Type {
        Type::Cone(self.tb.getTFClass(c))
    }

    fn nodeText(&self, node: Node) -> String {
        let mut p = AstPrinter::new(self.env.index, Some(&self.ctx().variables));
        match node {
            Node::Expression(e) => p.writeExpression(e, None),
            Node::Variable(v) => p.writeVariableNode(v),
            _ => unreachable!(),
        }
        p.getText()
    }

    fn localFunctionName(&self, f: &LocalFunction) -> String {
        f.name(self.env, self.enclosingFileUri)
    }

    /// `createSummary`.
    pub fn createSummary(&mut self, member: MemberNode<'a>, localFunction: Option<LocalFunction<'a>>) -> Summary {
        let env = self.env;
        let memberRef = member.reference();
        assert!(self.enclosingMember.is_none(), "Unable to create summary recursively");
        self.enclosingMember = Some(memberRef);
        self.enclosingFileUri = member.fileUri();
        self.ctx = Some(StaticTypeContext::new(member, env.typeEnvironment));
        self.localFunctions.clear();
        self.collectLocalFunctions(member);
        let mut vi = VariablesInfo { summaryFunction: localFunction.map(|f| f.key()), ..Default::default() };
        {
            let vars = &self.ctx.as_ref().unwrap().variables;
            vi.visitMember(member, env, vars);
        }
        self.vi = vi;
        let n = self.vi.numVariables();
        self.variableValues = vec![None; n];
        self.aggregateVariable = vec![false; n];
        self.capturedVariableReads = None;
        self.variableVersions = vec![0; n];
        self.jumpHandlers = None;
        self.jumpStates.clear();
        self.takenJumps.clear();
        self.returnValue = None;
        self.receiver = None;
        self.currentCondition = None;
        self.typesCache.clear();
        for i in 0..self.vi.numVariablesAtSummaryFunctionEntry {
            if self.vi.isCaptured(self.vi.varDeclarations[i]) {
                self.aggregateVariable[i] = true;
            }
        }
        let hasReceiver = hasReceiverArg(member, env);
        if let (MemberNode::Field(field), None) = (member, localFunction) {
            if hasReceiver {
                self.summary = Summary::new(1, 1, 0);
                let cls = env.index.enclosingClass(memberRef).unwrap();
                let receiver = self.declareParameter("this", Some(&env.coreTypes.nonNullableRawType(cls)), None, true);
                self.receiver = Some(TypeExpr::Stmt(receiver));
                if self.vi.isReceiverCaptured {
                    let name = self.svb.getSharedCapturedThis(memberRef, env);
                    self.summary.addNew(SStatement::new(StatementKind::WriteVariable {
                        variable: name,
                        arg: TypeExpr::Stmt(receiver),
                    }));
                }
            } else {
                self.summary = Summary::new(0, 0, 0);
            }
            self.functionTypeVariables = None;
            let result = self.visit(field.initializer.as_ref().unwrap());
            self.summary.result = result;
        } else {
            let function = match localFunction {
                Some(f) => f.function,
                None => member.function().unwrap(),
            };
            let numTypeParameters = if localFunction.is_none() { numTypeParams(member) } else { 0 };
            let firstParamIndex = (if hasReceiver || localFunction.is_some() { 1 } else { 0 }) + numTypeParameters;
            self.summary = Summary::new(
                firstParamIndex + function.positionalParameters.len() + function.namedParameters.len(),
                firstParamIndex + function.positionalParameters.len(),
                firstParamIndex + function.requiredParameterCount as usize,
            );
            let mut fnTypeVariables = None;
            if numTypeParameters > 0 {
                let mut vars = Vec::new();
                for tp in &function.typeParameters {
                    let p = self.declareParameter(&env.index.string(tp.name), None, None, false);
                    vars.push((tp.id, TypeExpr::Stmt(p)));
                }
                fnTypeVariables = Some(vars);
            }
            if localFunction.is_some() {
                self.declareParameter("#closure", Some(&DartType::Dynamic), None, false);
            } else if hasReceiver {
                let cls = env.index.enclosingClass(memberRef).unwrap();
                let r = self.declareParameter("this", Some(&env.coreTypes.nonNullableRawType(cls)), None, true);
                self.receiver = Some(TypeExpr::Stmt(r));
            }
            self.functionTypeVariables = fnTypeVariables;
            for decl in function.positionalParameters.iter().chain(function.namedParameters.iter()) {
                let ty = if useTypeCheckForParameter(decl) { None } else { Some(&decl.r#type) };
                self.declareParameter(&env.index.string(decl.name), ty, decl.initializer.as_deref(), false);
            }
            if hasReceiver && self.vi.isReceiverCaptured {
                let name = self.svb.getSharedCapturedThis(memberRef, env);
                if localFunction.is_some() {
                    let read = self.summary.addNew(SStatement::new(StatementKind::ReadVariable { variable: name }));
                    self.receiver = Some(TypeExpr::Stmt(read));
                } else {
                    let arg = self.receiver.clone().unwrap();
                    self.summary.addNew(SStatement::new(StatementKind::WriteVariable { variable: name, arg }));
                }
            }
            let mut count = firstParamIndex;
            for decl in function.positionalParameters.iter().chain(function.namedParameters.iter()) {
                let mut param = TypeExpr::Stmt(self.summary.statements[count]);
                count += 1;
                if useTypeCheckForParameter(decl) {
                    param = TypeExpr::Stmt(self.typeCheck(param, &decl.r#type, Node::Variable(decl)));
                }
                self.declareVariable(decl, param);
            }
            let rv = self.summary.addNew(SStatement::new(StatementKind::Join {
                name: Some("%result".into()),
                staticType: function.returnType.clone(),
                values: vec![],
            }));
            self.returnValue = Some(rv);
            if let (MemberNode::Constructor(c), None) = (member, localFunction) {
                let cls = env.index.class(env.index.enclosingClass(memberRef).unwrap()).unwrap();
                for f in &cls.fields {
                    if f.flags & kernel::class_hierarchy::FIELD_STATIC == 0 && f.flags & FIELD_LATE == 0 && f.initializer.is_some() {
                        self.epl.addRawCall(Selector::Direct {
                            member: MemberId::Node(f.fieldReference),
                            callKind: CallKind::FieldInitializer,
                        });
                    }
                }
                for i in &c.initializers {
                    self.visitInitializer(i);
                }
            }
            match &function.body {
                None => panic!("native procedures (NativeCodeOracle) are not ported yet"),
                Some(body) => {
                    self.visitStatement(body);
                    if nullability(&function.returnType, env.index) != Nullability::nonNullable
                        && !matches!(self.currentCondition, Some(TypeExpr::Type(Type::Empty)))
                    {
                        self.joinAdd(rv, TypeExpr::Type(Self::nullType()));
                    }
                }
            }
            self.currentCondition = None;
            if env.index.string(member.name().text) == "==" && localFunction.is_none() {
                let b = self.boolType();
                self.joinAdd(rv, TypeExpr::Type(b));
            }
            self.summary.result = match function.dartAsyncMarker {
                2 => TypeExpr::Type(concreteType(&self.addAllocatedClassTF(self.target.concreteAsyncResultClass().unwrap()))),
                3 => TypeExpr::Type(self.fromStaticType(&function.returnType, false)),
                1 => TypeExpr::Type(concreteType(&self.addAllocatedClassTF(self.target.concreteSyncStarResultClass().unwrap()))),
                _ => TypeExpr::Stmt(rv),
            };
        }
        match localFunction {
            None => {
                for a in member.annotations() {
                    self.visitAnnotation(a);
                }
                if let Some(c) = env.index.enclosingClass(memberRef) {
                    for a in &env.index.class(c).unwrap().annotations {
                        self.visitAnnotation(a);
                    }
                }
                for a in &env.index.enclosingLibrary(memberRef).unwrap().annotations {
                    self.visitAnnotation(a);
                }
            }
            Some(f) => {
                if let Some(v) = f.variable {
                    for a in &v.annotations {
                        self.visitAnnotation(a);
                    }
                }
            }
        }
        self.enclosingMember = None;
        let mut summary = std::mem::replace(&mut self.summary, Summary::new(0, 0, 0));
        normalize(&mut summary, self.tb, env);
        self.ctx = None;
        summary
    }

    fn collectLocalFunctions(&mut self, member: MemberNode<'a>) {
        fn walk<'a>(node: Node<'a>, out: &mut HashMap<VarId, LocalFunction<'a>>) {
            if let Node::Statement(Statement::FunctionDeclaration { variable, function, fileOffset, .. }) = node {
                out.insert(variable.id, LocalFunction { function, fileOffset: *fileOffset, variable: Some(variable) });
            }
            for c in children(node) {
                walk(c, out);
            }
        }
        let mut out = HashMap::new();
        match member {
            MemberNode::Field(f) => {
                if let Some(i) = &f.initializer {
                    walk(Node::Expression(i), &mut out);
                }
            }
            MemberNode::Procedure(p) => walk(Node::FunctionNode(&p.function), &mut out),
            MemberNode::Constructor(c) => {
                for i in &c.initializers {
                    walk(Node::Initializer(i), &mut out);
                }
                walk(Node::FunctionNode(&c.function), &mut out);
            }
        }
        self.localFunctions = out;
    }

    fn joinAdd(&mut self, join: StmtId, value: TypeExpr) {
        if let StatementKind::Join { values, .. } = &mut self.summary.stMut(join).kind {
            values.push(value);
        }
    }

    fn joinValues(&self, join: StmtId) -> &Vec<TypeExpr> {
        match &self.summary.st(join).kind {
            StatementKind::Join { values, .. } => values,
            _ => panic!("not a join"),
        }
    }

    fn isJoin(&self, e: &TypeExpr) -> Option<StmtId> {
        match e {
            TypeExpr::Stmt(s) if matches!(self.summary.st(*s).kind, StatementKind::Join { .. }) => Some(*s),
            _ => None,
        }
    }

    fn addAllocatedClassTF(&self, c: CnId) -> Rc<TFClass> {
        match self.epl.addAllocatedClass(c) {
            Type::Concrete(ct) => ct.cls.clone(),
            other => panic!("addAllocatedClass returned {other:?}"),
        }
    }

    fn visitAnnotation(&mut self, a: &'a Expression) {
        self.visit(a);
    }

    /// `_declareParameter`.
    fn declareParameter(&mut self, name: &str, ty: Option<&DartType>, defaultValue: Option<&'a Expression>, isReceiver: bool) -> StmtId {
        let staticType = ty.map(|t| self.fromStaticType(t, !isReceiver));
        let id = self.summary.addNew(SStatement::new(StatementKind::Parameter {
            name: name.into(),
            staticTypeForNarrowing: staticType,
            defaultValue: None,
        }));
        let index = self.summary.st(id).index as usize;
        if index >= self.summary.requiredParameterCount {
            let value = match defaultValue {
                Some(Expression::ConstantExpression { constant, .. }) => self.typeForConstant(*constant),
                Some(
                    e @ (Expression::StringLiteral { .. }
                    | Expression::IntLiteral { .. }
                    | Expression::DoubleLiteral { .. }
                    | Expression::BoolLiteral { .. }
                    | Expression::NullLiteral { .. }
                    | Expression::TypeLiteral { .. }),
                ) => self.visit(e).asType().unwrap().clone(),
                Some(other) => panic!("Unexpected parameter {name} default value {other:?}"),
                None => Self::nullType(),
            };
            if let StatementKind::Parameter { defaultValue, .. } = &mut self.summary.stMut(id).kind {
                *defaultValue = Some(value);
            }
        }
        id
    }

    fn varIndexOf(&self, v: VarId) -> usize {
        *self.vi.varIndex.get(&v).expect("variable index")
    }

    /// `_declareVariable`.
    fn declareVariable(&mut self, decl: &Variable, initialValue: TypeExpr) {
        let i = self.varIndexOf(decl.id);
        if self.vi.isCaptured(decl.id) {
            self.aggregateVariable[i] = true;
            if !initialValue.isEmpty() {
                self.writeVariable(decl.id, initialValue);
            }
        } else {
            self.variableValues[i] = Some(initialValue);
        }
    }

    fn sharedName(&self, v: VarId) -> String {
        let variable = self.ctx().variable(v);
        self.svb.getSharedVariable(variable, self.env)
    }

    /// `_writeVariable`.
    fn writeVariable(&mut self, v: VarId, value: TypeExpr) {
        if self.vi.isCaptured(v) {
            let name = self.sharedName(v);
            self.add(StatementKind::WriteVariable { variable: name, arg: value });
            return;
        }
        let i = self.varIndexOf(v);
        if self.aggregateVariable[i] {
            let join = self.variableValues[i].clone().and_then(|e| e.asStmt()).unwrap();
            self.addValueToJoin(join, value);
        } else {
            self.variableValues[i] = Some(value);
        }
    }

    fn readReceiver(&self) -> TypeExpr {
        self.receiver.clone().expect("receiver")
    }

    /// `_readVariable`.
    fn readVariable(&mut self, v: VarId) -> TypeExpr {
        if self.vi.isCaptured(v) {
            if let Some(cached) = self.capturedVariableReads.as_ref().and_then(|m| m.get(&v)).copied() {
                if self.currentCondition.is_none() {
                    return TypeExpr::Stmt(cached);
                }
                return TypeExpr::Stmt(self.makeUnary(UnaryOp::Move, TypeExpr::Stmt(cached)));
            }
            let name = self.sharedName(v);
            let read = self.add(StatementKind::ReadVariable { variable: name });
            if self.currentCondition.is_none() {
                self.capturedVariableReads.get_or_insert_with(HashMap::new).insert(v, read);
            }
            return TypeExpr::Stmt(read);
        }
        self.variableValues[self.varIndexOf(v)].clone().expect("Unable to find variable")
    }

    fn makeEmptyVariableValues(&self) -> State {
        (0..self.vi.numVariables())
            .map(|i| {
                if self.aggregateVariable[i] {
                    self.variableValues[i].clone()
                } else if self.variableValues[i].is_some() {
                    Some(TypeExpr::empty())
                } else {
                    None
                }
            })
            .collect()
    }

    /// `_makeJoin`.
    fn makeJoin(&mut self, varIndex: usize, value: TypeExpr) -> StmtId {
        let vid = self.vi.varDeclarations[varIndex];
        let variable = self.ctx().variable(vid);
        let cosmetic = self.env.index.string(variable.name);
        let cosmetic = if cosmetic.is_empty() { "null".to_string() } else { cosmetic };
        let name = format!("{cosmetic}_{}", self.variableVersions[varIndex]);
        self.variableVersions[varIndex] += 1;
        let staticType = variable.r#type.clone();
        self.add(StatementKind::Join { name: Some(name), staticType, values: vec![value] })
    }

    /// `_addValueToJoin`.
    fn addValueToJoin(&mut self, dst: StmtId, mut src: TypeExpr) {
        if self.joinValues(dst).contains(&src) {
            return;
        }
        if let Some(cc) = self.currentCondition.clone() {
            let dstCond = self.summary.st(dst).condition.clone();
            let srcCondEq = match &src {
                TypeExpr::Stmt(s) => self.summary.st(*s).condition.as_ref() == Some(&cc),
                _ => false,
            };
            if Some(&cc) != dstCond.as_ref() && !srcCondEq {
                src = TypeExpr::Stmt(self.makeUnary(UnaryOp::Move, src));
            }
        }
        self.joinAdd(dst, src);
    }

    fn sameExpr(a: &Option<TypeExpr>, b: &Option<TypeExpr>) -> bool {
        // `identical`: types are values here, so equal types are identical.
        a == b
    }

    /// `_mergeVariableValues`.
    fn mergeVariableValues(&mut self, dst: &mut State, src: &State) {
        for i in 0..dst.len() {
            let dstValue = dst[i].clone();
            let srcValue = src[i].clone();
            if Self::sameExpr(&dstValue, &srcValue) {
                continue;
            }
            let (Some(d), Some(s)) = (dstValue, srcValue) else {
                dst[i] = None;
                continue;
            };
            if d.isEmpty() {
                dst[i] = Some(s);
            } else if let Some(j) = self.isJoin(&d).filter(|&j| {
                self.joinValues(j).contains(&s) && {
                    let c = &self.summary.st(j).condition;
                    c.is_none() || *c == self.currentCondition
                }
            }) {
                let _ = j;
                continue;
            } else if s.isEmpty() {
                continue;
            } else if let Some(_j) = self.isJoin(&s).filter(|&j| {
                self.joinValues(j).contains(&d) && {
                    let c = &self.summary.st(j).condition;
                    c.is_none() || *c == self.currentCondition
                }
            }) {
                dst[i] = Some(s);
            } else {
                let join = self.makeJoin(i, d);
                self.joinAdd(join, s);
                dst[i] = Some(TypeExpr::Stmt(join));
            }
        }
    }

    fn mergeIntoCurrent(&mut self, src: &State) {
        let mut dst = std::mem::take(&mut self.variableValues);
        self.mergeVariableValues(&mut dst, src);
        self.variableValues = dst;
    }

    /// `_insertJoinsForModifiedVariables`.
    fn insertJoinsForModifiedVariables(&mut self, node: usize, isTry: bool) -> Vec<Option<StmtId>> {
        let mut joins = vec![None; self.vi.numVariables()];
        for i in self.vi.getModifiedVariables(node) {
            if !self.aggregateVariable[i] {
                let value = self.variableValues[i].clone().unwrap();
                let join = self.makeJoin(i, value);
                joins[i] = Some(join);
                self.variableValues[i] = Some(TypeExpr::Stmt(join));
                if isTry {
                    self.aggregateVariable[i] = true;
                }
            }
        }
        joins
    }

    fn restoreModifiedVariablesAfterTry(&mut self, joins: &[Option<StmtId>]) {
        for (i, j) in joins.iter().enumerate() {
            if j.is_some() {
                self.aggregateVariable[i] = false;
            }
        }
    }

    /// `_mergeVariableValuesAndConditions`.
    fn mergeVariableValuesAndConditions(
        &mut self,
        commonCondition: Option<TypeExpr>,
        mut values1: State,
        condition1: Option<TypeExpr>,
        values2: State,
        condition2: Option<TypeExpr>,
    ) {
        if matches!(condition1, Some(TypeExpr::Type(Type::Empty))) {
            self.currentCondition = condition2;
            self.variableValues = values2;
        } else if matches!(condition2, Some(TypeExpr::Type(Type::Empty))) {
            self.currentCondition = condition1;
            self.variableValues = values1;
        } else {
            self.currentCondition = commonCondition;
            self.mergeVariableValues(&mut values1, &values2);
            self.variableValues = values1;
        }
    }

    /// `_mergeVariableValuesToJoins`.
    fn mergeVariableValuesToJoins(&mut self, values: &State, joins: &[Option<StmtId>]) {
        for (i, join) in joins.iter().enumerate() {
            if let Some(join) = join {
                let value = values[i].clone();
                let isSelf = value == Some(TypeExpr::Stmt(*join));
                let isFirst = self.joinValues(*join).first().cloned() == value;
                if !isSelf && !isFirst {
                    self.joinAdd(*join, value.unwrap());
                }
            }
        }
    }

    /// `_typeCheck`.
    fn typeCheck(&mut self, value: TypeExpr, ty: &DartType, node: Node<'a>) -> StmtId {
        let runtimeType = self.translate(ty);
        let staticType = self.fromStaticType(ty, true);
        let nodeText = self.nodeText(node);
        self.add(StatementKind::TypeCheck { arg: value, type_: runtimeType, nodeText, staticType })
    }

    fn declareVariableWithStaticType(&mut self, decl: &'a Variable) {
        if let Some(init) = &decl.initializer {
            self.visit(init);
        }
        let t = self.fromStaticType(&decl.r#type, true);
        self.declareVariable(decl, TypeExpr::Type(t));
    }

    fn procedureReturnType(&self, target: &MemberId) -> Option<&'a DartType> {
        match target {
            MemberId::Node(r) => match self.env.index.member(*r)? {
                MemberNode::Procedure(p) => Some(&p.function.returnType),
                _ => None,
            },
            _ => None,
        }
    }

    /// `_makeCall`.
    fn makeCall(&mut self, node: Option<&'a Expression>, selector: Selector, args: Args, isInstanceCreation: bool) -> TypeExpr {
        let target = match &selector {
            Selector::Direct { member, .. } | Selector::Interface { member, .. } | Selector::Virtual { member, .. } => Some(member.clone()),
            _ => None,
        };
        let mut staticResultType = None;
        if let Some(e) = node {
            let staticDartType = self.ctx().getStaticType(e);
            if matches!(staticDartType, DartType::Never { nullability } if nullability == Nullability::nonNullable) {
                staticResultType = Some(Type::Empty);
            } else if let Some(returnType) = target.as_ref().and_then(|t| self.procedureReturnType(t)) {
                if matches!(returnType, DartType::TypeParameter { .. }) || *returnType != staticDartType {
                    staticResultType = Some(self.fromStaticType(&staticDartType, true));
                }
            }
        }
        let isEmpty = matches!(staticResultType, Some(Type::Empty));
        let call = self.add(StatementKind::Call { selector, args, staticResultType, isInstanceCreation, isResultUsed: false });
        if isEmpty {
            self.currentCondition = Some(TypeExpr::empty());
            self.variableValues = self.makeEmptyVariableValues();
            return TypeExpr::empty();
        }
        TypeExpr::Stmt(call)
    }

    fn isInstanceCreationCall(&self, s: StmtId) -> bool {
        matches!(self.summary.st(s).kind, StatementKind::Call { isInstanceCreation: true, .. })
    }

    /// `_makeNarrow`.
    fn makeNarrow(&mut self, arg: TypeExpr, ty: Type) -> TypeExpr {
        match &arg {
            TypeExpr::Stmt(s) => {
                if let Some((_, narrowType)) = self.summary.st(*s).asNarrow() {
                    if narrowType == ty {
                        return arg;
                    }
                    if ty == anyInstanceType && !narrowType.isNullable() {
                        return arg;
                    }
                } else if self.isInstanceCreationCall(*s) && ty == anyInstanceType {
                    return arg;
                } else if let StatementKind::TypeCheck { staticType, .. } = &self.summary.st(*s).kind {
                    if *staticType == ty {
                        return arg;
                    }
                }
            }
            TypeExpr::Type(t) => {
                if let Type::Nullable(b) = t {
                    if **b == anyInstanceType {
                        return TypeExpr::Type(ty);
                    }
                }
                if ty == anyInstanceType {
                    return TypeExpr::Type(match t {
                        Type::Nullable(b) => (**b).clone(),
                        _ => t.clone(),
                    });
                }
            }
        }
        if let Type::Nullable(b) = &ty {
            if **b == anyInstanceType {
                return arg;
            }
        }
        TypeExpr::Stmt(self.add(StatementKind::Narrow { arg, type_: ty }))
    }

    /// `_makeNarrowNotNull` (the null test side table is not kept).
    fn makeNarrowNotNull(&mut self, arg: TypeExpr) -> TypeExpr {
        match &arg {
            TypeExpr::Stmt(s) => match &self.summary.st(*s).kind {
                StatementKind::NarrowNotNull { .. } => return arg,
                StatementKind::Narrow { type_, .. } if !type_.isNullable() => return arg,
                _ => {}
            },
            TypeExpr::Type(t) => {
                return TypeExpr::Type(match t {
                    Type::Nullable(b) => (**b).clone(),
                    _ => t.clone(),
                });
            }
        }
        TypeExpr::Stmt(self.add(StatementKind::NarrowNotNull { arg }))
    }

    fn makeUnary(&mut self, op: UnaryOp, arg: TypeExpr) -> StmtId {
        self.add(StatementKind::Unary { op, arg })
    }

    fn makeBinary(&mut self, op: BinaryOp, arg1: TypeExpr, arg2: TypeExpr) -> StmtId {
        self.add(StatementKind::Binary { op, arg1, arg2 })
    }

    /// `_addUse`.
    fn addUse(&mut self, arg: &TypeExpr) {
        let TypeExpr::Stmt(s) = arg else { return };
        let kind = self.summary.st(*s).kind.clone();
        match kind {
            StatementKind::Narrow { arg, .. } | StatementKind::NarrowNotNull { arg } => self.addUse(&arg),
            StatementKind::Join { .. } | StatementKind::Call { .. } | StatementKind::TypeCheck { .. } | StatementKind::ReadVariable { .. } => {
                self.summary.addNew(SStatement::new(StatementKind::Use { arg: arg.clone() }));
            }
            StatementKind::Unary { arg, .. } => self.addUse(&arg),
            StatementKind::Binary { arg1, arg2, .. } => {
                self.addUse(&arg1);
                self.addUse(&arg2);
            }
            _ => {}
        }
    }

    fn staticType(&self, e: &Expression) -> Type {
        let t = self.ctx().getStaticType(e);
        self.fromStaticType(&t, true)
    }

    fn intLiteralType(&self, value: i64, constant: Option<TFConstant>) -> Type {
        match self.target.concreteIntLiteralClass(value) {
            Some(c) => {
                let cls = self.addAllocatedClassTF(c);
                constantConcreteType(&cls, constant.unwrap_or(TFConstant::Int(value)), None, self.env)
            }
            None => self.coneOf(self.env.coreTypes.intClass),
        }
    }

    fn doubleLiteralType(&self, value: f64, constant: Option<TFConstant>) -> Type {
        let cls = self.addAllocatedClassTF(self.target.concreteDoubleLiteralClass().unwrap());
        constantConcreteType(&cls, constant.unwrap_or(TFConstant::Double(value)), None, self.env)
    }

    fn stringLiteralType(&self, value: String, constant: Option<TFConstant>) -> Type {
        let cls = self.addAllocatedClassTF(self.target.concreteStringLiteralClass(&value).unwrap());
        constantConcreteType(&cls, constant.unwrap_or(TFConstant::String(value)), None, self.env)
    }

    fn boolLiteralType(&self, value: bool) -> Type {
        constantBool(self.tb, self.env, value)
    }

    /// `_localClosure`.
    fn localClosure(&mut self, f: LocalFunction<'a>) -> TypeExpr {
        let member = self.enclosingMember.unwrap();
        let name = self.localFunctionName(&f);
        let closure = Closure { member, function: Some((f.key(), name.clone())) };
        let callMethod = self.epl.getClosureCallMethod(&closure);
        self.epl.addRawCall(Selector::Direct { member: callMethod, callKind: CallKind::Method });
        let cls = self.addAllocatedClassTF(self.target.concreteClosureClass().unwrap());
        TypeExpr::Type(closureConcreteType(&cls, member, Some((f.key(), name))))
    }

    fn canNarrowVariable(&self, v: VarId) -> bool {
        self.ctx().variable(v).kind != Tag::LocalFunctionVariable && !self.aggregateVariable[self.varIndexOf(v)]
    }

    fn narrowVariable(&mut self, v: VarId, value: TypeExpr, state: Option<&mut State>) {
        if self.canNarrowVariable(v) {
            let i = self.varIndexOf(v);
            match state {
                Some(s) => s[i] = Some(value),
                None => self.variableValues[i] = Some(value),
            }
        }
    }

    fn isSubtype(&self, sub: &DartType, sup: &DartType) -> bool {
        self.env.typeEnvironment.isSubtypeOf(sub, sup)
    }

    /// `_hasOverriddenEquals`.
    fn hasOverriddenEquals(&mut self, ty: &DartType) -> bool {
        let DartType::Interface { classReference, .. } = ty else { return true };
        if let Some(r) = self.cachedHasOverriddenEquals.get(classReference) {
            return *r;
        }
        let objectEquals = self.env.coreTypes.objectEquals;
        let equalsName = self.env.index.member(objectEquals).unwrap().name();
        for c in self.env.hierarchy.getSubtypesOf(*classReference).iter() {
            let isAbstract = self.env.index.class(*c).unwrap().flags & 1 != 0;
            if !isAbstract {
                let candidate = self.env.hierarchy.getDispatchTarget(*c, equalsName, false);
                if candidate != Some(objectEquals) {
                    self.cachedHasOverriddenEquals.insert(*classReference, true);
                    return true;
                }
            }
        }
        self.cachedHasOverriddenEquals.insert(*classReference, false);
        false
    }

    /// `_visitCondition`.
    fn visitCondition(&mut self, node: &'a Expression, trueState: &mut State, falseState: &mut State) -> TypeExpr {
        match node {
            Expression::Not { operand, .. } => {
                let operand = self.visitCondition(operand, falseState, trueState);
                let result = self.makeUnary(UnaryOp::Not, operand);
                self.variableValues = vec![];
                return TypeExpr::Stmt(result);
            }
            Expression::LogicalExpression { left, operator, right, .. } => {
                let isOR = *operator == 1;
                let leftValue = self.visitCondition(left, trueState, falseState);
                let conditionAfterLHS = self.currentCondition.clone();
                let result;
                if isOR {
                    self.currentCondition = Some(TypeExpr::Stmt(self.makeUnary(UnaryOp::Not, leftValue.clone())));
                    self.variableValues = falseState.clone();
                    let mut trueStateAfterRHS = self.variableValues.clone();
                    let rightValue = self.visitCondition(right, &mut trueStateAfterRHS, falseState);
                    self.currentCondition = conditionAfterLHS;
                    self.mergeVariableValues(trueState, &trueStateAfterRHS);
                    result = self.makeBinary(BinaryOp::Or, leftValue, rightValue);
                } else {
                    self.currentCondition = Some(leftValue.clone());
                    self.variableValues = trueState.clone();
                    let mut falseStateAfterRHS = self.variableValues.clone();
                    let rightValue = self.visitCondition(right, trueState, &mut falseStateAfterRHS);
                    self.currentCondition = conditionAfterLHS;
                    self.mergeVariableValues(falseState, &falseStateAfterRHS);
                    result = self.makeBinary(BinaryOp::And, leftValue, rightValue);
                }
                self.variableValues = vec![];
                return TypeExpr::Stmt(result);
            }
            Expression::VariableGet { .. } | Expression::AsExpression { .. }
                if matches!(node, Expression::VariableGet { .. })
                    || matches!(node, Expression::AsExpression { operand, .. } if matches!(**operand, Expression::VariableGet { .. })) =>
            {
                let result = self.visit(node);
                self.addUse(&result);
                let v = match node {
                    Expression::VariableGet { variable, .. } => *variable,
                    Expression::AsExpression { operand, .. } => match &**operand {
                        Expression::VariableGet { variable, .. } => *variable,
                        _ => unreachable!(),
                    },
                    _ => unreachable!(),
                };
                if self.canNarrowVariable(v) {
                    let i = self.varIndexOf(v);
                    trueState[i] = Some(TypeExpr::Type(self.boolLiteralType(true)));
                    falseState[i] = Some(TypeExpr::Type(self.boolLiteralType(false)));
                }
                self.variableValues = vec![];
                return result;
            }
            Expression::EqualsCall { left, right, .. } if matches!(**left, Expression::VariableGet { .. }) => {
                let Expression::VariableGet { variable: lhsVar, .. } = &**left else { unreachable!() };
                let lhsType = self.ctx().variable(*lhsVar).r#type.clone();
                let core = self.env.coreTypes;
                let isInt = matches!(**right, Expression::IntLiteral { .. })
                    || matches!(&**right, Expression::ConstantExpression { constant, .. } if matches!(self.env.index.component.constants[*constant as usize], Constant::Int(_)));
                let isString = matches!(**right, Expression::StringLiteral { .. })
                    || matches!(&**right, Expression::ConstantExpression { constant, .. } if matches!(self.env.index.component.constants[*constant as usize], Constant::String(_)));
                let safe = |d: f64| !d.is_nan() && d != 0.0;
                let isDouble = match &**right {
                    Expression::DoubleLiteral { value, .. } => safe(*value),
                    Expression::ConstantExpression { constant, .. } => match self.env.index.component.constants[*constant as usize] {
                        Constant::Double(d) => safe(d),
                        _ => false,
                    },
                    _ => false,
                };
                let ok = (isInt && self.isSubtype(&lhsType, &core.nullableRawType(core.intClass)))
                    || (isDouble && self.isSubtype(&lhsType, &core.nullableRawType(core.doubleClass)))
                    || (isString && self.isSubtype(&lhsType, &core.nullableRawType(core.stringClass)))
                    || (matches!(**right, Expression::ConstantExpression { .. }) && !self.hasOverriddenEquals(&lhsType));
                if ok {
                    let result = self.visit(node);
                    self.addUse(&result);
                    if self.canNarrowVariable(*lhsVar) {
                        let i = self.varIndexOf(*lhsVar);
                        trueState[i] = Some(self.visit(right));
                    }
                    self.variableValues = vec![];
                    return result;
                }
            }
            Expression::EqualsNull { expression, .. } if matches!(**expression, Expression::VariableGet { .. }) => {
                let Expression::VariableGet { variable, .. } = &**expression else { unreachable!() };
                let expr = self.visit(expression);
                let objectEquals = self.env.coreTypes.objectEquals;
                self.makeCall(
                    Some(node),
                    Selector::Direct { member: MemberId::Node(objectEquals), callKind: CallKind::Method },
                    Args::new(vec![expr.clone(), TypeExpr::Type(Self::nullType())]),
                    false,
                );
                let narrowedNotNull = self.makeNarrowNotNull(expr.clone());
                let result = self.makeUnary(UnaryOp::IsNull, expr);
                if self.canNarrowVariable(*variable) {
                    let i = self.varIndexOf(*variable);
                    let mv = self.makeUnary(UnaryOp::Move, TypeExpr::Type(Self::nullType()));
                    self.summary.stMut(mv).condition = Some(TypeExpr::Stmt(result));
                    trueState[i] = Some(TypeExpr::Stmt(mv));
                    falseState[i] = Some(narrowedNotNull);
                }
                self.variableValues = vec![];
                return TypeExpr::Stmt(result);
            }
            Expression::IsExpression { operand, r#type, .. } if matches!(**operand, Expression::VariableGet { .. }) => {
                let Expression::VariableGet { variable, .. } = &**operand else { unreachable!() };
                let value = self.visit(operand);
                let typeCheck = self.typeCheck(value, r#type, Node::Expression(node));
                self.narrowVariable(*variable, TypeExpr::Stmt(typeCheck), Some(trueState));
                let isEmpty = self.makeUnary(UnaryOp::IsEmpty, TypeExpr::Stmt(typeCheck));
                let result = self.makeUnary(UnaryOp::Not, TypeExpr::Stmt(isEmpty));
                self.variableValues = vec![];
                return TypeExpr::Stmt(result);
            }
            _ => {}
        }
        let result = self.visit(node);
        self.addUse(&result);
        trueState.clone_from(&self.variableValues);
        falseState.clone_from(&self.variableValues);
        self.variableValues = vec![];
        result
    }

    /// `_updateReceiverAfterCall`.
    fn updateReceiverAfterCall(&mut self, receiverNode: &Expression, receiverValue: TypeExpr, selector: Name, isSetter: bool) {
        if let Expression::VariableGet { variable, .. } = receiverNode {
            let nullSelectors = if isSetter { &self.nullSetters } else { &self.nullMethodsAndGetters };
            if !nullSelectors.contains(&selector) && self.canNarrowVariable(*variable) {
                let i = self.varIndexOf(*variable);
                let narrowed = self.makeNarrow(receiverValue, anyInstanceType);
                self.variableValues[i] = Some(narrowed);
            }
        }
    }

    /// `_visitArguments`.
    fn visitArguments(&mut self, receiver: Option<TypeExpr>, arguments: &'a Arguments, passTypeArguments: bool) -> Args {
        let mut values = Vec::new();
        if passTypeArguments {
            for t in &arguments.types {
                values.push(self.translate(t));
            }
        }
        if let Some(r) = receiver {
            values.push(r);
        }
        for a in &arguments.positional {
            values.push(self.visit(a));
        }
        if arguments.named.is_empty() {
            return Args::new(values);
        }
        let mut named: Vec<(String, TypeExpr)> = Vec::new();
        for n in &arguments.named {
            let v = self.visit(&n.value);
            named.push((self.env.index.string(n.name), v));
        }
        let mut names: Vec<String> = named.iter().map(|(n, _)| n.clone()).collect();
        names.sort();
        for name in &names {
            values.push(named.iter().find(|(n, _)| n == name).unwrap().1.clone());
        }
        Args { values, names }
    }

    fn superclass(&self) -> CnId {
        let thisType = self.ctx().thisType.as_ref().unwrap();
        let DartType::Interface { classReference, .. } = thisType else { unreachable!() };
        self.env.index.class(*classReference).unwrap().supertype.as_ref().unwrap().className
    }

    fn memberOfTarget(&self, target: CnId) -> MemberId {
        // A reference to a field's getter or setter stands for the field.
        match self.env.index.member(target) {
            Some(m) => MemberId::Node(m.reference()),
            None => MemberId::Node(target),
        }
    }

    pub fn visit(&mut self, e: &'a Expression) -> TypeExpr {
        use Expression::*;
        let env = self.env;
        match e {
            AsExpression { operand, r#type, .. } => {
                let value = self.visit(operand);
                let result = self.typeCheck(value, r#type, Node::Expression(e));
                if let VariableGet { variable, .. } = &**operand {
                    self.narrowVariable(*variable, TypeExpr::Stmt(result), None);
                }
                TypeExpr::Stmt(result)
            }
            NullCheck { operand, .. } => {
                let value = self.visit(operand);
                let result = self.makeNarrowNotNull(value);
                if let VariableGet { variable, .. } = &**operand {
                    self.narrowVariable(*variable, result.clone(), None);
                }
                result
            }
            BoolLiteral { value, .. } => TypeExpr::Type(self.boolLiteralType(*value)),
            IntLiteral { value, .. } => TypeExpr::Type(self.intLiteralType(*value, None)),
            DoubleLiteral { value, .. } => TypeExpr::Type(self.doubleLiteralType(*value, None)),
            ConditionalExpression { condition, then, otherwise, .. } => {
                let mut trueState = self.variableValues.clone();
                let mut falseState = self.variableValues.clone();
                let staticType = self.ctx().getStaticType(e);
                let v = self.add(StatementKind::Join { name: None, staticType, values: vec![] });
                let conditionValue = self.visitCondition(condition, &mut trueState, &mut falseState);
                let conditionBeforeBranch = self.currentCondition.clone();
                self.currentCondition = Some(conditionValue.clone());
                self.variableValues = trueState;
                let t = self.visit(then);
                self.addValueToJoin(v, t);
                let conditionAfterThen = self.currentCondition.clone();
                let stateAfterThen = std::mem::take(&mut self.variableValues);
                self.currentCondition = conditionBeforeBranch.clone();
                self.currentCondition = Some(TypeExpr::Stmt(self.makeUnary(UnaryOp::Not, conditionValue)));
                self.variableValues = falseState;
                let o = self.visit(otherwise);
                self.addValueToJoin(v, o);
                let conditionAfterElse = self.currentCondition.clone();
                let stateAfterElse = std::mem::take(&mut self.variableValues);
                self.mergeVariableValuesAndConditions(conditionBeforeBranch, stateAfterThen, conditionAfterThen, stateAfterElse, conditionAfterElse);
                let st = self.staticType(e);
                self.makeNarrow(TypeExpr::Stmt(v), st)
            }
            ConstructorInvocation { targetReference, arguments, .. } => {
                let classNode = env.index.enclosingClass(*targetReference).unwrap();
                let klass = concreteType(&self.tb.getTFClass(classNode));
                let receiver = self.instantiateConcreteType(klass, &arguments.types);
                let args = self.visitArguments(Some(receiver), arguments, false);
                self.makeCall(Some(e), Selector::Direct { member: MemberId::Node(*targetReference), callKind: CallKind::Method }, args, true)
            }
            FunctionExpression { function, fileOffset, .. } => {
                self.localClosure(LocalFunction { function, fileOffset: *fileOffset, variable: None })
            }
            Instantiation { expression, .. } => {
                self.visit(expression);
                TypeExpr::Type(self.staticType(e))
            }
            Invalid { .. } => TypeExpr::empty(),
            IsExpression { operand, r#type, .. } => {
                let value = self.visit(operand);
                self.typeCheck(value, r#type, Node::Expression(e));
                TypeExpr::Type(self.boolType())
            }
            Let { variable, body, .. } => {
                let value = self.visit(variable.initializer.as_ref().expect("let variable value"));
                self.declareVariable(variable, value);
                self.visit(body)
            }
            BlockExpression { body, value, .. } => {
                for s in body {
                    self.visitStatement(s);
                }
                self.visit(value)
            }
            ListLiteral { expressions, typeArgument, .. } => {
                for x in expressions {
                    self.visit(x);
                }
                let cls = self.target.concreteListLiteralClass().unwrap();
                let ct = self.epl.addAllocatedClass(cls);
                self.instantiateConcreteType(ct, std::slice::from_ref(typeArgument))
            }
            LogicalExpression { .. } => {
                let mut trueState = self.variableValues.clone();
                let mut falseState = self.variableValues.clone();
                let result = self.visitCondition(e, &mut trueState, &mut falseState);
                self.variableValues = trueState;
                self.mergeIntoCurrent(&falseState);
                result
            }
            MapLiteral { entries, keyType, valueType, .. } => {
                for entry in entries {
                    self.visit(&entry.key);
                    self.visit(&entry.value);
                }
                let cls = self.target.concreteMapLiteralClass().unwrap();
                let ct = self.epl.addAllocatedClass(cls);
                self.instantiateConcreteType(ct, &[(**keyType).clone(), (**valueType).clone()])
            }
            SetLiteral { expressions, typeArgument, .. } => {
                for x in expressions {
                    self.visit(x);
                }
                let cls = self.target.concreteSetLiteralClass().unwrap();
                let ct = self.epl.addAllocatedClass(cls);
                self.instantiateConcreteType(ct, std::slice::from_ref(typeArgument))
            }
            RecordLiteral { positional, named, recordType, .. } => {
                let DartType::Record(rt) = &**recordType else { unreachable!() };
                let shape = RecordShape::new(rt, env);
                let receiver = self.epl.addAllocatedRecord(&shape);
                let mut fieldValues = vec![TypeExpr::empty(); shape.numFields()];
                for (i, p) in positional.iter().enumerate() {
                    let f = self.epl.getRecordPositionalField(&shape, i);
                    let value = self.visit(p);
                    fieldValues[i] = value.clone();
                    self.makeCall(
                        Some(e),
                        Selector::Direct { member: f, callKind: CallKind::SetFieldInConstructor },
                        Args::new(vec![TypeExpr::Type(receiver.clone()), value]),
                        false,
                    );
                }
                for (i, n) in named.iter().enumerate() {
                    let f = self.epl.getRecordNamedField(&shape, &env.index.string(n.name));
                    let value = self.visit(&n.value);
                    fieldValues[shape.numPositionalFields + i] = value.clone();
                    self.makeCall(
                        Some(e),
                        Selector::Direct { member: f, callKind: CallKind::SetFieldInConstructor },
                        Args::new(vec![TypeExpr::Type(receiver.clone()), value]),
                        false,
                    );
                }
                let cls = receiver.concrete().unwrap().cls.clone();
                TypeExpr::Stmt(self.add(StatementKind::CreateRecordType { cls, fieldTypes: fieldValues }))
            }
            RecordIndexGet { receiver, receiverType, index: i, .. } => {
                let r = self.visit(receiver);
                let DartType::Record(rt) = &**receiverType else { unreachable!() };
                let field = self.epl.getRecordPositionalField(&RecordShape::new(rt, env), *i as usize);
                self.makeCall(Some(e), Selector::Direct { member: field, callKind: CallKind::PropertyGet }, Args::new(vec![r]), false)
            }
            RecordNameGet { receiver, receiverType, name, .. } => {
                let r = self.visit(receiver);
                let DartType::Record(rt) = &**receiverType else { unreachable!() };
                let field = self.epl.getRecordNamedField(&RecordShape::new(rt, env), &env.index.string(*name));
                self.makeCall(Some(e), Selector::Direct { member: field, callKind: CallKind::PropertyGet }, Args::new(vec![r]), false)
            }
            InstanceInvocation { receiver, name, arguments, interfaceTarget, .. } => {
                let r = self.visit(receiver);
                let args = self.visitArguments(Some(r.clone()), arguments, false);
                if let ConstantExpression { constant, .. } = &**receiver {
                    if env.index.string(name.text) == "[]" {
                        if let Constant::List { typeArgument, entries } = &env.index.component.constants[*constant as usize] {
                            return self.handleIndexingIntoListConstant(typeArgument, entries);
                        }
                    }
                }
                let member = self.memberOfTarget(interfaceTarget.target);
                let selector = if matches!(**receiver, ThisExpression { .. }) {
                    Selector::Virtual { member, callKind: CallKind::Method }
                } else {
                    Selector::Interface { member, callKind: CallKind::Method }
                };
                let result = self.makeCall(Some(e), selector, args, false);
                self.updateReceiverAfterCall(receiver, r, *name, false);
                result
            }
            DynamicInvocation { receiver, name, arguments, .. } => {
                let r = self.visit(receiver);
                let args = self.visitArguments(Some(r.clone()), arguments, false);
                let result = self.makeCall(Some(e), Selector::Dynamic { callKind: CallKind::Method, name: *name }, args, false);
                self.updateReceiverAfterCall(receiver, r, *name, false);
                result
            }
            LocalFunctionInvocation { variable, arguments, .. } => {
                let f = *self.localFunctions.get(variable).expect("local function");
                let member = self.enclosingMember.unwrap();
                let closure = Closure { member, function: Some((f.key(), self.localFunctionName(&f))) };
                let callMethod = self.epl.getClosureCallMethod(&closure);
                let args = self.visitArguments(Some(TypeExpr::Type(anyInstanceType)), arguments, false);
                self.makeCall(Some(e), Selector::Direct { member: callMethod, callKind: CallKind::Method }, args, false)
            }
            FunctionInvocation { receiver, arguments, .. } => {
                let r = self.visit(receiver);
                let args = self.visitArguments(Some(r.clone()), arguments, false);
                let st = self.staticType(e);
                let result = self.makeCall(Some(e), Selector::Function { staticResultType: st }, args, false);
                let callName = self.callName();
                self.updateReceiverAfterCall(receiver, r, callName, false);
                result
            }
            EqualsCall { left, right, interfaceTarget, .. } => {
                let l = self.visit(left);
                self.addUse(&l);
                let r = self.visit(right);
                self.addUse(&r);
                let member = self.memberOfTarget(interfaceTarget.target);
                let selector = if matches!(**left, ThisExpression { .. }) {
                    Selector::Virtual { member, callKind: CallKind::Method }
                } else {
                    Selector::Interface { member, callKind: CallKind::Method }
                };
                let a = TypeExpr::Type(self.staticType(left));
                let b = TypeExpr::Type(self.staticType(right));
                self.makeCall(Some(e), selector, Args::new(vec![a, b]), false)
            }
            EqualsNull { expression, .. } => {
                let arg = self.visit(expression);
                self.makeNarrowNotNull(arg.clone());
                let objectEquals = env.coreTypes.objectEquals;
                let st = TypeExpr::Type(self.staticType(expression));
                self.makeCall(
                    Some(e),
                    Selector::Direct { member: MemberId::Node(objectEquals), callKind: CallKind::Method },
                    Args::new(vec![st, TypeExpr::Type(Self::nullType())]),
                    false,
                );
                TypeExpr::Stmt(self.makeUnary(UnaryOp::IsNull, arg))
            }
            InstanceGet { receiver, name, interfaceTarget, .. } | InstanceTearOff { receiver, name, interfaceTarget, .. } => {
                self.handlePropertyGet(e, receiver, Some(interfaceTarget.target), *name)
            }
            DynamicGet { receiver, name, .. } => self.handlePropertyGet(e, receiver, None, *name),
            InstanceSet { receiver, name, value, interfaceTarget, .. } => {
                let r = self.visit(receiver);
                let v = self.visit(value);
                let member = self.memberOfTarget(interfaceTarget.target);
                let selector = if matches!(**receiver, ThisExpression { .. }) {
                    Selector::Virtual { member, callKind: CallKind::PropertySet }
                } else {
                    Selector::Interface { member, callKind: CallKind::PropertySet }
                };
                self.makeCall(Some(e), selector, Args::new(vec![r.clone(), v.clone()]), false);
                self.updateReceiverAfterCall(receiver, r, *name, true);
                v
            }
            DynamicSet { receiver, name, value, .. } => {
                let r = self.visit(receiver);
                let v = self.visit(value);
                self.makeCall(Some(e), Selector::Dynamic { callKind: CallKind::PropertySet, name: *name }, Args::new(vec![r.clone(), v.clone()]), false);
                self.updateReceiverAfterCall(receiver, r, *name, true);
                v
            }
            SuperMethodInvocation { name, arguments, .. } => {
                let args = self.visitArguments(Some(self.readReceiver()), arguments, false);
                match env.hierarchy.getDispatchTarget(self.superclass(), *name, false) {
                    None => TypeExpr::empty(),
                    Some(target) => {
                        let m = MemberId::Node(target);
                        self.epl.recordMemberCalledViaThis(&m);
                        self.makeCall(Some(e), Selector::Direct { member: m, callKind: CallKind::Method }, args, false)
                    }
                }
            }
            SuperPropertyGet { name, .. } => {
                let args = Args::new(vec![self.readReceiver()]);
                match env.hierarchy.getDispatchTarget(self.superclass(), *name, false) {
                    None => TypeExpr::empty(),
                    Some(target) => {
                        self.makeCall(Some(e), Selector::Direct { member: MemberId::Node(target), callKind: CallKind::PropertyGet }, args, false)
                    }
                }
            }
            SuperPropertySet { name, value, .. } => {
                let v = self.visit(value);
                let args = Args::new(vec![self.readReceiver(), v.clone()]);
                if let Some(target) = env.hierarchy.getDispatchTarget(self.superclass(), *name, true) {
                    let m = MemberId::Node(target);
                    self.epl.recordMemberCalledViaThis(&m);
                    self.makeCall(Some(e), Selector::Direct { member: m, callKind: CallKind::PropertySet }, args, false);
                }
                v
            }
            Not { operand, .. } => {
                let o = self.visit(operand);
                self.addUse(&o);
                TypeExpr::Stmt(self.makeUnary(UnaryOp::Not, o))
            }
            NullLiteral { .. } => TypeExpr::Type(Self::nullType()),
            Rethrow { .. } => {
                self.currentCondition = Some(TypeExpr::empty());
                self.variableValues = self.makeEmptyVariableValues();
                TypeExpr::empty()
            }
            StaticGet { targetReference, .. } => {
                let m = self.memberOfTarget(*targetReference);
                self.makeCall(Some(e), Selector::Direct { member: m, callKind: CallKind::PropertyGet }, Args::new(vec![]), false)
            }
            StaticInvocation { targetReference, arguments, .. } => {
                let target = env.index.member(*targetReference).expect("static target");
                let MemberNode::Procedure(p) = target else { panic!("static invocation of a non-procedure") };
                if p.flags & PROCEDURE_WEAK_TEAROFF != 0 {
                    return TypeExpr::Type(self.staticType(e));
                }
                let args = self.visitArguments(None, arguments, p.kind == ProcedureKind::Factory);
                if *targetReference == env.coreTypes.identicalProcedure {
                    self.makeCall(
                        Some(e),
                        Selector::Direct { member: MemberId::Node(*targetReference), callKind: CallKind::Method },
                        Args::new(vec![TypeExpr::Type(nullableAnyType()), TypeExpr::Type(nullableAnyType())]),
                        false,
                    );
                    return TypeExpr::Type(self.boolType());
                }
                let mut result = self.makeCall(Some(e), Selector::Direct { member: MemberId::Node(*targetReference), callKind: CallKind::Method }, args.clone(), false);
                if Some(*targetReference) == getMember(env.index, "dart:_internal", None, "unsafeCast") {
                    let arg = args.values[0].clone();
                    let t = self.fromStaticType(&arguments.types[0], true);
                    result = self.makeNarrow(arg, t);
                }
                result
            }
            StaticSet { targetReference, value, .. } => {
                let v = self.visit(value);
                let m = self.memberOfTarget(*targetReference);
                self.makeCall(Some(e), Selector::Direct { member: m, callKind: CallKind::PropertySet }, Args::new(vec![v.clone()]), false);
                v
            }
            StringConcatenation { expressions, .. } => {
                for x in expressions {
                    self.visit(x);
                }
                TypeExpr::Type(self.coneOf(env.coreTypes.stringClass))
            }
            StringLiteral { value, .. } => TypeExpr::Type(self.stringLiteralType(env.index.string(*value), None)),
            SymbolLiteral { .. } => panic!("Expected SymbolLiteral to be lowered to SymbolConstant by CFE"),
            ThisExpression { .. } => self.readReceiver(),
            Throw { expression, .. } => {
                self.visit(expression);
                self.currentCondition = Some(TypeExpr::empty());
                self.variableValues = self.makeEmptyVariableValues();
                TypeExpr::empty()
            }
            TypeLiteral { .. } => TypeExpr::Type(self.coneOf(env.coreTypes.typeClass)),
            VariableGet { variable, promotedType, .. } => {
                let v = self.ctx().variable(*variable);
                let readType = if v.kind == Tag::LocalFunctionVariable {
                    let f = *self.localFunctions.get(variable).expect("local function");
                    self.localClosure(f)
                } else {
                    self.readVariable(*variable)
                };
                match promotedType {
                    Some(t) => {
                        let t = self.fromStaticType(t, true);
                        self.makeNarrow(readType, t)
                    }
                    None => readType,
                }
            }
            VariableSet { variable, value, .. } => {
                let v = self.visit(value);
                self.writeVariable(*variable, v.clone());
                v
            }
            LoadLibrary { .. } | CheckLibraryIsLoaded { .. } => TypeExpr::Type(self.staticType(e)),
            ConstantExpression { constant, .. } | FileUriConstantExpression { constant, .. } => TypeExpr::Type(self.typeForConstant(*constant)),
            AwaitExpression { operand, .. } => {
                self.visit(operand);
                TypeExpr::Type(self.staticType(e))
            }
            FileUriExpression { expression, .. } => self.visit(expression),
            other => panic!("Unexpected node {other:?}"),
        }
    }

    fn callName(&self) -> Name {
        // `Name.callName`: the public name `call`.
        let pool = &self.env.index.component.strings;
        let text = (0..pool.len() as u32).find(|&i| pool.get(i) == b"call").expect("the string 'call'");
        Name { text, library: None }
    }

    fn handleIndexingIntoListConstant(&mut self, typeArgument: &DartType, entries: &[ConstId]) -> TypeExpr {
        let mut elementTypes: Vec<Type> = Vec::new();
        for e in entries {
            let t = self.typeForConstant(*e);
            if !elementTypes.contains(&t) {
                elementTypes.push(t);
            }
        }
        match elementTypes.len() {
            0 => TypeExpr::empty(),
            1 => TypeExpr::Type(elementTypes.pop().unwrap()),
            _ => TypeExpr::Stmt(self.add(StatementKind::Join {
                name: None,
                staticType: typeArgument.clone(),
                values: elementTypes.into_iter().map(TypeExpr::Type).collect(),
            })),
        }
    }

    fn handlePropertyGet(&mut self, node: &'a Expression, receiverNode: &'a Expression, target: Option<CnId>, selector: Name) -> TypeExpr {
        let receiver = self.visit(receiverNode);
        let args = Args::new(vec![receiver.clone()]);
        let result = match target {
            None => self.makeCall(Some(node), Selector::Dynamic { callKind: CallKind::PropertyGet, name: selector }, args, false),
            Some(t) => {
                let member = self.memberOfTarget(t);
                let sel = if matches!(receiverNode, Expression::ThisExpression { .. }) {
                    Selector::Virtual { member, callKind: CallKind::PropertyGet }
                } else {
                    Selector::Interface { member, callKind: CallKind::PropertyGet }
                };
                self.makeCall(Some(node), sel, args, false)
            }
        };
        self.updateReceiverAfterCall(receiverNode, receiver, selector, false);
        result
    }

    fn visitInitializer(&mut self, i: &'a Initializer) {
        match i {
            Initializer::Field { fieldReference, value, .. } => {
                let v = self.visit(value);
                let args = Args::new(vec![self.readReceiver(), v]);
                let m = self.memberOfTarget(*fieldReference);
                self.makeCall(None, Selector::Direct { member: m, callKind: CallKind::SetFieldInConstructor }, args, false);
            }
            Initializer::Redirecting { targetReference, arguments, .. } => {
                let args = self.visitArguments(Some(self.readReceiver()), arguments, false);
                self.makeCall(None, Selector::Direct { member: MemberId::Node(*targetReference), callKind: CallKind::Method }, args, false);
            }
            Initializer::Super { targetReference, arguments, .. } => {
                let args = self.visitArguments(Some(self.readReceiver()), arguments, false);
                let targetName = self.env.index.member(*targetReference).unwrap().name();
                let superclass = self.env.index.class(self.superclass()).unwrap();
                let target = superclass.constructors.iter().find(|c| c.name == targetName).map(|c| c.reference).expect("super constructor");
                self.makeCall(None, Selector::Direct { member: MemberId::Node(target), callKind: CallKind::Method }, args, false);
            }
            Initializer::Local { variable, .. } => self.defaultVariable(variable),
            Initializer::Assert { statement, .. } => self.visitStatement(statement),
            Initializer::Invalid { .. } => {}
        }
    }

    /// `defaultVariable`.
    fn defaultVariable(&mut self, node: &'a Variable) {
        for a in &node.annotations {
            self.visitAnnotation(a);
        }
        let savedCondition = self.currentCondition.clone();
        let isLate = VariableFlags::of(node).isLate;
        let initialValue = match &node.initializer {
            None => {
                if nullability(&node.r#type, self.env.index) == Nullability::nonNullable || isLate {
                    TypeExpr::empty()
                } else {
                    TypeExpr::Type(Self::nullType())
                }
            }
            Some(init) => self.visit(init),
        };
        self.declareVariable(node, initialValue);
        if isLate {
            self.currentCondition = savedCondition;
        }
    }

    fn callJumpHandler(&mut self, key: JumpKey) {
        let handler = self
            .jumpHandlers
            .as_ref()
            .and_then(|h| h.iter().find(|(k, _)| *k == key))
            .map(|(_, h)| h.clone())
            .expect("jump handler");
        let state = self.variableValues.clone();
        match handler {
            JumpHandler::Labeled(slot) => self.jumpStates[slot].push(state),
            JumpHandler::Switch(joins) => self.mergeVariableValuesToJoins(&state, &joins),
            JumpHandler::TryFinally(slot) => {
                if !self.takenJumps[slot].contains(&key) {
                    self.takenJumps[slot].push(key);
                }
            }
        }
    }

    fn setJumpHandler(&mut self, key: JumpKey, handler: JumpHandler) {
        let handlers = self.jumpHandlers.get_or_insert_with(Vec::new);
        if let Some(entry) = handlers.iter_mut().find(|(k, _)| *k == key) {
            entry.1 = handler;
        } else {
            handlers.push((key, handler));
        }
    }

    fn removeJumpHandler(&mut self, key: JumpKey) {
        if let Some(h) = &mut self.jumpHandlers {
            h.retain(|(k, _)| *k != key);
        }
    }

    pub fn visitStatement(&mut self, s: &'a Statement) {
        match s {
            Statement::Assert { condition, message, .. } => {
                let mut trueState = self.variableValues.clone();
                let mut falseState = self.variableValues.clone();
                self.visitCondition(condition, &mut trueState, &mut falseState);
                if let Some(m) = message {
                    let saved = self.currentCondition.clone();
                    self.variableValues = falseState;
                    self.visit(m);
                    self.currentCondition = saved;
                }
                self.variableValues = trueState;
            }
            Statement::Block { statements, .. } | Statement::AssertBlock { statements } => {
                for x in statements {
                    self.visitStatement(x);
                }
            }
            Statement::Break { target, .. } => {
                self.callJumpHandler(JumpKey::Label(*target));
                self.currentCondition = Some(TypeExpr::empty());
                self.variableValues = self.makeEmptyVariableValues();
            }
            Statement::ContinueSwitch { target, .. } => {
                self.callJumpHandler(JumpKey::SwitchCase(*target));
                self.currentCondition = Some(TypeExpr::empty());
                self.variableValues = self.makeEmptyVariableValues();
            }
            Statement::Do { body, condition, .. } => {
                let joins = self.insertJoinsForModifiedVariables(ptr(s), false);
                self.visitStatement(body);
                let mut trueState = self.variableValues.clone();
                let mut falseState = self.variableValues.clone();
                self.visitCondition(condition, &mut trueState, &mut falseState);
                self.mergeVariableValuesToJoins(&trueState, &joins);
                self.variableValues = falseState;
            }
            Statement::Empty => {}
            Statement::Expression(e) => {
                self.visit(e);
            }
            Statement::ForIn { variable, iterable, body, .. } => {
                self.visit(iterable);
                self.declareVariableWithStaticType(variable);
                let joins = self.insertJoinsForModifiedVariables(ptr(s), false);
                let conditionAfterLoop = self.currentCondition.clone();
                let stateAfterLoop = self.variableValues.clone();
                self.visitStatement(body);
                let values = self.variableValues.clone();
                self.mergeVariableValuesToJoins(&values, &joins);
                self.currentCondition = conditionAfterLoop;
                self.variableValues = stateAfterLoop;
            }
            Statement::For { variables, condition, updates, body, .. } => {
                for v in variables {
                    self.defaultVariable(&v.variable);
                }
                let joins = self.insertJoinsForModifiedVariables(ptr(s), false);
                let mut trueState = self.variableValues.clone();
                let mut falseState = self.variableValues.clone();
                if let Some(c) = condition {
                    self.visitCondition(c, &mut trueState, &mut falseState);
                }
                let conditionAfterLoop = self.currentCondition.clone();
                self.variableValues = trueState;
                self.visitStatement(body);
                for u in updates {
                    self.visit(u);
                }
                let values = self.variableValues.clone();
                self.mergeVariableValuesToJoins(&values, &joins);
                self.variableValues = falseState;
                self.currentCondition = conditionAfterLoop;
            }
            Statement::FunctionDeclaration { .. } => {}
            Statement::If { condition, then, otherwise, .. } => {
                let mut trueState = self.variableValues.clone();
                let mut falseState = self.variableValues.clone();
                let conditionValue = self.visitCondition(condition, &mut trueState, &mut falseState);
                let conditionBeforeBranch = self.currentCondition.clone();
                self.currentCondition = Some(conditionValue.clone());
                self.variableValues = trueState;
                self.visitStatement(then);
                let conditionAfterThen = self.currentCondition.clone();
                let stateAfterThen = std::mem::take(&mut self.variableValues);
                self.currentCondition = conditionBeforeBranch.clone();
                self.currentCondition = Some(TypeExpr::Stmt(self.makeUnary(UnaryOp::Not, conditionValue)));
                self.variableValues = falseState;
                if let Some(o) = otherwise {
                    self.visitStatement(o);
                }
                let conditionAfterElse = self.currentCondition.clone();
                let stateAfterElse = std::mem::take(&mut self.variableValues);
                self.mergeVariableValuesAndConditions(conditionBeforeBranch, stateAfterThen, conditionAfterThen, stateAfterElse, conditionAfterElse);
            }
            Statement::Labeled { id, body, .. } => {
                let conditionOnEntry = self.currentCondition.clone();
                let slot = self.jumpStates.len();
                self.jumpStates.push(Vec::new());
                self.setJumpHandler(JumpKey::Label(*id), JumpHandler::Labeled(slot));
                self.visitStatement(body);
                self.removeJumpHandler(JumpKey::Label(*id));
                let states = std::mem::take(&mut self.jumpStates[slot]);
                if !states.is_empty() {
                    self.currentCondition = conditionOnEntry;
                    for state in &states {
                        self.mergeIntoCurrent(state);
                    }
                }
            }
            Statement::Return { expression, .. } => {
                let ret = match expression {
                    Some(x) => self.visit(x),
                    None => TypeExpr::Type(Self::nullType()),
                };
                if let Some(rv) = self.returnValue {
                    self.addValueToJoin(rv, ret);
                }
                self.currentCondition = Some(TypeExpr::empty());
                self.variableValues = self.makeEmptyVariableValues();
            }
            Statement::Switch { expression, cases, .. } => {
                self.visit(expression);
                let conditionOnEntry = self.currentCondition.clone();
                let stateOnEntry = self.variableValues.clone();
                let mut atEntry: Vec<State> = Vec::new();
                for c in cases {
                    self.variableValues = stateOnEntry.clone();
                    let joins = self.insertJoinsForModifiedVariables(ptr(s), false);
                    atEntry.push(self.variableValues.clone());
                    self.setJumpHandler(JumpKey::SwitchCase(c.id), JumpHandler::Switch(joins));
                }
                let mut hasDefault = false;
                for (c, state) in cases.iter().zip(atEntry) {
                    self.currentCondition = conditionOnEntry.clone();
                    self.variableValues = state;
                    for x in &c.expressions {
                        self.visit(x);
                    }
                    self.visitStatement(&c.body);
                    hasDefault = hasDefault || c.isDefault;
                }
                for c in cases {
                    self.removeJumpHandler(JumpKey::SwitchCase(c.id));
                }
                if !hasDefault {
                    self.currentCondition = conditionOnEntry;
                    self.mergeIntoCurrent(&stateOnEntry);
                }
            }
            Statement::TryCatch { body, catches, .. } => {
                let joins = self.insertJoinsForModifiedVariables(ptr(s), true);
                let stateDuringTry = self.variableValues.clone();
                let conditionOnEntry = self.currentCondition.clone();
                self.visitStatement(body);
                self.restoreModifiedVariablesAfterTry(&joins);
                for c in catches {
                    let conditionAfterTry = self.currentCondition.clone();
                    let stateAfterTry = std::mem::take(&mut self.variableValues);
                    self.currentCondition = conditionOnEntry.clone();
                    self.variableValues = stateDuringTry.clone();
                    if let Some(v) = &c.exception {
                        self.declareVariableWithStaticType(v);
                    }
                    if let Some(v) = &c.stackTrace {
                        self.declareVariableWithStaticType(v);
                    }
                    self.visitStatement(&c.body);
                    let values = std::mem::take(&mut self.variableValues);
                    let cond = self.currentCondition.clone();
                    self.mergeVariableValuesAndConditions(conditionOnEntry.clone(), stateAfterTry, conditionAfterTry, values, cond);
                }
            }
            Statement::TryFinally { body, finalizer, .. } => {
                let slot = self.takenJumps.len();
                self.takenJumps.push(Vec::new());
                let outer = self.jumpHandlers.clone();
                if let Some(outerHandlers) = &outer {
                    self.jumpHandlers = Some(outerHandlers.iter().map(|(k, _)| (*k, JumpHandler::TryFinally(slot))).collect());
                }
                let joins = self.insertJoinsForModifiedVariables(ptr(s), true);
                let stateDuringTry = self.variableValues.clone();
                let conditionOnEntry = self.currentCondition.clone();
                self.visitStatement(body);
                self.restoreModifiedVariablesAfterTry(&joins);
                let conditionAfterTry = self.currentCondition.clone();
                self.jumpHandlers = outer.clone();
                self.currentCondition = conditionOnEntry;
                self.variableValues = stateDuringTry;
                self.visitStatement(finalizer);
                if outer.is_some() && !matches!(self.currentCondition, Some(TypeExpr::Type(Type::Empty))) {
                    let taken = self.takenJumps[slot].clone();
                    for key in taken {
                        self.callJumpHandler(key);
                    }
                }
                if matches!(conditionAfterTry, Some(TypeExpr::Type(Type::Empty))) {
                    self.currentCondition = Some(TypeExpr::empty());
                    self.variableValues = self.makeEmptyVariableValues();
                }
            }
            Statement::VariableStatement { declaration, .. } => self.defaultVariable(&declaration.variable),
            Statement::While { condition, body, .. } => {
                let joins = self.insertJoinsForModifiedVariables(ptr(s), false);
                let mut trueState = self.variableValues.clone();
                let mut falseState = self.variableValues.clone();
                self.visitCondition(condition, &mut trueState, &mut falseState);
                let conditionOnEntry = self.currentCondition.clone();
                self.variableValues = trueState;
                self.visitStatement(body);
                let values = self.variableValues.clone();
                self.mergeVariableValuesToJoins(&values, &joins);
                self.variableValues = falseState;
                self.currentCondition = conditionOnEntry;
            }
            Statement::Yield { expression, .. } => {
                self.visit(expression);
            }
            other => panic!("Unexpected node {other:?}"),
        }
    }

    // RuntimeTypeTranslatorImpl.

    /// `instantiateConcreteType`.
    fn instantiateConcreteType(&mut self, ty: Type, typeArgs: &[DartType]) -> TypeExpr {
        if typeArgs.is_empty() {
            return TypeExpr::Type(ty);
        }
        let cls = ty.concrete().unwrap().cls.clone();
        let klass = self.env.index.class(cls.classNode).unwrap();
        let substitution = Substitution::fromPairs(&klass.typeParameters, typeArgs);
        let flattened = self.gii.flattenedTypeArgumentsFor(cls.classNode);
        let mut exprs = Vec::new();
        let mut createConcreteType = true;
        let mut allUnknown = true;
        for t in &flattened {
            let te = self.translate(&substitution.substituteType(t, self.env.index));
            if !matches!(te, TypeExpr::Type(Type::Unknown)) {
                allUnknown = false;
            }
            if matches!(te, TypeExpr::Stmt(_)) {
                createConcreteType = false;
            }
            exprs.push(te);
        }
        if allUnknown {
            return TypeExpr::Type(ty);
        }
        if createConcreteType {
            let types = exprs.into_iter().map(|e| e.asType().unwrap().clone()).collect();
            TypeExpr::Type(classConcreteType(&cls, types, None, self.env))
        } else {
            TypeExpr::Stmt(self.summary.addNew(SStatement::new(StatementKind::CreateConcreteType { cls, flattenedTypeArgs: exprs })))
        }
    }

    /// `translate`.
    pub fn translate(&mut self, ty: &DartType) -> TypeExpr {
        if let Some((_, cached)) = self.typesCache.iter().find(|(t, _)| t == ty) {
            return cached.clone();
        }
        self.typesCache.push((ty.clone(), TypeExpr::Type(unknownType)));
        let result = self.translateUncached(ty);
        if let Some(entry) = self.typesCache.iter_mut().find(|(t, _)| t == ty) {
            entry.1 = result.clone();
        }
        result
    }

    fn translateUncached(&mut self, ty: &DartType) -> TypeExpr {
        let env = self.env;
        match ty {
            DartType::Dynamic | DartType::Void | DartType::Never { .. } | DartType::Null => {
                TypeExpr::Type(Type::Runtime(Rc::new(RuntimeType::new(ty.clone(), None, env))))
            }
            DartType::Typedef { .. } => panic!("TypedefType: unalias is not ported"),
            DartType::Interface { nullability: n, classReference, typeArguments } => {
                if typeArguments.is_empty() {
                    return TypeExpr::Type(Type::Runtime(Rc::new(RuntimeType::new(ty.clone(), None, env))));
                }
                let klass = env.index.class(*classReference).unwrap();
                let substitution = Substitution::fromPairs(&klass.typeParameters, typeArguments);
                let flattened = self.gii.flattenedTypeArgumentsFor(*classReference);
                let mut exprs = Vec::new();
                let mut createRuntimeType = true;
                for t in &flattened {
                    let te = self.translate(&substitution.substituteType(t, env.index));
                    if matches!(te, TypeExpr::Type(Type::Unknown)) {
                        return TypeExpr::Type(unknownType);
                    }
                    if !matches!(te, TypeExpr::Type(Type::Runtime(_))) {
                        createRuntimeType = false;
                    }
                    exprs.push(te);
                }
                let nullability = kernel::type_algebra::nullability(ty, env.index);
                if createRuntimeType {
                    let raw = DartType::Interface {
                        nullability,
                        classReference: *classReference,
                        typeArguments: vec![DartType::Dynamic; klass.typeParameters.len()],
                    };
                    let _ = n;
                    let args = exprs.into_iter().map(|e| e.asType().unwrap().clone()).collect();
                    TypeExpr::Type(Type::Runtime(Rc::new(RuntimeType::new(raw, Some(args), env))))
                } else {
                    TypeExpr::Stmt(self.summary.addNew(SStatement::new(StatementKind::CreateRuntimeType {
                        klass: *classReference,
                        nullability,
                        flattenedTypeArgs: exprs,
                    })))
                }
            }
            DartType::FutureOr { typeArgument, .. } => {
                let arg = self.translate(typeArgument);
                if matches!(arg, TypeExpr::Type(Type::Unknown)) {
                    return TypeExpr::Type(unknownType);
                }
                let nullability = kernel::type_algebra::nullability(ty, env.index);
                if let TypeExpr::Type(t @ Type::Runtime(_)) = &arg {
                    let raw = DartType::FutureOr { declaredNullability: nullability, typeArgument: Box::new(DartType::Dynamic) };
                    TypeExpr::Type(Type::Runtime(Rc::new(RuntimeType::new(raw, Some(vec![t.clone()]), env))))
                } else {
                    TypeExpr::Stmt(self.summary.addNew(SStatement::new(StatementKind::CreateRuntimeType {
                        klass: env.coreTypes.deprecatedFutureOrClass,
                        nullability,
                        flattenedTypeArgs: vec![arg],
                    })))
                }
            }
            DartType::TypeParameter { parameter, declaredNullability } => {
                if let Some(vars) = &self.functionTypeVariables {
                    if let Some((_, result)) = vars.iter().find(|(p, _)| p == parameter) {
                        let result = result.clone();
                        let n = *declaredNullability;
                        if n != Nullability::nonNullable && n != Nullability::undetermined {
                            return TypeExpr::Stmt(
                                self.summary.addNew(SStatement::new(StatementKind::ApplyNullability { arg: result, nullability: n })),
                            );
                        }
                        return result;
                    }
                }
                let Some(kernel::reference_index::TypeParameterDeclaration::Class(interfaceClass)) =
                    env.index.typeParameterDeclaration(*parameter)
                else {
                    return TypeExpr::Type(unknownType);
                };
                let mut n = *declaredNullability;
                if n == Nullability::undetermined {
                    n = Nullability::nonNullable;
                }
                let arg = self.readReceiver();
                TypeExpr::Stmt(self.summary.addNew(SStatement::new(StatementKind::Extract {
                    arg,
                    referenceClass: interfaceClass,
                    paramIndex: env.index.typeParameterIndex(*parameter).unwrap(),
                    nullability: n,
                })))
            }
            DartType::Function(_) | DartType::Record(_) | DartType::Intersection { .. } => TypeExpr::Type(unknownType),
            DartType::Extension { extensionTypeErasure, .. } => self.translate(extensionTypeErasure),
            DartType::Invalid => panic!("InvalidType is not supported"),
        }
    }

    // ConstantAllocationCollector.

    /// `typeFor`.
    fn typeForConstant(&mut self, id: ConstId) -> Type {
        let key = TFConstant::fromTable(id, self.env);
        if let Some((_, t)) = self.constants.iter().find(|(c, _)| *c == key) {
            return t.clone();
        }
        let t = self.visitConstant(id, key.clone());
        self.constants.push((key, t.clone()));
        t
    }

    fn constantStaticType(&self, id: ConstId) -> Type {
        let t = constantType(&self.env.index.component.constants[id as usize], self.ctx());
        self.fromStaticType(&t, false)
    }

    fn getConstantConcreteType(&mut self, concreteClass: CnId, constant: TFConstant, typeArgs: &[DartType]) -> Type {
        let ct = self.epl.addAllocatedClass(concreteClass);
        let instantiated = self.instantiateConcreteType(ct, typeArgs);
        let TypeExpr::Type(Type::Concrete(c)) = instantiated else { panic!("constant type is not a ClassConcreteType") };
        let typeArgs = match &c.kind {
            ConcreteKind::Class { typeArgs, .. } => typeArgs.clone(),
            _ => None,
        };
        constantConcreteType(&c.cls, constant, typeArgs, self.env)
    }

    fn visitConstant(&mut self, id: ConstId, key: TFConstant) -> Type {
        let env = self.env;
        let constant = &env.index.component.constants[id as usize];
        match constant {
            Constant::Null => Self::nullType(),
            Constant::Bool(b) => self.boolLiteralType(*b),
            Constant::Int(i) => self.intLiteralType(*i, Some(key)),
            Constant::Double(d) => self.doubleLiteralType(*d, Some(key)),
            Constant::String(s) => self.stringLiteralType(env.index.string(*s), Some(key)),
            Constant::Symbol { .. } => {
                let c = self.target.concreteConstSymbolLiteralClass().unwrap();
                self.getConstantConcreteType(c, key, &[])
            }
            Constant::List { typeArgument, entries } => {
                for e in entries {
                    self.typeForConstant(*e);
                }
                let c = self.target.concreteConstListLiteralClass().unwrap();
                self.getConstantConcreteType(c, key, std::slice::from_ref(typeArgument))
            }
            Constant::Map { keyType, valueType, entries } => {
                for (k, v) in entries {
                    self.typeForConstant(*k);
                    self.typeForConstant(*v);
                }
                let c = self.target.concreteConstMapLiteralClass().unwrap();
                self.getConstantConcreteType(c, key, &[keyType.clone(), valueType.clone()])
            }
            Constant::Set { typeArgument, entries } => {
                for e in entries {
                    self.typeForConstant(*e);
                }
                let c = self.target.concreteConstSetLiteralClass().unwrap();
                self.getConstantConcreteType(c, key, std::slice::from_ref(typeArgument))
            }
            Constant::Record { positional, named, recordType } => {
                let DartType::Record(rt) = recordType else { unreachable!() };
                let shape = RecordShape::new(rt, env);
                let receiver = self.epl.addAllocatedRecord(&shape);
                let mut fieldTypes = vec![Type::Empty; shape.numFields()];
                for (i, p) in positional.iter().enumerate() {
                    let f = self.epl.getRecordPositionalField(&shape, i);
                    let value = self.typeForConstant(*p);
                    fieldTypes[i] = if value.isSpecialized() { value.clone() } else { anyInstanceType };
                    self.epl.addFieldUsedInConstant(&f, &receiver, &value);
                }
                let mut namedIndex = positional.len();
                for (name, v) in named {
                    let f = self.epl.getRecordNamedField(&shape, &env.index.string(*name));
                    let value = self.typeForConstant(*v);
                    fieldTypes[namedIndex] = if value.isSpecialized() { value.clone() } else { anyInstanceType };
                    namedIndex += 1;
                    self.epl.addFieldUsedInConstant(&f, &receiver, &value);
                }
                recordConcreteType(&receiver.concrete().unwrap().cls, fieldTypes)
            }
            Constant::Instance { classReference, typeArguments, fieldValues } => {
                let resultType = self.getConstantConcreteType(*classReference, key, typeArguments);
                for (field, value) in fieldValues {
                    let v = self.typeForConstant(*value);
                    self.epl.addFieldUsedInConstant(&self.memberOfTarget(*field), &resultType, &v);
                }
                resultType
            }
            Constant::StaticTearOff { targetReference }
            | Constant::ConstructorTearOff { targetReference }
            | Constant::RedirectingFactoryTearOff { targetReference } => {
                self.epl.addRawCall(Selector::Direct { member: MemberId::Node(*targetReference), callKind: CallKind::Method });
                if let Some(MemberNode::Constructor(_)) = env.index.member(*targetReference) {
                    self.epl.addAllocatedClass(env.index.enclosingClass(*targetReference).unwrap());
                }
                self.epl.recordTearOff(*targetReference);
                let c = self.target.concreteClosureClass().unwrap();
                self.getConstantConcreteType(c, key, &[])
            }
            Constant::Instantiation { tearOffConstant, .. } => {
                let inner = TFConstant::fromTable(*tearOffConstant, env);
                self.visitConstant(*tearOffConstant, inner);
                self.constantStaticType(id)
            }
            Constant::TypeLiteral { .. } => self.coneOf(env.coreTypes.typeClass),
            Constant::TypedefTearOff { .. } => panic!("TypedefTearOffConstant is not supported (should be constant evaluated)."),
            Constant::Unevaluated { .. } => panic!("UnevaluatedConstant is not supported (should be constant evaluated)."),
        }
    }
}

/// `Field.FlagLate`.
const FIELD_LATE: u32 = 1 << 5;
/// `Procedure.FlagHasWeakTearoffReferencePragma`.
const PROCEDURE_WEAK_TEAROFF: u32 = 1 << 8;

fn useTypeCheckForParameter(decl: &Variable) -> bool {
    let f = VariableFlags::of(decl);
    f.isCovariantByDeclaration || f.isCovariantByClass
}

/// `hasReceiverArg` (utils.dart).
pub fn hasReceiverArg(member: MemberNode, env: &Env) -> bool {
    let isInstance = match member {
        MemberNode::Field(f) => f.flags & kernel::class_hierarchy::FIELD_STATIC == 0 && env.index.enclosingClass(f.fieldReference).is_some(),
        MemberNode::Procedure(p) => {
            p.flags & kernel::class_hierarchy::PROCEDURE_STATIC == 0
                && p.kind != ProcedureKind::Factory
                && env.index.enclosingClass(p.reference).is_some()
        }
        MemberNode::Constructor(_) => true,
    };
    isInstance
}

/// `numTypeParams` (utils.dart).
pub fn numTypeParams(member: MemberNode) -> usize {
    match member {
        MemberNode::Procedure(p) if p.kind == ProcedureKind::Factory => p.function.typeParameters.len(),
        _ => 0,
    }
}

// _SummaryNormalizer, with the statements' `simplify`.

struct Normalizer<'s, 'e> {
    summary: &'s mut Summary,
    tb: &'s dyn TypesBuilder,
    env: &'s Env<'e>,
    processed: HashSet<StmtId>,
    pending: HashSet<StmtId>,
    inLoop: bool,
}

pub fn normalize(summary: &mut Summary, tb: &dyn TypesBuilder, env: &Env) {
    let mut n = Normalizer { summary, tb, env, processed: HashSet::new(), pending: HashSet::new(), inLoop: false };
    n.normalize();
}

impl<'s, 'e> Normalizer<'s, 'e> {
    fn normalize(&mut self) {
        let statements = self.summary.statements.clone();
        for &st in statements.iter().rev() {
            if matches!(self.summary.st(st).kind, StatementKind::Join { .. }) {
                self.excludeRedundantJoinPaths(st);
            }
        }
        self.summary.reset();
        let positional = self.summary.positionalParameterCount;
        let count = self.summary.parameterCount;
        for &st in &statements[..positional] {
            self.processed.insert(st);
            self.summary.add(st);
        }
        if positional < count {
            let mut named: Vec<StmtId> = statements[positional..count].to_vec();
            named.sort_by(|a, b| self.paramName(*a).cmp(&self.paramName(*b)));
            for st in named {
                self.processed.insert(st);
                self.summary.add(st);
            }
        }
        for &st in &statements {
            match &self.summary.st(st).kind {
                StatementKind::Call { .. } | StatementKind::TypeCheck { .. } | StatementKind::NarrowNotNull { .. } | StatementKind::WriteVariable { .. } => {
                    self.normalizeExpr(TypeExpr::Stmt(st), false);
                }
                StatementKind::Use { arg } => {
                    let arg = arg.clone();
                    self.normalizeExpr(arg, true);
                }
                _ => {}
            }
        }
        let result = self.summary.result.clone();
        self.summary.result = self.normalizeExpr(result, true);
    }

    fn paramName(&self, s: StmtId) -> String {
        match &self.summary.st(s).kind {
            StatementKind::Parameter { name, .. } => name.clone(),
            _ => unreachable!(),
        }
    }

    fn excludeRedundantJoinPaths(&mut self, join: StmtId) {
        let mut cache: HashMap<StmtId, TypeExpr> = HashMap::new();
        let values = match &self.summary.st(join).kind {
            StatementKind::Join { values, .. } => values.clone(),
            _ => unreachable!(),
        };
        let mut newValues = Vec::new();
        for v in values {
            newValues.push(self.excludeInternal(v, join, &mut cache));
        }
        if let StatementKind::Join { values, .. } = &mut self.summary.stMut(join).kind {
            *values = newValues;
        }
    }

    fn excludeInternal(&mut self, expr: TypeExpr, join: StmtId, cache: &mut HashMap<StmtId, TypeExpr>) -> TypeExpr {
        if expr.isEmpty() || expr == TypeExpr::Stmt(join) {
            return TypeExpr::empty();
        }
        let TypeExpr::Stmt(e) = expr else { return expr };
        if self.summary.st(e).index < self.summary.st(join).index {
            return expr;
        }
        let st = self.summary.st(e).clone();
        // `simplifyUnaryStatement`.
        let unary = |this: &mut Self, cache: &mut HashMap<StmtId, TypeExpr>, origArg: TypeExpr, create: &dyn Fn(TypeExpr) -> SStatement| -> TypeExpr {
            if let Some(r) = cache.get(&e) {
                return r.clone();
            }
            cache.insert(e, TypeExpr::empty());
            let arg = this.excludeInternal(origArg.clone(), join, cache);
            let result = if arg.isEmpty() {
                TypeExpr::empty()
            } else if arg == origArg {
                TypeExpr::Stmt(e)
            } else {
                let mut s = create(arg);
                s.index = st.index;
                TypeExpr::Stmt(this.summary.alloc(s))
            };
            cache.insert(e, result.clone());
            result
        };
        match &st.kind {
            StatementKind::Unary { op: UnaryOp::Move, arg } => {
                let cond = st.condition.clone();
                if *arg == TypeExpr::Type(nullableEmptyType()) {
                    if let Some(TypeExpr::Stmt(c)) = &cond {
                        if let StatementKind::Unary { op: UnaryOp::IsNull, arg: condArg } = &self.summary.st(*c).kind {
                            let condArg = condArg.clone();
                            let condCondition = self.summary.st(*c).condition.clone();
                            return unary(self, cache, condArg, &|a| SStatement {
                                index: -1,
                                condition: condCondition.clone(),
                                kind: StatementKind::Narrow { arg: a, type_: nullableEmptyType() },
                            });
                        }
                    }
                }
                unary(self, cache, arg.clone(), &|a| SStatement { index: -1, condition: cond.clone(), kind: StatementKind::Unary { op: UnaryOp::Move, arg: a } })
            }
            StatementKind::Narrow { .. } | StatementKind::NarrowNotNull { .. } => {
                let (arg, ty) = st.asNarrow().map(|(a, t)| (a.clone(), t)).unwrap();
                let cond = st.condition.clone();
                unary(self, cache, arg, &|a| SStatement { index: -1, condition: cond.clone(), kind: StatementKind::Narrow { arg: a, type_: ty.clone() } })
            }
            StatementKind::TypeCheck { arg, staticType, .. } => {
                let cond = st.condition.clone();
                let ty = staticType.clone();
                unary(self, cache, arg.clone(), &|a| SStatement { index: -1, condition: cond.clone(), kind: StatementKind::Narrow { arg: a, type_: ty.clone() } })
            }
            StatementKind::Join { values, staticType, .. } => {
                if let Some(r) = cache.get(&e) {
                    return r.clone();
                }
                cache.insert(e, TypeExpr::empty());
                let mut changed = false;
                let mut newValues: Vec<TypeExpr> = Vec::new();
                for v in values {
                    let nv = self.excludeInternal(v.clone(), join, cache);
                    changed |= nv != *v;
                    if !nv.isEmpty() && !newValues.contains(&nv) {
                        newValues.push(nv);
                    }
                }
                let result = if !changed {
                    TypeExpr::Stmt(e)
                } else if newValues.is_empty() {
                    TypeExpr::empty()
                } else if newValues.len() == 1 {
                    newValues.pop().unwrap()
                } else {
                    let s = SStatement {
                        index: st.index,
                        condition: st.condition.clone(),
                        kind: StatementKind::Join { name: None, staticType: staticType.clone(), values: newValues },
                    };
                    TypeExpr::Stmt(self.summary.alloc(s))
                };
                cache.insert(e, result.clone());
                result
            }
            _ => expr,
        }
    }

    fn normalizeExpr(&mut self, st: TypeExpr, isResultUsed: bool) -> TypeExpr {
        let TypeExpr::Stmt(s) = st else { return st };
        if isResultUsed {
            if let StatementKind::Call { isResultUsed: used, .. } = &mut self.summary.stMut(s).kind {
                *used = true;
            }
        }
        if self.processed.contains(&s) {
            return st;
        }
        if self.pending.insert(s) {
            self.visit(s);
            self.pending.remove(&s);
            if self.inLoop {
                return self.handleLoop(s);
            }
            if let Some(TypeExpr::Type(c)) = self.summary.st(s).condition.clone() {
                if c == Type::Empty || c == constantBool(self.tb, self.env, false) {
                    return TypeExpr::empty();
                }
                self.summary.stMut(s).condition = None;
            }
            if let Some(simplified) = self.simplify(s) {
                return simplified;
            }
            self.processed.insert(s);
            self.summary.add(s);
            st
        } else {
            self.handleLoop(s)
        }
    }

    fn handleLoop(&mut self, s: StmtId) -> TypeExpr {
        if let StatementKind::Join { staticType, .. } = &self.summary.st(s).kind {
            self.inLoop = false;
            let t = staticType.clone();
            TypeExpr::Type(fromStaticType(self.tb, self.env, &t, true))
        } else {
            self.inLoop = true;
            TypeExpr::Stmt(s)
        }
    }

    fn visit(&mut self, s: StmtId) {
        // visitStatement: the condition first.
        if let Some(c) = self.summary.st(s).condition.clone() {
            let n = self.normalizeExpr(c, true);
            self.summary.stMut(s).condition = Some(n);
        }
        if self.inLoop {
            return;
        }
        let kind = self.summary.st(s).kind.clone();
        macro_rules! norm {
            ($e:expr) => {{
                let r = self.normalizeExpr($e, true);
                r
            }};
        }
        match kind {
            StatementKind::Parameter { .. } => panic!("\"Parameter\" statement should not be referenced"),
            StatementKind::Use { .. } => panic!("\"Use\" statement should not be referenced"),
            StatementKind::ReadVariable { .. } => {}
            StatementKind::Narrow { arg, .. }
            | StatementKind::NarrowNotNull { arg }
            | StatementKind::Extract { arg, .. }
            | StatementKind::ApplyNullability { arg, .. }
            | StatementKind::Unary { arg, .. }
            | StatementKind::WriteVariable { arg, .. } => {
                let n = norm!(arg);
                self.setArg(s, n);
            }
            StatementKind::Join { values, .. } => {
                for (i, v) in values.into_iter().enumerate() {
                    let n = norm!(v);
                    if let StatementKind::Join { values, .. } = &mut self.summary.stMut(s).kind {
                        values[i] = n;
                    }
                    if self.inLoop {
                        return;
                    }
                }
            }
            StatementKind::Call { args, .. } => {
                for (i, v) in args.values.into_iter().enumerate() {
                    let n = norm!(v);
                    if let StatementKind::Call { args, .. } = &mut self.summary.stMut(s).kind {
                        args.values[i] = n;
                    }
                    if self.inLoop {
                        return;
                    }
                }
            }
            StatementKind::CreateConcreteType { flattenedTypeArgs: list, .. }
            | StatementKind::CreateRecordType { fieldTypes: list, .. }
            | StatementKind::CreateRuntimeType { flattenedTypeArgs: list, .. } => {
                for (i, v) in list.into_iter().enumerate() {
                    let n = norm!(v);
                    match &mut self.summary.stMut(s).kind {
                        StatementKind::CreateConcreteType { flattenedTypeArgs: l, .. }
                        | StatementKind::CreateRecordType { fieldTypes: l, .. }
                        | StatementKind::CreateRuntimeType { flattenedTypeArgs: l, .. } => l[i] = n,
                        _ => unreachable!(),
                    }
                    if self.inLoop {
                        return;
                    }
                }
            }
            StatementKind::TypeCheck { arg, type_, .. } => {
                let n = norm!(arg);
                if let StatementKind::TypeCheck { arg, .. } = &mut self.summary.stMut(s).kind {
                    *arg = n;
                }
                if self.inLoop {
                    return;
                }
                let n = norm!(type_);
                if let StatementKind::TypeCheck { type_, .. } = &mut self.summary.stMut(s).kind {
                    *type_ = n;
                }
            }
            StatementKind::Binary { arg1, arg2, .. } => {
                let n = norm!(arg1);
                if let StatementKind::Binary { arg1, .. } = &mut self.summary.stMut(s).kind {
                    *arg1 = n;
                }
                if self.inLoop {
                    return;
                }
                let n = norm!(arg2);
                if let StatementKind::Binary { arg2, .. } = &mut self.summary.stMut(s).kind {
                    *arg2 = n;
                }
            }
        }
    }

    fn setArg(&mut self, s: StmtId, n: TypeExpr) {
        match &mut self.summary.stMut(s).kind {
            StatementKind::Narrow { arg, .. }
            | StatementKind::NarrowNotNull { arg }
            | StatementKind::Extract { arg, .. }
            | StatementKind::ApplyNullability { arg, .. }
            | StatementKind::Unary { arg, .. }
            | StatementKind::WriteVariable { arg, .. } => *arg = n,
            _ => unreachable!(),
        }
    }

    /// `_canBeNull` of `Join`.
    fn canBeNull(&self, mut expr: TypeExpr) -> bool {
        loop {
            match &expr {
                TypeExpr::Type(t) => return t.isNullable(),
                TypeExpr::Stmt(s) => match &self.summary.st(*s).kind {
                    StatementKind::Call { isInstanceCreation: true, .. } => return false,
                    StatementKind::Narrow { type_: Type::Nullable(_), arg } => expr = arg.clone(),
                    StatementKind::Unary { op: UnaryOp::Move, arg } => expr = arg.clone(),
                    StatementKind::Narrow { .. } | StatementKind::NarrowNotNull { .. } | StatementKind::Unary { .. } | StatementKind::Binary { .. } => {
                        return false;
                    }
                    _ => return true,
                },
            }
        }
    }

    /// `simplify` of each statement.
    fn simplify(&mut self, s: StmtId) -> Option<TypeExpr> {
        let st = self.summary.st(s).clone();
        let hasCondition = st.condition.is_some();
        let constantTrue = constantBool(self.tb, self.env, true);
        let constantFalse = constantBool(self.tb, self.env, false);
        let boolT = boolType(self.tb, self.env);
        match st.kind {
            StatementKind::Narrow { arg, type_ } => {
                if arg.isEmpty() || type_ == Type::Empty {
                    return Some(TypeExpr::empty());
                }
                if hasCondition {
                    return None;
                }
                if type_ == nullableAnyType() {
                    return Some(arg);
                }
                match &arg {
                    TypeExpr::Type(a) => {
                        if *a == nullableAnyType() {
                            return Some(TypeExpr::Type(type_));
                        }
                        if type_ == anyInstanceType {
                            return Some(TypeExpr::Type(match a {
                                Type::Nullable(b) => (**b).clone(),
                                _ => a.clone(),
                            }));
                        }
                        if *a == anyInstanceType {
                            return Some(TypeExpr::Type(match &type_ {
                                Type::Nullable(b) => (**b).clone(),
                                _ => type_.clone(),
                            }));
                        }
                        if *a == nullableEmptyType() || type_ == nullableEmptyType() {
                            return Some(TypeExpr::Type(if a.isNullable() && type_.isNullable() { nullableEmptyType() } else { Type::Empty }));
                        }
                        None
                    }
                    TypeExpr::Stmt(a) => {
                        if matches!(self.summary.st(*a).kind, StatementKind::Call { isInstanceCreation: true, .. }) && type_ == anyInstanceType {
                            return Some(arg);
                        }
                        None
                    }
                }
            }
            StatementKind::NarrowNotNull { arg } => match arg {
                TypeExpr::Type(t) => Some(TypeExpr::Type(match t {
                    Type::Nullable(b) => *b,
                    other => other,
                })),
                _ => None,
            },
            StatementKind::Join { values, .. } => {
                let hasNull = values.iter().any(|v| matches!(v, TypeExpr::Type(Type::Nullable(_))));
                let mut valuesSet: Vec<TypeExpr> = Vec::new();
                let mut out: Vec<TypeExpr> = Vec::new();
                for v in values {
                    let v = if hasNull && v == TypeExpr::Type(anyInstanceType) { TypeExpr::Type(nullableAnyType()) } else { v };
                    if !v.isEmpty() && !valuesSet.contains(&v) {
                        valuesSet.push(v.clone());
                        out.push(v);
                    }
                }
                let hasNullableAny = valuesSet.contains(&TypeExpr::Type(nullableAnyType()));
                let hasAnyInstance = valuesSet.contains(&TypeExpr::Type(anyInstanceType));
                let mut kept = Vec::new();
                for v in out {
                    let mut redundant = false;
                    let mut e = v.clone();
                    loop {
                        let arg = match &e {
                            TypeExpr::Stmt(x) => match &self.summary.st(*x).kind {
                                StatementKind::Unary { op: UnaryOp::Move, arg } => arg.clone(),
                                StatementKind::Narrow { arg, .. } | StatementKind::NarrowNotNull { arg } => arg.clone(),
                                _ => break,
                            },
                            _ => break,
                        };
                        if arg.isEmpty() || valuesSet.contains(&arg) {
                            redundant = true;
                            break;
                        }
                        e = arg;
                    }
                    if !redundant {
                        if hasNullableAny && v != TypeExpr::Type(nullableAnyType()) {
                            redundant = true;
                        } else if hasAnyInstance && v != TypeExpr::Type(anyInstanceType) && !self.canBeNull(v.clone()) {
                            redundant = true;
                        }
                    }
                    if !redundant {
                        kept.push(v);
                    }
                }
                if kept.is_empty() {
                    return Some(TypeExpr::empty());
                }
                if kept.len() == 1 && !hasCondition {
                    return Some(kept.pop().unwrap());
                }
                if let StatementKind::Join { values, .. } = &mut self.summary.stMut(s).kind {
                    *values = kept;
                }
                None
            }
            StatementKind::CreateRecordType { cls, fieldTypes } => {
                let mut all = true;
                for f in &fieldTypes {
                    if f.isEmpty() {
                        return Some(TypeExpr::empty());
                    }
                    match f {
                        TypeExpr::Type(t) if t.isSpecialized() => {}
                        _ => all = false,
                    }
                }
                if hasCondition || !all {
                    return None;
                }
                Some(TypeExpr::Type(recordConcreteType(&cls, fieldTypes.into_iter().map(|f| f.asType().unwrap().clone()).collect())))
            }
            StatementKind::Unary { op, arg } => {
                if arg.isEmpty() && op != UnaryOp::IsEmpty {
                    return Some(TypeExpr::empty());
                }
                if hasCondition {
                    return None;
                }
                if op == UnaryOp::Move {
                    return Some(arg);
                }
                let TypeExpr::Type(a) = arg else { return None };
                match op {
                    UnaryOp::Move => unreachable!(),
                    UnaryOp::IsNull => {
                        if let Type::Nullable(b) = &a {
                            if **b == Type::Empty {
                                return Some(TypeExpr::Type(constantTrue));
                            }
                            if b.isSpecialized() {
                                return Some(TypeExpr::Type(boolT));
                            }
                            return None;
                        }
                        Some(TypeExpr::Type(constantFalse))
                    }
                    UnaryOp::IsEmpty => {
                        if a == Type::Empty {
                            return Some(TypeExpr::Type(constantTrue));
                        }
                        if a.isNullable() || a.isSpecialized() {
                            return Some(TypeExpr::Type(boolT));
                        }
                        None
                    }
                    UnaryOp::Not => {
                        if a == constantTrue {
                            return Some(TypeExpr::Type(constantFalse));
                        }
                        if a == constantFalse {
                            return Some(TypeExpr::Type(constantTrue));
                        }
                        Some(TypeExpr::Type(boolT))
                    }
                }
            }
            StatementKind::Binary { op, arg1, arg2 } => {
                if arg1.isEmpty() {
                    return Some(TypeExpr::empty());
                }
                if hasCondition {
                    return None;
                }
                let left = arg1.asType().cloned();
                match op {
                    BinaryOp::Or => {
                        if left.as_ref() == Some(&constantTrue) {
                            return Some(TypeExpr::Type(constantTrue));
                        }
                        if left.as_ref() == Some(&constantFalse) {
                            return Some(arg2);
                        }
                    }
                    BinaryOp::And => {
                        if left.as_ref() == Some(&constantFalse) {
                            return Some(TypeExpr::Type(constantFalse));
                        }
                        if left.as_ref() == Some(&constantTrue) {
                            return Some(arg2);
                        }
                    }
                }
                if left.is_some() {
                    return Some(TypeExpr::Type(boolT));
                }
                None
            }
            _ => None,
        }
    }
}
