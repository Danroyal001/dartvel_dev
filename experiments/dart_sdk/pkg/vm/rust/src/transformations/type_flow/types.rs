// Port of lib/transformations/type_flow/types.dart: the type lattice of the
// analysis (`Type` and its subclasses), `TFClass`, `RecordShape` and
// `TypesBuilder`.
//
// Ported so far: the types, their equality and their text, and what the
// summary collector builds them with (`fromStaticType`, constant and
// closure types). `union`, `intersection` and `specialize`, which only the
// analysis proper applies, are not ported yet.
use std::rc::Rc;

use kernel::ast::*;
use kernel::core_types::Nullability;
use kernel::src::printer::{AstPrinter, doubleToString, escapeString};

use super::Env;

/// `TFClass`.
#[derive(Debug)]
pub struct TFClass {
    pub id: i64,
    pub classNode: CnId,
    pub recordShape: Option<RecordShape>,
}

impl TFClass {
    pub fn isRecord(&self) -> bool {
        self.recordShape.is_some()
    }

    /// `toString`.
    pub fn toText(&self, env: &Env) -> String {
        let name = AstPrinter::new(env.index, None).className(self.classNode);
        match &self.recordShape {
            Some(shape) => format!("{name}[{}]", shape.toText()),
            None => name,
        }
    }
}

/// `RecordShape`.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct RecordShape {
    pub numPositionalFields: usize,
    pub namedFields: Vec<String>,
}

impl RecordShape {
    pub fn new(ty: &RecordType, env: &Env) -> Self {
        RecordShape {
            numPositionalFields: ty.positional.len(),
            namedFields: ty.named.iter().map(|n| env.index.string(n.name)).collect(),
        }
    }

    pub fn numFields(&self) -> usize {
        self.numPositionalFields + self.namedFields.len()
    }

    /// `fieldName`.
    pub fn fieldName(&self, i: usize) -> String {
        if i < self.numPositionalFields { format!("${}", i + 1) } else { self.namedFields[i - self.numPositionalFields].clone() }
    }

    pub fn toText(&self) -> String {
        if self.namedFields.is_empty() {
            format!("{}", self.numPositionalFields)
        } else {
            format!("{},{}", self.numPositionalFields, self.namedFields.join(","))
        }
    }
}

/// A constant as the analysis keys types by it: upstream's `Constant`,
/// whose equality is by value. The primitive constants a literal makes
/// (`IntConstant(value)`) are values here; the others are the component's
/// constants, which the format already shares by value.
#[derive(Debug, Clone)]
pub enum TFConstant {
    Bool(bool),
    Int(i64),
    Double(f64),
    String(String),
    Table(ConstId),
}

impl PartialEq for TFConstant {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (TFConstant::Bool(a), TFConstant::Bool(b)) => a == b,
            (TFConstant::Int(a), TFConstant::Int(b)) => a == b,
            (TFConstant::Double(a), TFConstant::Double(b)) => a.to_bits() == b.to_bits(),
            (TFConstant::String(a), TFConstant::String(b)) => a == b,
            (TFConstant::Table(a), TFConstant::Table(b)) => a == b,
            _ => false,
        }
    }
}

impl TFConstant {
    /// The constant [id] of the component, primitive ones as values.
    pub fn fromTable(id: ConstId, env: &Env) -> Self {
        match &env.index.component.constants[id as usize] {
            Constant::Bool(b) => TFConstant::Bool(*b),
            Constant::Int(i) => TFConstant::Int(*i),
            Constant::Double(d) => TFConstant::Double(*d),
            Constant::String(s) => TFConstant::String(env.index.string(*s)),
            _ => TFConstant::Table(id),
        }
    }

    /// `nodeToText(constant)`.
    pub fn toText(&self, env: &Env) -> String {
        match self {
            TFConstant::Bool(b) => b.to_string(),
            TFConstant::Int(i) => i.to_string(),
            TFConstant::Double(d) => doubleToString(*d),
            TFConstant::String(s) => format!("\"{}\"", escapeString(s)),
            TFConstant::Table(id) => {
                let mut printer = AstPrinter::new(env.index, None);
                printer.writeConstantId(*id);
                printer.getText()
            }
        }
    }
}

/// A member the analysis refers to: one of the component's, or one the
/// analysis makes (a record field, a closure's call method).
#[derive(Debug, Clone, PartialEq)]
pub enum MemberId {
    Node(CnId),
    /// `Field.immutable(Name(name))`, as the summary collector test's
    /// entry points listener makes for record fields.
    SyntheticField(String),
    /// `Closure.createCallMethod()`.
    ClosureCall(Box<Closure>),
}

impl MemberId {
    /// `nodeToText(member)`.
    pub fn toText(&self, env: &Env) -> String {
        match self {
            MemberId::Node(r) => AstPrinter::new(env.index, None).qualifiedMemberName(*r, true),
            MemberId::SyntheticField(name) => name.clone(),
            MemberId::ClosureCall(_) => "call".into(),
        }
    }
}

/// `Closure`: a tear-off of [member], or the local function [function] in
/// it (by identity, with its `localFunctionName`).
#[derive(Debug, Clone)]
pub struct Closure {
    pub member: CnId,
    pub function: Option<(usize, String)>,
}

impl PartialEq for Closure {
    fn eq(&self, other: &Self) -> bool {
        self.member == other.member && self.function.as_ref().map(|f| f.0) == other.function.as_ref().map(|f| f.0)
    }
}

impl Closure {
    pub fn toText(&self, env: &Env) -> String {
        match &self.function {
            None => format!("tear-off {}", MemberId::Node(self.member).toText(env)),
            Some((_, name)) => name.clone(),
        }
    }
}

/// `TypeAttributes`.
#[derive(Debug, Clone, PartialEq)]
pub struct TypeAttributes {
    pub constant: Option<TFConstant>,
    pub closure: Option<Closure>,
}

impl TypeAttributes {
    pub fn toText(&self, env: &Env) -> String {
        let mut buf = String::new();
        if let Some(c) = &self.constant {
            buf.push_str(&c.toText(env));
        }
        if let Some(c) = &self.closure {
            if !buf.is_empty() {
                buf.push_str(", ");
            }
            buf.push_str(&c.toText(env));
        }
        buf
    }
}

#[derive(Debug, Clone)]
pub enum ConcreteKind {
    Class { numImmediateTypeArgs: usize, typeArgs: Option<Vec<Type>>, attributes: Option<TypeAttributes> },
    Record { fieldTypes: Vec<Type>, depth: usize, isRaw: bool },
}

/// `ConcreteType` (`ClassConcreteType` and `RecordConcreteType`).
#[derive(Debug, Clone)]
pub struct ConcreteType {
    pub cls: Rc<TFClass>,
    pub kind: ConcreteKind,
}

impl PartialEq for ConcreteType {
    fn eq(&self, other: &Self) -> bool {
        if self.cls.id != other.cls.id {
            return false;
        }
        match (&self.kind, &other.kind) {
            (
                ConcreteKind::Class { typeArgs: a, attributes: x, .. },
                ConcreteKind::Class { typeArgs: b, attributes: y, .. },
            ) => a == b && x == y,
            (ConcreteKind::Record { fieldTypes: a, .. }, ConcreteKind::Record { fieldTypes: b, .. }) => a == b,
            _ => false,
        }
    }
}

pub const maxRecordDepth: usize = 3;

/// `RuntimeType`.
#[derive(Debug, Clone)]
pub struct RuntimeType {
    pub type_: DartType,
    pub typeArgs: Option<Vec<Type>>,
    pub numImmediateTypeArgs: usize,
}

impl PartialEq for RuntimeType {
    fn eq(&self, other: &Self) -> bool {
        self.type_ == other.type_ && (self.typeArgs.is_none() || self.typeArgs == other.typeArgs)
    }
}

impl RuntimeType {
    pub fn new(type_: DartType, typeArgs: Option<Vec<Type>>, env: &Env) -> Self {
        let numImmediateTypeArgs = match &type_ {
            DartType::Interface { classReference, .. } => env.index.class(*classReference).map(|c| c.typeParameters.len()).unwrap_or(0),
            DartType::FutureOr { .. } => 1,
            _ => 0,
        };
        RuntimeType { type_, typeArgs, numImmediateTypeArgs }
    }

    pub fn nullability(&self) -> u8 {
        kernel::type_algebra::declaredNullability(&self.type_)
    }

    pub fn toText(&self, env: &Env) -> String {
        let mut printer = AstPrinter::new(env.index, None);
        let head = match &self.type_ {
            DartType::Interface { classReference, .. } => printer.className(*classReference),
            t => {
                printer.writeType(t);
                printer.getText()
            }
        };
        let args = if self.numImmediateTypeArgs == 0 {
            String::new()
        } else {
            let list: Vec<String> =
                self.typeArgs.as_ref().unwrap()[..self.numImmediateTypeArgs].iter().map(|t| t.toText(env)).collect();
            format!("<{}>", list.join(", "))
        };
        let n = kernel::type_algebra::nullability(&self.type_, env.index);
        format!("{head}{args}{}", if n == Nullability::nullable { "?" } else { "" })
    }
}

/// `Type`.
#[derive(Debug, Clone)]
pub enum Type {
    Empty,
    Nullable(Box<Type>),
    AnyInstance,
    Set(Rc<Vec<ConcreteType>>),
    Cone(Rc<TFClass>),
    WideCone(Rc<TFClass>),
    Concrete(Rc<ConcreteType>),
    Runtime(Rc<RuntimeType>),
    Unknown,
}

pub const emptyType: Type = Type::Empty;
pub const anyInstanceType: Type = Type::AnyInstance;
pub const unknownType: Type = Type::Unknown;

pub fn nullableEmptyType() -> Type {
    Type::Nullable(Box::new(Type::Empty))
}

pub fn nullableAnyType() -> Type {
    Type::Nullable(Box::new(Type::AnyInstance))
}

impl PartialEq for Type {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Type::Empty, Type::Empty) | (Type::AnyInstance, Type::AnyInstance) | (Type::Unknown, Type::Unknown) => true,
            (Type::Nullable(a), Type::Nullable(b)) => a == b,
            (Type::Set(a), Type::Set(b)) => a == b,
            (Type::Cone(a), Type::Cone(b)) | (Type::WideCone(a), Type::WideCone(b)) => a.id == b.id,
            (Type::Concrete(a), Type::Concrete(b)) => a == b,
            (Type::Runtime(a), Type::Runtime(b)) => a == b,
            _ => false,
        }
    }
}

impl Type {
    /// `nullable()`.
    pub fn nullable(&self) -> Type {
        match self {
            Type::Nullable(_) => self.clone(),
            Type::Runtime(_) => panic!("ERROR: RuntimeType does not support nullable()."),
            _ => Type::Nullable(Box::new(self.clone())),
        }
    }

    /// `isSpecialized`.
    pub fn isSpecialized(&self) -> bool {
        match self {
            Type::Nullable(b) => b.isSpecialized(),
            Type::Cone(_) => false,
            Type::Runtime(_) => panic!("ERROR: RuntimeType does not support isSpecialized."),
            _ => true,
        }
    }

    pub fn isNullable(&self) -> bool {
        matches!(self, Type::Nullable(_))
    }

    pub fn concrete(&self) -> Option<&ConcreteType> {
        match self {
            Type::Concrete(c) => Some(c),
            _ => None,
        }
    }

    /// `toString`.
    pub fn toText(&self, env: &Env) -> String {
        match self {
            Type::Empty => "_T {}".into(),
            Type::Nullable(b) => format!("{}?", b.toText(env)),
            Type::AnyInstance => "_T ANY".into(),
            Type::Set(types) => {
                let list: Vec<String> = types.iter().map(|t| Type::Concrete(Rc::new(t.clone())).toText(env)).collect();
                format!("_T [{}]", list.join(", "))
            }
            Type::Cone(c) => format!("_T ({})+", c.toText(env)),
            Type::WideCone(c) => format!("_T ({})++", c.toText(env)),
            Type::Concrete(c) => match &c.kind {
                ConcreteKind::Class { numImmediateTypeArgs, typeArgs, attributes } => {
                    if typeArgs.is_none() && attributes.is_none() {
                        return format!("_T ({})", c.cls.toText(env));
                    }
                    let mut buf = format!("_T ({}", c.cls.toText(env));
                    if let Some(args) = typeArgs {
                        let list: Vec<String> = args[..*numImmediateTypeArgs].iter().map(|t| t.toText(env)).collect();
                        buf.push_str(&format!("<{}>", list.join(", ")));
                    }
                    if let Some(a) = attributes {
                        buf.push_str(&format!(", {}", a.toText(env)));
                    }
                    buf.push(')');
                    buf
                }
                ConcreteKind::Record { fieldTypes, isRaw, .. } => {
                    if *isRaw {
                        format!("_T ({})", c.cls.toText(env))
                    } else {
                        let list: Vec<String> = fieldTypes.iter().map(|t| t.toText(env)).collect();
                        format!("_T ({}({}))", c.cls.toText(env), list.join(", "))
                    }
                }
            },
            Type::Runtime(r) => r.toText(env),
            Type::Unknown => "UNKNOWN".into(),
        }
    }
}

/// `TFClass.concreteType`.
pub fn concreteType(cls: &Rc<TFClass>) -> Type {
    match &cls.recordShape {
        Some(shape) => {
            let n = shape.numFields();
            Type::Concrete(Rc::new(ConcreteType {
                cls: cls.clone(),
                kind: ConcreteKind::Record {
                    fieldTypes: vec![nullableAnyType(); n],
                    depth: if n == 0 { 0 } else { maxRecordDepth },
                    isRaw: true,
                },
            }))
        }
        None => Type::Concrete(Rc::new(ConcreteType {
            cls: cls.clone(),
            kind: ConcreteKind::Class { numImmediateTypeArgs: 0, typeArgs: None, attributes: None },
        })),
    }
}

/// `ClassConcreteType(cls, typeArgs)`.
pub fn classConcreteType(cls: &Rc<TFClass>, typeArgs: Vec<Type>, attributes: Option<TypeAttributes>, env: &Env) -> Type {
    let n = env.index.class(cls.classNode).map(|c| c.typeParameters.len()).unwrap_or(0);
    Type::Concrete(Rc::new(ConcreteType {
        cls: cls.clone(),
        kind: ConcreteKind::Class { numImmediateTypeArgs: n, typeArgs: Some(typeArgs), attributes },
    }))
}

/// `TFClass.constantConcreteType`.
pub fn constantConcreteType(cls: &Rc<TFClass>, constant: TFConstant, typeArgs: Option<Vec<Type>>, env: &Env) -> Type {
    let closure = closureForConstant(&constant, env);
    let attributes = TypeAttributes { constant: Some(constant), closure };
    match typeArgs {
        Some(args) => classConcreteType(cls, args, Some(attributes), env),
        None => Type::Concrete(Rc::new(ConcreteType {
            cls: cls.clone(),
            kind: ConcreteKind::Class { numImmediateTypeArgs: 0, typeArgs: None, attributes: Some(attributes) },
        })),
    }
}

fn closureForConstant(constant: &TFConstant, env: &Env) -> Option<Closure> {
    let TFConstant::Table(id) = constant else { return None };
    match &env.index.component.constants[*id as usize] {
        Constant::Instantiation { tearOffConstant, .. } => closureForConstant(&TFConstant::Table(*tearOffConstant), env),
        Constant::StaticTearOff { targetReference }
        | Constant::ConstructorTearOff { targetReference }
        | Constant::RedirectingFactoryTearOff { targetReference } => Some(Closure { member: *targetReference, function: None }),
        Constant::TypedefTearOff { .. } => panic!("Unexpected TypedefTearOffConstant"),
        _ => None,
    }
}

/// `TFClass.closureConcreteType`.
pub fn closureConcreteType(cls: &Rc<TFClass>, member: CnId, function: Option<(usize, String)>) -> Type {
    Type::Concrete(Rc::new(ConcreteType {
        cls: cls.clone(),
        kind: ConcreteKind::Class {
            numImmediateTypeArgs: 0,
            typeArgs: None,
            attributes: Some(TypeAttributes { constant: None, closure: Some(Closure { member, function }) }),
        },
    }))
}

fn recordDepth(t: &Type) -> usize {
    match t {
        Type::Concrete(c) => match &c.kind {
            ConcreteKind::Record { depth, .. } => *depth,
            _ => 0,
        },
        Type::Nullable(b) => recordDepth(b),
        Type::Set(types) => types
            .iter()
            .map(|c| match &c.kind {
                ConcreteKind::Record { depth, .. } => *depth,
                _ => 0,
            })
            .max()
            .unwrap_or(0),
        _ => 0,
    }
}

/// `TFClass.recordConcreteType`.
pub fn recordConcreteType(cls: &Rc<TFClass>, fieldTypes: Vec<Type>) -> Type {
    let mut allNullableAny = true;
    let mut maxFieldDepth = 0;
    for f in &fieldTypes {
        if *f != nullableAnyType() {
            allNullableAny = false;
            maxFieldDepth = maxFieldDepth.max(recordDepth(f));
        }
    }
    if allNullableAny || maxFieldDepth >= maxRecordDepth {
        return concreteType(cls);
    }
    Type::Concrete(Rc::new(ConcreteType {
        cls: cls.clone(),
        kind: ConcreteKind::Record { fieldTypes, depth: maxFieldDepth + 1, isRaw: false },
    }))
}

/// `TypesBuilder`: makes the analysis's classes.
pub trait TypesBuilder {
    fn getTFClass(&self, classNode: CnId) -> Rc<TFClass>;
    fn getRecordClass(&self, shape: &RecordShape) -> Rc<TFClass>;
}

/// `TypesBuilder.boolType`.
pub fn boolType(builder: &dyn TypesBuilder, env: &Env) -> Type {
    concreteType(&builder.getTFClass(env.coreTypes.boolClass))
}

/// `TypesBuilder.constantTrue` / `constantFalse`.
pub fn constantBool(builder: &dyn TypesBuilder, env: &Env, value: bool) -> Type {
    constantConcreteType(&builder.getTFClass(env.coreTypes.boolClass), TFConstant::Bool(value), None, env)
}

/// `TypesBuilder.fromStaticType`.
pub fn fromStaticType(builder: &dyn TypesBuilder, env: &Env, ty: &DartType, mut canBeNull: bool) -> Type {
    let mut result = match ty {
        DartType::Interface { classReference, .. } => Type::Cone(builder.getTFClass(*classReference)),
        DartType::Dynamic | DartType::Void => Type::AnyInstance,
        DartType::Never { .. } | DartType::Null => Type::Empty,
        DartType::Function(_) => Type::Cone(builder.getTFClass(env.coreTypes.functionClass)),
        DartType::Record(r) => Type::Cone(builder.getRecordClass(&RecordShape::new(r, env))),
        DartType::FutureOr { .. } => Type::AnyInstance,
        DartType::TypeParameter { parameter, .. } => {
            let bound = &env.index.typeParameter(*parameter).expect("type parameter").bound;
            if matches!(bound, DartType::TypeParameter { .. }) {
                Type::AnyInstance
            } else {
                fromStaticType(builder, env, bound, canBeNull)
            }
        }
        DartType::Intersection { right, .. } => {
            if matches!(**right, DartType::TypeParameter { .. }) {
                Type::AnyInstance
            } else {
                fromStaticType(builder, env, right, canBeNull)
            }
        }
        DartType::Extension { extensionTypeErasure, .. } => fromStaticType(builder, env, extensionTypeErasure, canBeNull),
        other => panic!("Unexpected type {other:?}"),
    };
    if kernel::type_algebra::nullability(ty, env.index) == Nullability::nonNullable {
        canBeNull = false;
    }
    if canBeNull {
        result = result.nullable();
    }
    result
}
