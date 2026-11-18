// Port of lib/transformations/type_flow/types.dart: the type lattice of the
// analysis (`Type` and its subclasses, with `union`, `intersection`,
// `specialize`), `TFClass`, `RecordShape`, `TypesBuilder` and
// `TypeHierarchy`.
//
// Upstream compares some objects by identity; the port keeps those
// semantics where they show:
//   * a `TFClass` is unique per class id, so `identical` on classes (and on
//     their `coneType`) is equality of ids;
//   * `TypeAttributes` are compared by identity in `ClassConcreteType ==`
//     and by value in `intersectionSameClass`, as upstream; they are shared
//     (`Rc`) and interned per class exactly where upstream interns them
//     (`_concreteTypesWithAttributes`);
//   * `RecordConcreteType.isRaw` (`identical(this, cls.concreteType)`) is
//     the `isRaw` flag, set only on `cls.concreteType`.
// Where upstream's `identical` merely short-cuts to a result equal to the
// one the long way gives (set merging, record field merging), the port
// compares by value.
//
// Not ported yet: `isSubtypeOfRuntimeType`, `RuntimeType.representedType`,
// `withNullability`/`applyNullability`, `Closure.createCallMethod` (the
// analysis needs them; the transformer test will).
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::hash::{Hash, Hasher};
use std::rc::Rc;

use kernel::ast::*;
use kernel::core_types::Nullability;
use kernel::src::printer::{AstPrinter, doubleToString, escapeString};

use super::Env;

/// `kHashMask` (utils.dart).
pub const kHashMask: i64 = 0x3fffffff;

/// `combineHashes` (utils.dart).
pub fn combineHashes(hash1: i64, hash2: i64) -> i64 {
    (((hash1 * 31) & kHashMask) + hash2) & kHashMask
}

/// `null.hashCode` on the Dart VM.
const nullHashCode: i64 = 2011;

/// `TFClass`.
#[derive(Debug)]
pub struct TFClass {
    pub id: i64,
    pub classNode: CnId,
    /// `supertypes`: the ids of the super-types, this class included.
    pub supertypes: HashSet<i64>,
    pub recordShape: Option<RecordShape>,
    /// `toString()`, a function of the class node, computed once.
    text: String,
    /// `_concreteTypesWithAttributes`, by the attributes they intern.
    concreteTypesWithAttributes: RefCell<HashMap<TypeAttributes, Rc<TypeAttributes>>>,
    /// `hasDynamicallyExtendableSubtypes` (false but in the analysis's
    /// `_TFClassImpl`).
    pub dynamicallyExtendableSubtypes: Cell<bool>,
}

impl TFClass {
    /// `TFClass(id, classNode, supertypes, recordShape)`, whose class node
    /// prints as [className] (`nodeToText(classNode)`).
    pub fn new(
        id: i64,
        classNode: CnId,
        supertypes: impl IntoIterator<Item = i64>,
        recordShape: Option<RecordShape>,
        className: String,
    ) -> TFClass {
        let mut set: HashSet<i64> = supertypes.into_iter().collect();
        set.insert(id);
        let text = match &recordShape {
            Some(shape) => format!("{className}[{}]", shape.toText()),
            None => className,
        };
        TFClass {
            id,
            classNode,
            supertypes: set,
            recordShape,
            text,
            concreteTypesWithAttributes: RefCell::new(HashMap::new()),
            dynamicallyExtendableSubtypes: Cell::new(false),
        }
    }

    /// [new] with the class node printed by the component's printer.
    pub fn fromEnv(
        id: i64,
        classNode: CnId,
        supertypes: impl IntoIterator<Item = i64>,
        recordShape: Option<RecordShape>,
        env: &Env,
    ) -> TFClass {
        let name = AstPrinter::new(env.index, None).className(classNode);
        TFClass::new(id, classNode, supertypes, recordShape, name)
    }

    pub fn isRecord(&self) -> bool {
        self.recordShape.is_some()
    }

    /// `isSubtypeOf`.
    pub fn isSubtypeOf(&self, other: &TFClass) -> bool {
        self.id == other.id || self.supertypes.contains(&other.id)
    }

    pub fn hasDynamicallyExtendableSubtypes(&self) -> bool {
        self.dynamicallyExtendableSubtypes.get()
    }

    /// `hashCode`.
    pub fn hashCode(&self) -> i64 {
        self.id
    }

    /// `toString`.
    pub fn toText(&self, _env: &Env) -> String {
        self.text.clone()
    }

    /// `toString`, without a component.
    pub fn text(&self) -> &str {
        &self.text
    }

    /// The attributes `_concreteTypeWithAttributes` keys its types by.
    fn internAttributes(&self, attributes: TypeAttributes) -> Rc<TypeAttributes> {
        self.concreteTypesWithAttributes.borrow_mut().entry(attributes.clone()).or_insert_with(|| Rc::new(attributes)).clone()
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

    /// `fieldIndex`.
    pub fn fieldIndex(&self, name: &str) -> usize {
        if let Some(index) = self.namedFields.iter().position(|n| n == name) {
            return self.numPositionalFields + index;
        }
        name[1..].parse::<usize>().expect("positional field name") - 1
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

impl Eq for TFConstant {}

impl Hash for TFConstant {
    fn hash<H: Hasher>(&self, state: &mut H) {
        match self {
            TFConstant::Bool(b) => (0u8, b).hash(state),
            TFConstant::Int(i) => (1u8, i).hash(state),
            TFConstant::Double(d) => (2u8, d.to_bits()).hash(state),
            TFConstant::String(s) => (3u8, s).hash(state),
            TFConstant::Table(id) => (4u8, id).hash(state),
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
            TFConstant::Table(id) => {
                let mut printer = AstPrinter::new(env.index, None);
                printer.writeConstantId(*id);
                printer.getText()
            }
            primitive => primitive.primitiveText().unwrap(),
        }
    }

    /// `nodeToText` of a primitive constant, which needs no component.
    fn primitiveText(&self) -> Option<String> {
        Some(match self {
            TFConstant::Bool(b) => b.to_string(),
            TFConstant::Int(i) => i.to_string(),
            TFConstant::Double(d) => doubleToString(*d),
            TFConstant::String(s) => format!("\"{}\"", escapeString(s)),
            TFConstant::Table(_) => return None,
        })
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

impl Eq for Closure {}

impl Hash for Closure {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.member.hash(state);
        self.function.as_ref().map(|f| f.0).hash(state);
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

/// `TypeAttributes`. Its `==` is by value; `ClassConcreteType ==` compares
/// the `Rc`s that hold them by identity, as upstream.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
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

    /// `hashCode`: upstream hashes constants and closures by identity or
    /// by fields it does not fix; this stands in with a hash of the value
    /// (never printed, only compared).
    pub fn hashCode(&self) -> i64 {
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        self.hash(&mut hasher);
        (hasher.finish() as i64) & kHashMask
    }
}

fn sameAttributes(a: &Option<Rc<TypeAttributes>>, b: &Option<Rc<TypeAttributes>>) -> bool {
    match (a, b) {
        (None, None) => true,
        (Some(x), Some(y)) => Rc::ptr_eq(x, y),
        _ => false,
    }
}

#[derive(Debug, Clone)]
pub enum ConcreteKind {
    Class { numImmediateTypeArgs: usize, typeArgs: Option<Vec<Type>>, attributes: Option<Rc<TypeAttributes>> },
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
            (ConcreteKind::Class { attributes: x, .. }, ConcreteKind::Class { attributes: y, .. }) => {
                sameAttributes(x, y) && self.hasSameTypeArgs(other)
            }
            (ConcreteKind::Record { fieldTypes: a, .. }, ConcreteKind::Record { fieldTypes: b, .. }) => a == b,
            _ => false,
        }
    }
}

pub const maxRecordDepth: usize = 3;

impl ConcreteType {
    fn classTypeArgs(&self) -> Option<&Vec<Type>> {
        match &self.kind {
            ConcreteKind::Class { typeArgs, .. } => typeArgs.as_ref(),
            _ => None,
        }
    }

    pub fn attributes(&self) -> Option<&Rc<TypeAttributes>> {
        match &self.kind {
            ConcreteKind::Class { attributes, .. } => attributes.as_ref(),
            _ => None,
        }
    }

    fn numImmediateTypeArgs(&self) -> usize {
        match &self.kind {
            ConcreteKind::Class { numImmediateTypeArgs, .. } => *numImmediateTypeArgs,
            _ => 0,
        }
    }

    /// `ClassConcreteType._hasSameTypeArgs`.
    fn hasSameTypeArgs(&self, other: &ConcreteType) -> bool {
        match (self.classTypeArgs(), other.classTypeArgs()) {
            (None, None) => true,
            (Some(a), Some(b)) => (0..self.numImmediateTypeArgs()).all(|i| a[i] == b[i]),
            _ => false,
        }
    }

    /// `isRaw`.
    pub fn isRaw(&self) -> bool {
        match &self.kind {
            ConcreteKind::Class { typeArgs, attributes, .. } => typeArgs.is_none() && attributes.is_none(),
            ConcreteKind::Record { isRaw, .. } => *isRaw,
        }
    }

    /// `raw`: `cls.concreteType`.
    pub fn raw(&self) -> ConcreteType {
        rawConcreteType(&self.cls)
    }

    /// `closure`.
    pub fn closure(&self) -> Option<&Closure> {
        self.attributes().and_then(|a| a.closure.as_ref())
    }

    /// `hashCode`.
    pub fn hashCode(&self) -> i64 {
        match &self.kind {
            ConcreteKind::Class { numImmediateTypeArgs, typeArgs, attributes } => {
                let mut hash = combineHashes(43, self.cls.hashCode());
                for i in 0..*numImmediateTypeArgs {
                    hash = combineHashes(hash, typeArgs.as_ref().unwrap()[i].hashCode());
                }
                combineHashes(hash, attributes.as_ref().map_or(nullHashCode, |a| a.hashCode()))
            }
            ConcreteKind::Record { fieldTypes, .. } => {
                fieldTypes.iter().fold(combineHashes(47, self.cls.hashCode()), |h, t| combineHashes(h, t.hashCode()))
            }
        }
    }

    fn toType(&self) -> Type {
        Type::Concrete(Rc::new(self.clone()))
    }

    /// `unionSameClass`.
    pub fn unionSameClass(&self, other: &ConcreteType, typeHierarchy: &dyn TypeHierarchy) -> ConcreteType {
        assert_eq!(self.cls.id, other.cls.id);
        if self == other || self.isRaw() {
            return self.clone();
        }
        if other.isRaw() {
            return other.clone();
        }
        match (&self.kind, &other.kind) {
            (
                ConcreteKind::Class { numImmediateTypeArgs, typeArgs, attributes },
                ConcreteKind::Class { attributes: otherAttributes, .. },
            ) => {
                if sameAttributes(attributes, otherAttributes) {
                    // Since the attributes are the same (possibly both null),
                    // and `this != other`, the type arguments differ.
                    return self.raw();
                }
                if typeArgs.is_some() && self.hasSameTypeArgs(other) {
                    if attributes.is_none() {
                        return self.clone();
                    }
                    if otherAttributes.is_none() {
                        return other.clone();
                    }
                    return ConcreteType {
                        cls: self.cls.clone(),
                        kind: ConcreteKind::Class {
                            numImmediateTypeArgs: *numImmediateTypeArgs,
                            typeArgs: typeArgs.clone(),
                            attributes: None,
                        },
                    };
                }
                self.raw()
            }
            (ConcreteKind::Record { fieldTypes: thisFields, .. }, ConcreteKind::Record { fieldTypes: otherFields, .. }) => {
                let mut sameAsThis = true;
                let mut sameAsOther = true;
                let mut unionedFields = Vec::with_capacity(thisFields.len());
                for (thisField, otherField) in thisFields.iter().zip(otherFields) {
                    let unioned = thisField.union(otherField, typeHierarchy).specialize(typeHierarchy);
                    if unioned != *thisField {
                        sameAsThis = false;
                    }
                    if unioned != *otherField {
                        sameAsOther = false;
                    }
                    unionedFields.push(unioned);
                }
                if sameAsThis {
                    return self.clone();
                }
                if sameAsOther {
                    return other.clone();
                }
                recordConcreteTypeOf(&self.cls, unionedFields)
            }
            _ => panic!("unionSameClass of a class and a record type"),
        }
    }

    /// `intersectionSameClass`.
    pub fn intersectionSameClass(&self, other: &ConcreteType, typeHierarchy: &dyn TypeHierarchy) -> Type {
        assert_eq!(self.cls.id, other.cls.id);
        if self == other || other.isRaw() {
            return self.toType();
        }
        if self.isRaw() {
            return other.toType();
        }
        match (&self.kind, &other.kind) {
            (
                ConcreteKind::Class { numImmediateTypeArgs, typeArgs: thisTypeArgs, attributes },
                ConcreteKind::Class { typeArgs: otherTypeArgs, attributes: otherAttributes, .. },
            ) => {
                if let (Some(a), Some(b)) = (attributes, otherAttributes)
                    && **a != **b
                {
                    return Type::Empty;
                }
                let mergedAttributes = attributes.clone().or_else(|| otherAttributes.clone());
                let mergedTypeArgs = match (thisTypeArgs, otherTypeArgs) {
                    (None, Some(b)) => b.clone(),
                    (Some(a), None) => a.clone(),
                    (Some(a), Some(b)) => {
                        let mut merged = Vec::with_capacity(a.len());
                        for (x, y) in a.iter().zip(b) {
                            let m = x.intersection(y, typeHierarchy);
                            if matches!(m, Type::Empty) {
                                return Type::Empty;
                            }
                            merged.push(m);
                        }
                        merged
                    }
                    (None, None) => panic!("Null check operator used on a null value"),
                };
                Type::Concrete(Rc::new(ConcreteType {
                    cls: self.cls.clone(),
                    kind: ConcreteKind::Class {
                        numImmediateTypeArgs: *numImmediateTypeArgs,
                        typeArgs: Some(mergedTypeArgs),
                        attributes: mergedAttributes,
                    },
                }))
            }
            (ConcreteKind::Record { fieldTypes: thisFields, .. }, ConcreteKind::Record { fieldTypes: otherFields, .. }) => {
                let mut sameAsThis = true;
                let mut sameAsOther = true;
                let mut mergedFields = Vec::with_capacity(thisFields.len());
                for (thisField, otherField) in thisFields.iter().zip(otherFields) {
                    let merged = thisField.intersection(otherField, typeHierarchy);
                    if matches!(merged, Type::Empty) {
                        return Type::Empty;
                    }
                    if merged != *thisField {
                        sameAsThis = false;
                    }
                    if merged != *otherField {
                        sameAsOther = false;
                    }
                    mergedFields.push(merged);
                }
                if sameAsThis {
                    return self.toType();
                }
                if sameAsOther {
                    return other.toType();
                }
                recordConcreteTypeOf(&self.cls, mergedFields).toType()
            }
            _ => panic!("intersectionSameClass of a class and a record type"),
        }
    }
}

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

    /// `hashCode`: upstream hashes the Dart type, by fields it does not fix
    /// (class nodes hash by identity); this stands in with a hash of the
    /// type's debug form (never printed, only compared).
    pub fn hashCode(&self) -> i64 {
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        format!("{:?}", self.type_).hash(&mut hasher);
        let mut hash = combineHashes(47, (hasher.finish() as i64) & kHashMask);
        for i in 0..self.numImmediateTypeArgs {
            hash = combineHashes(hash, self.typeArgs.as_ref().unwrap()[i].hashCode());
        }
        hash
    }
}

/// `TypeOrder`: the order of precedence between types for evaluation of
/// union and intersection.
pub mod TypeOrder {
    pub const RuntimeType: i32 = 0;
    pub const Unknown: i32 = 1;
    pub const Empty: i32 = 2;
    pub const Nullable: i32 = 3;
    pub const Any: i32 = 4;
    pub const WideCone: i32 = 5;
    pub const Set: i32 = 6;
    pub const Cone: i32 = 7;
    pub const Concrete: i32 = 8;
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

/// `SetType(types)`.
pub fn setType(types: Vec<ConcreteType>) -> Type {
    debug_assert!(types.len() >= 2);
    debug_assert!(types.windows(2).all(|w| w[0].cls.id <= w[1].cls.id));
    Type::Set(Rc::new(types))
}

/// `TypeHierarchy`: the type hierarchy information types use.
pub trait TypeHierarchy {
    /// `specializeTypeCone`.
    fn specializeTypeCone(&self, base: &Rc<TFClass>, allowWideCone: bool) -> Type;

    /// `hasAllocatedSubtypes`.
    fn hasAllocatedSubtypes(&self, cls: &Rc<TFClass>) -> bool;
}

impl Type {
    /// `nullable()`.
    pub fn nullable(&self) -> Type {
        match self {
            Type::Nullable(_) => self.clone(),
            Type::Runtime(_) => panic!("ERROR: RuntimeType does not support nullable()."),
            Type::Unknown => panic!("ERROR: UnknownType does not support nullable()."),
            _ => Type::Nullable(Box::new(self.clone())),
        }
    }

    /// `order`.
    pub fn order(&self) -> i32 {
        match self {
            Type::Runtime(_) => TypeOrder::RuntimeType,
            Type::Unknown => TypeOrder::Unknown,
            Type::Empty => TypeOrder::Empty,
            Type::Nullable(_) => TypeOrder::Nullable,
            Type::AnyInstance => TypeOrder::Any,
            Type::WideCone(_) => TypeOrder::WideCone,
            Type::Set(_) => TypeOrder::Set,
            Type::Cone(_) => TypeOrder::Cone,
            Type::Concrete(_) => TypeOrder::Concrete,
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

    /// `closure`.
    pub fn closure(&self) -> Option<&Closure> {
        match self {
            Type::Concrete(c) => c.closure(),
            _ => None,
        }
    }

    /// `isSubtypeOf(cls)`.
    pub fn isSubtypeOf(&self, cls: &TFClass) -> bool {
        match self {
            Type::Nullable(b) => b.isSubtypeOf(cls),
            Type::Set(types) => types.iter().all(|t| t.cls.isSubtypeOf(cls)),
            Type::Cone(c) | Type::WideCone(c) => c.isSubtypeOf(cls),
            Type::Concrete(c) => c.cls.isSubtypeOf(cls),
            Type::Runtime(_) => panic!("ERROR: RuntimeType does not support isSubtypeOf."),
            Type::Unknown => panic!("ERROR: UnknownType does not support isSubtypeOf."),
            Type::Empty | Type::AnyInstance => false,
        }
    }

    /// `specialize`.
    pub fn specialize(&self, typeHierarchy: &dyn TypeHierarchy) -> Type {
        match self {
            Type::Nullable(b) => {
                if b.isSpecialized() {
                    self.clone()
                } else {
                    b.specialize(typeHierarchy).nullable()
                }
            }
            Type::Cone(c) => typeHierarchy.specializeTypeCone(c, true),
            Type::Runtime(_) => panic!("ERROR: RuntimeType does not support specialize."),
            _ => self.clone(),
        }
    }

    /// `hasEmptySpecialization`.
    pub fn hasEmptySpecialization(&self, typeHierarchy: &dyn TypeHierarchy) -> bool {
        match self {
            Type::Empty => true,
            Type::Cone(c) => !c.hasDynamicallyExtendableSubtypes() && !typeHierarchy.hasAllocatedSubtypes(c),
            _ => false,
        }
    }

    /// `hashCode`.
    pub fn hashCode(&self) -> i64 {
        match self {
            Type::Empty => 997,
            Type::AnyInstance => 991,
            Type::Unknown => 1019,
            Type::Nullable(b) => combineHashes(31, b.hashCode()),
            Type::Set(types) => types.iter().fold(1237, |h, t| combineHashes(h, t.hashCode())),
            Type::Cone(c) => combineHashes(37, c.id),
            Type::WideCone(c) => combineHashes(41, c.id),
            Type::Concrete(c) => c.hashCode(),
            Type::Runtime(r) => r.hashCode(),
        }
    }

    /// `union`.
    pub fn union(&self, other: &Type, typeHierarchy: &dyn TypeHierarchy) -> Type {
        match self {
            Type::Empty => other.clone(),
            Type::Nullable(base) => {
                if other.order() < self.order() {
                    return other.union(self, typeHierarchy);
                }
                match other {
                    Type::Nullable(otherBase) => base.union(otherBase, typeHierarchy).nullable(),
                    _ => base.union(other, typeHierarchy).nullable(),
                }
            }
            Type::AnyInstance => {
                if other.order() < self.order() {
                    return other.union(self, typeHierarchy);
                }
                self.clone()
            }
            Type::Set(types) => {
                if let Type::Set(o) = other
                    && Rc::ptr_eq(types, o)
                {
                    return self.clone();
                }
                if other.order() < self.order() {
                    return other.union(self, typeHierarchy);
                }
                match other {
                    Type::Set(otherTypes) => {
                        if types.len() >= otherTypes.len() {
                            if isSubList(otherTypes, types, typeHierarchy) {
                                return self.clone();
                            }
                        } else if isSubList(types, otherTypes, typeHierarchy) {
                            return other.clone();
                        }
                        setType(unionLists(types, otherTypes, typeHierarchy))
                    }
                    Type::Concrete(c) => match binarySearch(types, c.cls.id) {
                        Ok(index) => {
                            let ty = &types[index];
                            let unioned = ty.unionSameClass(c, typeHierarchy);
                            if unioned == *ty {
                                return self.clone();
                            }
                            let mut list = (**types).clone();
                            list[index] = unioned;
                            setType(list)
                        }
                        Err(index) => {
                            let mut list = (**types).clone();
                            list.insert(index, (**c).clone());
                            setType(list)
                        }
                    },
                    Type::Cone(cls) => typeHierarchy.specializeTypeCone(cls, true).union(self, typeHierarchy),
                    _ => panic!("Unexpected type {other:?}"),
                }
            }
            Type::Cone(cls) => {
                if other.order() < self.order() {
                    return other.union(self, typeHierarchy);
                }
                match other {
                    Type::Cone(otherCls) => {
                        if otherCls.id == cls.id {
                            return self.clone();
                        }
                        if other.hasEmptySpecialization(typeHierarchy) || otherCls.isSubtypeOf(cls) {
                            return self.clone();
                        }
                        if self.hasEmptySpecialization(typeHierarchy) || cls.isSubtypeOf(otherCls) {
                            return other.clone();
                        }
                    }
                    Type::Concrete(c) => {
                        if c.cls.isSubtypeOf(cls) {
                            return self.clone();
                        }
                    }
                    _ => {}
                }
                typeHierarchy.specializeTypeCone(cls, true).union(other, typeHierarchy)
            }
            Type::WideCone(cls) => {
                if other.order() < self.order() {
                    return other.union(self, typeHierarchy);
                }
                match other {
                    Type::Cone(otherCls) | Type::WideCone(otherCls) => {
                        if other.hasEmptySpecialization(typeHierarchy) || otherCls.isSubtypeOf(cls) {
                            return self.clone();
                        }
                        if cls.isSubtypeOf(otherCls) {
                            return other.clone();
                        }
                    }
                    Type::Concrete(c) => {
                        if c.cls.isSubtypeOf(cls) {
                            return self.clone();
                        }
                        if cls.isSubtypeOf(&c.cls) {
                            return Type::Cone(c.cls.clone());
                        }
                    }
                    Type::Set(types) => {
                        if types.iter().all(|t| t.cls.isSubtypeOf(cls)) {
                            return self.clone();
                        }
                    }
                    _ => panic!("Unexpected type {other:?}"),
                }
                // Wider approximation.
                Type::AnyInstance
            }
            Type::Concrete(c) => {
                if other.order() < self.order() {
                    return other.union(self, typeHierarchy);
                }
                match other {
                    Type::Concrete(o) => {
                        if c.cls.id != o.cls.id {
                            let types = if c.cls.id < o.cls.id {
                                vec![(**c).clone(), (**o).clone()]
                            } else {
                                vec![(**o).clone(), (**c).clone()]
                            };
                            return setType(types);
                        }
                        c.unionSameClass(o, typeHierarchy).toType()
                    }
                    _ => panic!("Unexpected type {other:?}"),
                }
            }
            Type::Runtime(_) => panic!("ERROR: RuntimeType does not support union."),
            Type::Unknown => match other {
                Type::Unknown | Type::Runtime(_) => self.clone(),
                _ => panic!("ERROR: UnknownType does not support union with {other:?}"),
            },
        }
    }

    /// `intersection`.
    pub fn intersection(&self, other: &Type, typeHierarchy: &dyn TypeHierarchy) -> Type {
        match self {
            Type::Empty => Type::Empty,
            Type::Nullable(base) => {
                if other.order() < self.order() {
                    return other.intersection(self, typeHierarchy);
                }
                match other {
                    Type::Nullable(otherBase) => base.intersection(otherBase, typeHierarchy).nullable(),
                    _ => base.intersection(other, typeHierarchy),
                }
            }
            Type::AnyInstance => {
                if other.order() < self.order() {
                    return other.intersection(self, typeHierarchy);
                }
                other.clone()
            }
            Type::Set(types) => {
                if let Type::Set(o) = other
                    && Rc::ptr_eq(types, o)
                {
                    return self.clone();
                }
                if other.order() < self.order() {
                    return other.intersection(self, typeHierarchy);
                }
                match other {
                    Type::Set(otherTypes) => {
                        let list = intersectLists(types, otherTypes, typeHierarchy);
                        let size = list.len();
                        if size == 0 {
                            Type::Empty
                        } else if size == 1 {
                            list[0].toType()
                        } else if size == types.len() && **types == list {
                            self.clone()
                        } else if size == otherTypes.len() && **otherTypes == list {
                            other.clone()
                        } else {
                            setType(list)
                        }
                    }
                    Type::Concrete(c) => {
                        for ty in types.iter() {
                            if *ty == **c {
                                return other.clone();
                            }
                            if ty.cls.id == c.cls.id {
                                return ty.intersectionSameClass(c, typeHierarchy);
                            }
                        }
                        Type::Empty
                    }
                    Type::Cone(cls) => typeHierarchy.specializeTypeCone(cls, true).intersection(self, typeHierarchy),
                    _ => panic!("Unexpected type {other:?}"),
                }
            }
            Type::Cone(cls) => {
                if other.order() < self.order() {
                    return other.intersection(self, typeHierarchy);
                }
                match other {
                    Type::Cone(otherCls) => {
                        if otherCls.id == cls.id {
                            return self.clone();
                        }
                        if self.hasEmptySpecialization(typeHierarchy) || other.hasEmptySpecialization(typeHierarchy) {
                            return Type::Empty;
                        }
                        if otherCls.isSubtypeOf(cls) {
                            return other.clone();
                        }
                        if cls.isSubtypeOf(otherCls) {
                            return self.clone();
                        }
                    }
                    Type::Concrete(c) => {
                        return if c.cls.isSubtypeOf(cls) { other.clone() } else { Type::Empty };
                    }
                    _ => {}
                }
                typeHierarchy.specializeTypeCone(cls, true).intersection(other, typeHierarchy)
            }
            Type::WideCone(cls) => {
                if other.order() < self.order() {
                    return other.intersection(self, typeHierarchy);
                }
                match other {
                    Type::Cone(otherCls) | Type::WideCone(otherCls) => {
                        if other.hasEmptySpecialization(typeHierarchy) {
                            return Type::Empty;
                        }
                        if otherCls.isSubtypeOf(cls) {
                            return other.clone();
                        }
                    }
                    Type::Concrete(c) => {
                        return if c.cls.isSubtypeOf(cls) { other.clone() } else { Type::Empty };
                    }
                    Type::Set(otherTypes) => {
                        let list: Vec<ConcreteType> = otherTypes.iter().filter(|t| t.cls.isSubtypeOf(cls)).cloned().collect();
                        let size = list.len();
                        return if size == 0 {
                            Type::Empty
                        } else if size == 1 {
                            list[0].toType()
                        } else if size == otherTypes.len() {
                            other.clone()
                        } else {
                            setType(list)
                        };
                    }
                    _ => panic!("Unexpected type {other:?}"),
                }
                // Wider approximation.
                self.clone()
            }
            Type::Concrete(c) => {
                if other.order() < self.order() {
                    return other.intersection(self, typeHierarchy);
                }
                match other {
                    Type::Concrete(o) => {
                        if c.cls.id != o.cls.id {
                            return Type::Empty;
                        }
                        c.intersectionSameClass(o, typeHierarchy)
                    }
                    _ => panic!("Unexpected type {other:?}"),
                }
            }
            Type::Runtime(r) => match other {
                Type::Unknown => self.clone(),
                Type::Runtime(o) => {
                    if **r == **o {
                        self.clone()
                    } else {
                        Type::Empty
                    }
                }
                _ => panic!("ERROR: RuntimeType cannot intersect with {other:?}"),
            },
            Type::Unknown => match other {
                Type::Unknown | Type::Runtime(_) => other.clone(),
                _ => panic!("ERROR: UnknownType does not support intersection with {other:?}"),
            },
        }
    }

    /// `toString`.
    pub fn toText(&self, env: &Env) -> String {
        self.text(Some(env))
    }

    /// `toString`; [env] is needed only for constants of the component,
    /// closures and runtime types.
    pub fn text(&self, env: Option<&Env>) -> String {
        match self {
            Type::Empty => "_T {}".into(),
            Type::Nullable(b) => format!("{}?", b.text(env)),
            Type::AnyInstance => "_T ANY".into(),
            Type::Set(types) => {
                let list: Vec<String> = types.iter().map(|t| t.toType().text(env)).collect();
                format!("_T [{}]", list.join(", "))
            }
            Type::Cone(c) => format!("_T ({})+", c.text()),
            Type::WideCone(c) => format!("_T ({})++", c.text()),
            Type::Concrete(c) => match &c.kind {
                ConcreteKind::Class { numImmediateTypeArgs, typeArgs, attributes } => {
                    if typeArgs.is_none() && attributes.is_none() {
                        return format!("_T ({})", c.cls.text());
                    }
                    let mut buf = format!("_T ({}", c.cls.text());
                    if let Some(args) = typeArgs {
                        let list: Vec<String> = args[..*numImmediateTypeArgs].iter().map(|t| t.text(env)).collect();
                        buf.push_str(&format!("<{}>", list.join(", ")));
                    }
                    if let Some(a) = attributes {
                        let text = match env {
                            Some(env) => a.toText(env),
                            None => match (&a.constant, &a.closure) {
                                (Some(constant), None) => constant.primitiveText().expect("a component's constant needs the component"),
                                _ => panic!("a closure needs the component"),
                            },
                        };
                        buf.push_str(&format!(", {text}"));
                    }
                    buf.push(')');
                    buf
                }
                ConcreteKind::Record { fieldTypes, isRaw, .. } => {
                    if *isRaw {
                        format!("_T ({})", c.cls.text())
                    } else {
                        let list: Vec<String> = fieldTypes.iter().map(|t| t.text(env)).collect();
                        format!("_T ({}({}))", c.cls.text(), list.join(", "))
                    }
                }
            },
            Type::Runtime(r) => r.toText(env.expect("a runtime type needs the component")),
            Type::Unknown => "UNKNOWN".into(),
        }
    }
}

/// `SetType._binarySearch`, as `Ok(index)` / `Err(insertion point)`
/// (upstream's `index` / `~index`).
fn binarySearch(types: &[ConcreteType], targetId: i64) -> Result<usize, usize> {
    let mut min = 0;
    let mut max = types.len();
    while min < max {
        let mid = (min + max) >> 1;
        let id = types[mid].cls.id;
        if id == targetId {
            return Ok(mid);
        }
        if id < targetId {
            min = mid + 1;
        } else {
            max = mid;
        }
    }
    Err(min)
}

/// `SetType._unionLists`.
fn unionLists(types1: &[ConcreteType], types2: &[ConcreteType], typeHierarchy: &dyn TypeHierarchy) -> Vec<ConcreteType> {
    let mut types = Vec::with_capacity(types1.len() + types2.len());
    let (mut i1, mut i2) = (0, 0);
    while i1 < types1.len() && i2 < types2.len() {
        let (t1, t2) = (&types1[i1], &types2[i2]);
        let (id1, id2) = (t1.cls.id, t2.cls.id);
        if id1 < id2 {
            types.push(t1.clone());
            i1 += 1;
        } else if id1 > id2 {
            types.push(t2.clone());
            i2 += 1;
        } else {
            types.push(t1.unionSameClass(t2, typeHierarchy));
            i1 += 1;
            i2 += 1;
        }
    }
    types.extend_from_slice(&types1[i1..]);
    types.extend_from_slice(&types2[i2..]);
    types
}

/// `SetType._intersectLists`.
fn intersectLists(types1: &[ConcreteType], types2: &[ConcreteType], typeHierarchy: &dyn TypeHierarchy) -> Vec<ConcreteType> {
    let mut types = Vec::new();
    let (mut i1, mut i2) = (0, 0);
    while i1 < types1.len() && i2 < types2.len() {
        let (t1, t2) = (&types1[i1], &types2[i2]);
        let (id1, id2) = (t1.cls.id, t2.cls.id);
        if id1 < id2 {
            i1 += 1;
        } else if id1 > id2 {
            i2 += 1;
        } else {
            if let Type::Concrete(c) = t1.intersectionSameClass(t2, typeHierarchy) {
                types.push((*c).clone());
            }
            i1 += 1;
            i2 += 1;
        }
    }
    types
}

/// `SetType._isSubList`.
fn isSubList(sublist: &[ConcreteType], list: &[ConcreteType], typeHierarchy: &dyn TypeHierarchy) -> bool {
    let (mut i1, mut i2) = (0, 0);
    while i1 < sublist.len() && i2 < list.len() {
        let (t1, t2) = (&sublist[i1], &list[i2]);
        if t1.cls.id > t2.cls.id {
            i2 += 1;
        } else if t1.cls.id == t2.cls.id && t2.unionSameClass(t1, typeHierarchy) == *t2 {
            i1 += 1;
            i2 += 1;
        } else {
            return false;
        }
    }
    i1 == sublist.len()
}

/// `TFClass.concreteType`, as a [ConcreteType].
pub fn rawConcreteType(cls: &Rc<TFClass>) -> ConcreteType {
    match &cls.recordShape {
        Some(shape) => {
            let n = shape.numFields();
            ConcreteType {
                cls: cls.clone(),
                kind: ConcreteKind::Record {
                    fieldTypes: vec![nullableAnyType(); n],
                    depth: if n == 0 { 0 } else { maxRecordDepth },
                    isRaw: true,
                },
            }
        }
        None => ConcreteType {
            cls: cls.clone(),
            kind: ConcreteKind::Class { numImmediateTypeArgs: 0, typeArgs: None, attributes: None },
        },
    }
}

/// `TFClass.concreteType`.
pub fn concreteType(cls: &Rc<TFClass>) -> Type {
    rawConcreteType(cls).toType()
}

/// `ClassConcreteType._(cls, typeArgs, attributes)` with type arguments;
/// [numTypeParameters] is `cls.classNode.typeParameters.length`.
pub fn classConcreteTypeWith(
    cls: &Rc<TFClass>,
    numTypeParameters: usize,
    typeArgs: Vec<Type>,
    attributes: Option<Rc<TypeAttributes>>,
) -> Type {
    Type::Concrete(Rc::new(ConcreteType {
        cls: cls.clone(),
        kind: ConcreteKind::Class { numImmediateTypeArgs: numTypeParameters, typeArgs: Some(typeArgs), attributes },
    }))
}

/// `ClassConcreteType(cls, typeArgs)` (and `ClassConcreteType._` with
/// attributes).
pub fn classConcreteType(cls: &Rc<TFClass>, typeArgs: Vec<Type>, attributes: Option<Rc<TypeAttributes>>, env: &Env) -> Type {
    let n = env.index.class(cls.classNode).map(|c| c.typeParameters.len()).unwrap_or(0);
    classConcreteTypeWith(cls, n, typeArgs, attributes)
}

/// `TFClass.constantConcreteType` without type arguments, whose type (and
/// attributes) the class interns.
pub fn internedConstantConcreteType(cls: &Rc<TFClass>, constant: TFConstant, closure: Option<Closure>) -> Type {
    let attributes = cls.internAttributes(TypeAttributes { constant: Some(constant), closure });
    Type::Concrete(Rc::new(ConcreteType {
        cls: cls.clone(),
        kind: ConcreteKind::Class { numImmediateTypeArgs: 0, typeArgs: None, attributes: Some(attributes) },
    }))
}

/// `TFClass.constantConcreteType`.
pub fn constantConcreteType(cls: &Rc<TFClass>, constant: TFConstant, typeArgs: Option<Vec<Type>>, env: &Env) -> Type {
    let closure = closureForConstant(&constant, env);
    match typeArgs {
        Some(args) => {
            let attributes = Rc::new(TypeAttributes { constant: Some(constant), closure });
            classConcreteType(cls, args, Some(attributes), env)
        }
        None => internedConstantConcreteType(cls, constant, closure),
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
    let attributes = cls.internAttributes(TypeAttributes { constant: None, closure: Some(Closure { member, function }) });
    Type::Concrete(Rc::new(ConcreteType {
        cls: cls.clone(),
        kind: ConcreteKind::Class { numImmediateTypeArgs: 0, typeArgs: None, attributes: Some(attributes) },
    }))
}

/// `TFClass._recordDepth`.
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

/// `TFClass.recordConcreteType`, as a [ConcreteType].
fn recordConcreteTypeOf(cls: &Rc<TFClass>, fieldTypes: Vec<Type>) -> ConcreteType {
    let mut allNullableAny = true;
    let mut maxFieldDepth = 0;
    for f in &fieldTypes {
        if *f != nullableAnyType() {
            allNullableAny = false;
            maxFieldDepth = maxFieldDepth.max(recordDepth(f));
        }
    }
    if allNullableAny || maxFieldDepth >= maxRecordDepth {
        return rawConcreteType(cls);
    }
    ConcreteType { cls: cls.clone(), kind: ConcreteKind::Record { fieldTypes, depth: maxFieldDepth + 1, isRaw: false } }
}

/// `TFClass.recordConcreteType`.
pub fn recordConcreteType(cls: &Rc<TFClass>, fieldTypes: Vec<Type>) -> Type {
    recordConcreteTypeOf(cls, fieldTypes).toType()
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
