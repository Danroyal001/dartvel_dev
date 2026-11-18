// Port of lib/type_environment.dart (`TypeEnvironment`, `StaticTypeContext`)
// with the `getStaticTypeInternal` methods of lib/src/ast/expressions.dart
// and `computeFunctionType`/`getterType` of lib/src/ast/{functions,members}.dart
// they call, as far as the type-flow summary collector needs them.
//
// The subtype test follows lib/src/types.dart's rules for the types the
// summary collector asks about (interface, type parameter, FutureOr, Null,
// Never, top types and functions); record and extension types are compared
// by their erasure and shape.
use std::collections::HashMap;

use crate::ast::*;
use crate::class_hierarchy::{ClassHierarchy, computeNullabilityFromBound};
use crate::core_types::{CoreTypes, Nullability};
use crate::reference_index::{MemberNode, NodeIndex};
use crate::type_algebra::{Substitution, nullability, withDeclaredNullability};
use crate::visitor::{Node, visitDescendants};

pub struct TypeEnvironment<'a> {
    pub index: &'a NodeIndex<'a>,
    pub coreTypes: &'a CoreTypes<'a>,
    pub hierarchy: &'a ClassHierarchy<'a>,
}

impl<'a> TypeEnvironment<'a> {
    pub fn new(coreTypes: &'a CoreTypes<'a>, hierarchy: &'a ClassHierarchy<'a>) -> Self {
        TypeEnvironment { index: coreTypes.index, coreTypes, hierarchy }
    }

    fn isTop(&self, t: &DartType) -> bool {
        match t {
            DartType::Dynamic | DartType::Void | DartType::Invalid => true,
            DartType::Interface { classReference, nullability, .. } => {
                *classReference == self.coreTypes.objectClass && *nullability == Nullability::nullable
            }
            DartType::FutureOr { typeArgument, .. } => {
                self.isTop(typeArgument)
                    || (matches!(**typeArgument, DartType::Interface { classReference, .. } if classReference == self.coreTypes.objectClass)
                        && nullability(t, self.index) == Nullability::nullable)
            }
            _ => false,
        }
    }

    /// `isSubtypeOf` (with `SubtypeCheckMode.withNullabilities`).
    pub fn isSubtypeOf(&self, s: &DartType, t: &DartType) -> bool {
        if s == t {
            return true;
        }
        if self.isTop(t) {
            return true;
        }
        if let DartType::Typedef { .. } = t {
            return true; // Typedef types are unaliased before this point.
        }
        // Left side cases.
        match s {
            DartType::Never { nullability: n } if *n == Nullability::nonNullable => return true,
            DartType::Dynamic | DartType::Void | DartType::Invalid => return false,
            _ => {}
        }
        // Object (non-nullable) on the right.
        if let DartType::Interface { classReference, nullability: n, .. } = t {
            if *classReference == self.coreTypes.objectClass && *n == Nullability::nonNullable {
                return nullability(s, self.index) == Nullability::nonNullable
                    || match s {
                        DartType::TypeParameter { parameter, .. } => {
                            nullability(s, self.index) != Nullability::nullable
                                && self.boundOf(*parameter).map(|b| self.isSubtypeOf(&b, t)).unwrap_or(false)
                        }
                        _ => false,
                    };
            }
        }
        let tNullable = nullability(t, self.index) == Nullability::nullable;
        // Null on the left.
        if matches!(s, DartType::Null) || matches!(s, DartType::Never { nullability: n } if *n == Nullability::nullable) {
            return match t {
                DartType::FutureOr { typeArgument, .. } => tNullable || self.isSubtypeOf(s, typeArgument),
                DartType::TypeParameter { parameter, .. } => {
                    tNullable || self.boundOf(*parameter).map(|b| self.isSubtypeOf(s, &b)).unwrap_or(false) && false
                }
                _ => tNullable,
            };
        }
        // A nullable left side needs a nullable right side.
        let sNullability = nullability(s, self.index);
        if sNullability == Nullability::nullable {
            if tNullable {
                return self.isSubtypeOf(&withDeclaredNullability(s, Nullability::nonNullable), &withDeclaredNullability(t, Nullability::nonNullable));
            }
            if let DartType::FutureOr { typeArgument, .. } = t {
                return self.isSubtypeOf(s, typeArgument);
            }
            return false;
        }
        let tNonNull = if tNullable { withDeclaredNullability(t, Nullability::nonNullable) } else { t.clone() };
        match (s, &tNonNull) {
            (DartType::TypeParameter { parameter: a, .. }, DartType::TypeParameter { parameter: b, .. }) if a == b => true,
            (DartType::TypeParameter { parameter, .. }, _) => match self.boundOf(*parameter) {
                Some(b) => self.isSubtypeOf(&b, &tNonNull),
                None => false,
            },
            (DartType::Intersection { left, right }, _) => self.isSubtypeOf(left, &tNonNull) || self.isSubtypeOf(right, &tNonNull),
            (_, DartType::FutureOr { typeArgument, .. }) => {
                if let DartType::FutureOr { typeArgument: sArg, .. } = s {
                    return self.isSubtypeOf(sArg, typeArgument);
                }
                let future = DartType::Interface {
                    nullability: Nullability::nonNullable,
                    classReference: self.coreTypes.futureClass,
                    typeArguments: vec![(**typeArgument).clone()],
                };
                self.isSubtypeOf(s, typeArgument) || self.isSubtypeOf(s, &future)
            }
            (DartType::FutureOr { typeArgument, .. }, _) => {
                let future = DartType::Interface {
                    nullability: Nullability::nonNullable,
                    classReference: self.coreTypes.futureClass,
                    typeArguments: vec![(**typeArgument).clone()],
                };
                self.isSubtypeOf(&future, &tNonNull) && self.isSubtypeOf(typeArgument, &tNonNull)
            }
            (DartType::Interface { classReference: sc, typeArguments: sa, .. }, DartType::Interface { classReference: tc, typeArguments: ta, .. }) => {
                match self.hierarchy.getInterfaceTypeArgumentsAsInstanceOfClass(*sc, sa, *tc) {
                    Some(args) => args.iter().zip(ta.iter()).all(|(a, b)| self.isSubtypeOf(a, b)),
                    None => false,
                }
            }
            (DartType::Function(_), DartType::Interface { classReference, .. }) => *classReference == self.coreTypes.functionClass,
            (DartType::Record(_), DartType::Interface { classReference, .. }) => *classReference == self.coreTypes.recordClass,
            (DartType::Extension { extensionTypeErasure, .. }, _) => self.isSubtypeOf(extensionTypeErasure, &tNonNull),
            (DartType::Function(sf), DartType::Function(tf)) => {
                sf.positionalParameters.len() >= tf.positionalParameters.len()
                    && sf.requiredParameterCount <= tf.requiredParameterCount
                    && self.isSubtypeOf(&sf.returnType, &tf.returnType)
                    && tf.positionalParameters.iter().zip(sf.positionalParameters.iter()).all(|(a, b)| self.isSubtypeOf(a, b))
            }
            (DartType::Record(sr), DartType::Record(tr)) => {
                sr.positional.len() == tr.positional.len()
                    && sr.named.len() == tr.named.len()
                    && sr.positional.iter().zip(tr.positional.iter()).all(|(a, b)| self.isSubtypeOf(a, b))
                    && sr.named.iter().zip(tr.named.iter()).all(|(a, b)| a.name == b.name && self.isSubtypeOf(&a.r#type, &b.r#type))
            }
            _ => false,
        }
    }

    fn boundOf(&self, parameter: TypeParamId) -> Option<DartType> {
        self.index.typeParameter(parameter).map(|p| p.bound.clone())
    }

    /// `flatten`.
    pub fn flatten(&self, t: &DartType) -> DartType {
        match t {
            DartType::FutureOr { typeArgument, .. } => (**typeArgument).clone(),
            DartType::Interface { classReference, typeArguments, .. } => {
                if let Some(args) = self.hierarchy.getInterfaceTypeArgumentsAsInstanceOfClass(*classReference, typeArguments, self.coreTypes.futureClass) {
                    let inner = args[0].clone();
                    if nullability(t, self.index) == Nullability::nullable {
                        return withDeclaredNullability(&inner, Nullability::nullable);
                    }
                    return inner;
                }
                t.clone()
            }
            _ => t.clone(),
        }
    }

    pub fn listType(&self, typeArgument: &DartType) -> DartType {
        DartType::Interface { nullability: Nullability::nonNullable, classReference: self.coreTypes.listClass, typeArguments: vec![typeArgument.clone()] }
    }
    pub fn setType(&self, typeArgument: &DartType) -> DartType {
        DartType::Interface { nullability: Nullability::nonNullable, classReference: self.coreTypes.setClass, typeArguments: vec![typeArgument.clone()] }
    }
    pub fn mapType(&self, key: &DartType, value: &DartType) -> DartType {
        DartType::Interface { nullability: Nullability::nonNullable, classReference: self.coreTypes.mapClass, typeArguments: vec![key.clone(), value.clone()] }
    }
}

/// `FunctionNode.computeFunctionType`.
pub fn computeFunctionType(function: &FunctionNode, n: u8, index: &NodeIndex) -> DartType {
    let mut named: Vec<NamedType> = function
        .namedParameters
        .iter()
        .map(|p| NamedType { name: p.name, r#type: p.r#type.clone(), isRequired: p.flags & VARIABLE_REQUIRED != 0 })
        .collect();
    named.sort_by(|a, b| index.component.strings.get(a.name).cmp(index.component.strings.get(b.name)));
    DartType::Function(Box::new(FunctionType {
        nullability: n,
        typeParameters: function.typeParameters.clone(),
        requiredParameterCount: function.requiredParameterCount,
        positionalParameters: function.positionalParameters.iter().map(|p| p.r#type.clone()).collect(),
        namedParameters: named,
        returnType: Box::new(function.returnType.clone()),
    }))
}

/// `Variable.FlagRequired`.
pub const VARIABLE_REQUIRED: u32 = 1 << 6;

/// `Member.getterType`.
pub fn getterType(member: MemberNode, index: &NodeIndex) -> DartType {
    match member {
        MemberNode::Field(f) => f.r#type.clone(),
        MemberNode::Procedure(p) if p.kind == ProcedureKind::Getter => p.function.returnType.clone(),
        MemberNode::Procedure(p) => computeFunctionType(&p.function, Nullability::nonNullable, index),
        MemberNode::Constructor(c) => computeFunctionType(&c.function, Nullability::nonNullable, index),
    }
}

/// `StaticTypeContext`: the member whose expressions are typed, with its
/// `this` type and its variables.
pub struct StaticTypeContext<'a> {
    pub env: &'a TypeEnvironment<'a>,
    pub thisType: Option<DartType>,
    pub variables: HashMap<VarId, &'a Variable>,
}

impl<'a> StaticTypeContext<'a> {
    pub fn new(member: MemberNode<'a>, env: &'a TypeEnvironment<'a>) -> Self {
        let index = env.index;
        let thisType = index.enclosingClass(member.reference()).map(|c| {
            let class = index.class(c).unwrap();
            DartType::Interface {
                nullability: Nullability::nonNullable,
                classReference: c,
                typeArguments: class
                    .typeParameters
                    .iter()
                    .map(|p| DartType::TypeParameter { declaredNullability: computeNullabilityFromBound(p, index), parameter: p.id })
                    .collect(),
            }
        });
        let mut variables = HashMap::new();
        let mut add = |node: Node<'a>| {
            if let Node::Variable(v) = node {
                variables.insert(v.id, v);
            }
        };
        match member {
            MemberNode::Field(f) => {
                if let Some(i) = &f.initializer {
                    add(Node::Expression(i));
                    visitDescendants(Node::Expression(i), &mut add);
                }
            }
            MemberNode::Procedure(p) => visitDescendants(Node::FunctionNode(&p.function), &mut add),
            MemberNode::Constructor(c) => {
                for i in &c.initializers {
                    visitDescendants(Node::Initializer(i), &mut add);
                }
                visitDescendants(Node::FunctionNode(&c.function), &mut add);
            }
        }
        StaticTypeContext { env, thisType, variables }
    }

    fn core(&self) -> &CoreTypes<'a> {
        self.env.coreTypes
    }

    fn bool_(&self) -> DartType {
        self.core().nonNullableRawType(self.core().boolClass)
    }

    pub fn variable(&self, id: VarId) -> &'a Variable {
        self.variables.get(&id).copied().expect("variable declared in the member")
    }

    /// `Expression.getStaticType`.
    pub fn getStaticType(&self, e: &Expression) -> DartType {
        use Expression::*;
        let index = self.env.index;
        let core = self.core();
        match e {
            Invalid { .. } | Rethrow { .. } | Throw { .. } => DartType::Never { nullability: Nullability::nonNullable },
            VariableGet { variable, promotedType, .. } => match promotedType {
                Some(t) => (**t).clone(),
                None => self.variable(*variable).r#type.clone(),
            },
            VariableSet { value, .. } | InstanceSet { value, .. } | DynamicSet { value, .. } | StaticSet { value, .. } | SuperPropertySet { value, .. } => {
                self.getStaticType(value)
            }
            RecordIndexGet { receiverType, index: i, .. } => match &**receiverType {
                DartType::Record(r) => r.positional[*i as usize].clone(),
                _ => DartType::Dynamic,
            },
            RecordNameGet { receiverType, name, .. } => match &**receiverType {
                DartType::Record(r) => r.named.iter().find(|n| n.name == *name).map(|n| n.r#type.clone()).unwrap_or(DartType::Dynamic),
                _ => DartType::Dynamic,
            },
            DynamicGet { kind, .. } | DynamicInvocation { kind, .. } => match kind {
                0 => DartType::Dynamic,
                1 => DartType::Never { nullability: Nullability::nonNullable },
                _ => DartType::Invalid,
            },
            InstanceGet { resultType, .. } | InstanceTearOff { resultType, .. } | InstanceInvocation { resultType, .. } => (**resultType).clone(),
            FunctionTearOff { receiver, .. } => self.getStaticType(receiver),
            SuperPropertyGet { interfaceTarget, .. } => {
                let target = index.member(interfaceTarget.target).expect("super target");
                let declaringClass = index.enclosingClass(target.reference()).unwrap();
                let class = index.class(declaringClass).unwrap();
                let getter = getterType(target, index);
                if class.typeParameters.is_empty() {
                    return getter;
                }
                let args = self.typeArgumentsOfThisAsInstanceOf(declaringClass);
                Substitution::fromPairs(&class.typeParameters, &args).substituteType(&getter, index)
            }
            StaticGet { targetReference, .. } | StaticTearOff { targetReference, .. } => {
                getterType(index.member(*targetReference).expect("static target"), index)
            }
            InstanceGetterInvocation { functionType, .. } | FunctionInvocation { functionType, .. } => match &**functionType {
                DartType::Function(f) => (*f.returnType).clone(),
                _ => DartType::Dynamic,
            },
            LocalFunctionInvocation { functionType, .. } | EqualsCall { functionType, .. } => match &**functionType {
                DartType::Function(f) => (*f.returnType).clone(),
                _ => DartType::Dynamic,
            },
            EqualsNull { .. } | Not { .. } | LogicalExpression { .. } | IsExpression { .. } | BoolLiteral { .. } => self.bool_(),
            SuperMethodInvocation { interfaceTarget, arguments, .. } => {
                let target = index.member(interfaceTarget.target).expect("super target");
                let function = target.function().unwrap();
                let superclass = index.enclosingClass(target.reference()).unwrap();
                let class = index.class(superclass).unwrap();
                let args = self.typeArgumentsOfThisAsInstanceOf(superclass);
                let returnType = Substitution::fromPairs(&class.typeParameters, &args).substituteType(&function.returnType, index);
                Substitution::fromPairs(&function.typeParameters, &arguments.types).substituteType(&returnType, index)
            }
            StaticInvocation { targetReference, arguments, .. } => {
                let target = index.member(*targetReference).expect("static target");
                let function = target.function().unwrap();
                Substitution::fromPairs(&function.typeParameters, &arguments.types).substituteType(&function.returnType, index)
            }
            ConstructorInvocation { targetReference, arguments, .. } => {
                let class = index.enclosingClass(*targetReference).unwrap();
                if arguments.types.is_empty() {
                    core.nonNullableRawType(class)
                } else {
                    DartType::Interface { nullability: Nullability::nonNullable, classReference: class, typeArguments: arguments.types.clone() }
                }
            }
            RedirectingFactoryInvocation { expression, .. } | FileUriExpression { expression, .. } => self.getStaticType(expression),
            Instantiation { expression, typeArguments, .. } => match self.getStaticType(expression) {
                DartType::Function(f) => {
                    let substitution = Substitution::fromPairs(&f.typeParameters, typeArguments);
                    let instantiated = FunctionType { typeParameters: vec![], ..(*f).clone() };
                    substitution.substituteType(&DartType::Function(Box::new(instantiated)), index)
                }
                other => other,
            },
            ConditionalExpression { staticType, .. } | SwitchExpression { staticType, .. } => {
                staticType.as_ref().map(|t| (**t).clone()).unwrap_or(DartType::Dynamic)
            }
            StringConcatenation { .. } | StringLiteral { .. } => core.nonNullableRawType(core.stringClass),
            ListConcatenation { typeArgument, .. } | ListLiteral { typeArgument, .. } => self.env.listType(typeArgument),
            SetConcatenation { typeArgument, .. } | SetLiteral { typeArgument, .. } => self.env.setType(typeArgument),
            MapConcatenation { keyType, valueType, .. } | MapLiteral { keyType, valueType, .. } => self.env.mapType(keyType, valueType),
            InstanceCreation { classReference, typeArguments, .. } => {
                if typeArguments.is_empty() {
                    core.nonNullableRawType(*classReference)
                } else {
                    DartType::Interface { nullability: Nullability::nonNullable, classReference: *classReference, typeArguments: typeArguments.clone() }
                }
            }
            AsExpression { r#type, .. } | ConstantExpression { r#type, .. } | FileUriConstantExpression { r#type, .. } => r#type.clone(),
            NullCheck { operand, .. } => match self.getStaticType(operand) {
                DartType::Null => DartType::Never { nullability: Nullability::nonNullable },
                t => withDeclaredNullability(&t, Nullability::nonNullable),
            },
            IntLiteral { .. } => core.nonNullableRawType(core.intClass),
            DoubleLiteral { .. } => core.nonNullableRawType(core.doubleClass),
            NullLiteral { .. } => DartType::Null,
            SymbolLiteral { .. } => core.nonNullableRawType(core.symbolClass),
            TypeLiteral { .. } => core.nonNullableRawType(core.typeClass),
            ThisExpression { .. } => self.thisType.clone().expect("this type"),
            RecordLiteral { recordType, .. } => (**recordType).clone(),
            AwaitExpression { operand, .. } => self.env.flatten(&self.getStaticType(operand)),
            FunctionExpression { function, .. } => computeFunctionType(function, Nullability::nonNullable, index),
            Let { body, .. } => self.getStaticType(body),
            BlockExpression { value, .. } => self.getStaticType(value),
            LoadLibrary { .. } => DartType::Interface {
                nullability: Nullability::nonNullable,
                classReference: core.futureClass,
                typeArguments: vec![DartType::Dynamic],
            },
            CheckLibraryIsLoaded { .. } => core.nonNullableRawType(core.objectClass),
            ConstructorTearOff { targetReference, .. } | RedirectingFactoryTearOff { targetReference, .. } => {
                let target = index.member(*targetReference).unwrap();
                computeFunctionType(target.function().unwrap(), Nullability::nonNullable, index)
            }
            TypedefTearOff { .. } | PatternAssignment { .. } => panic!("getStaticType: not ported for {e:?}"),
        }
    }

    fn typeArgumentsOfThisAsInstanceOf(&self, superclass: CnId) -> Vec<DartType> {
        match self.thisType.as_ref().expect("this type") {
            DartType::Interface { classReference, typeArguments, .. } => self
                .env
                .hierarchy
                .getInterfaceTypeArgumentsAsInstanceOfClass(*classReference, typeArguments, superclass)
                .expect("this is a subtype of the super class"),
            _ => unreachable!(),
        }
    }
}

/// `Constant.getType`.
pub fn constantType(constant: &Constant, ctx: &StaticTypeContext) -> DartType {
    let core = ctx.env.coreTypes;
    let index = ctx.env.index;
    match constant {
        Constant::Null => DartType::Null,
        Constant::Bool(_) => core.nonNullableRawType(core.boolClass),
        Constant::Int(_) => core.nonNullableRawType(core.intClass),
        Constant::Double(_) => core.nonNullableRawType(core.doubleClass),
        Constant::String(_) => core.nonNullableRawType(core.stringClass),
        Constant::Symbol { .. } => core.nonNullableRawType(core.symbolClass),
        Constant::Map { keyType, valueType, .. } => ctx.env.mapType(keyType, valueType),
        Constant::List { typeArgument, .. } => ctx.env.listType(typeArgument),
        Constant::Set { typeArgument, .. } => ctx.env.setType(typeArgument),
        Constant::Record { recordType, .. } => recordType.clone(),
        Constant::Instance { classReference, typeArguments, .. } => DartType::Interface {
            nullability: Nullability::nonNullable,
            classReference: *classReference,
            typeArguments: typeArguments.clone(),
        },
        Constant::Instantiation { tearOffConstant, types } => {
            match constantType(&index.component.constants[*tearOffConstant as usize], ctx) {
                DartType::Function(f) => {
                    let substitution = Substitution::fromPairs(&f.typeParameters, types);
                    let instantiated = FunctionType { typeParameters: vec![], ..(*f).clone() };
                    substitution.substituteType(&DartType::Function(Box::new(instantiated)), index)
                }
                other => other,
            }
        }
        Constant::StaticTearOff { targetReference } | Constant::ConstructorTearOff { targetReference } | Constant::RedirectingFactoryTearOff { targetReference } => {
            computeFunctionType(index.member(*targetReference).unwrap().function().unwrap(), Nullability::nonNullable, index)
        }
        Constant::TypeLiteral { .. } => core.nonNullableRawType(core.typeClass),
        Constant::Unevaluated { .. } | Constant::TypedefTearOff { .. } => panic!("Constant.getType: not ported"),
    }
}
