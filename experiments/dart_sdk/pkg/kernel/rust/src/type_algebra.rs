// Port of lib/type_algebra.dart, as far as the type-flow summary collector
// needs it: `Substitution.fromPairs` and `substituteType`, with the
// nullability rules of lib/src/ast/types.dart it relies on (`nullability`,
// `withDeclaredNullability`, `combineNullabilitiesForSubstitution`).
//
// Upstream gives a substituted function type fresh structural parameters;
// here they keep their ids (no type here is compared by parameter identity
// across a substitution).
use std::collections::HashMap;

use crate::ast::*;
use crate::core_types::Nullability;
use crate::reference_index::NodeIndex;

/// `combineNullabilitiesForSubstitution`.
pub fn combineNullabilitiesForSubstitution(inner: u8, outer: u8) -> u8 {
    if inner == Nullability::nullable || outer == Nullability::nullable {
        return Nullability::nullable;
    }
    inner
}

/// `uniteNullabilities`.
pub fn uniteNullabilities(a: u8, b: u8) -> u8 {
    if a == Nullability::nullable || b == Nullability::nullable {
        return Nullability::nullable;
    }
    if a == Nullability::undetermined || b == Nullability::undetermined {
        return Nullability::undetermined;
    }
    Nullability::nonNullable
}

/// `DartType.declaredNullability`.
pub fn declaredNullability(ty: &DartType) -> u8 {
    match ty {
        DartType::Never { nullability } => *nullability,
        DartType::Invalid | DartType::Dynamic | DartType::Void | DartType::Null => Nullability::nullable,
        DartType::Interface { nullability, .. } | DartType::Typedef { nullability, .. } => *nullability,
        DartType::Function(f) => f.nullability,
        DartType::Record(r) => r.nullability,
        DartType::TypeParameter { declaredNullability, .. }
        | DartType::Extension { declaredNullability, .. }
        | DartType::FutureOr { declaredNullability, .. } => *declaredNullability,
        DartType::Intersection { left, .. } => declaredNullability(left),
    }
}

/// `DartType.nullability`.
pub fn nullability(ty: &DartType, index: &NodeIndex) -> u8 {
    match ty {
        DartType::FutureOr { declaredNullability, typeArgument } => {
            uniteNullabilities(nullability(typeArgument, index), *declaredNullability)
        }
        DartType::Intersection { left, right } => {
            // IntersectionType.nullability: the combination of the left
            // side's declared nullability and the bound's.
            let l = declaredNullability(left);
            let r = nullability(right, index);
            if l == Nullability::nullable || r == Nullability::nonNullable {
                if l == Nullability::nullable { Nullability::nullable } else { Nullability::nonNullable }
            } else {
                l
            }
        }
        DartType::Extension { declaredNullability, extensionTypeDeclarationReference, .. } => {
            let inherent = match index.extensionType(*extensionTypeDeclarationReference) {
                Some(declaration) => {
                    if declaration.implements.is_empty() {
                        Nullability::undetermined
                    } else {
                        Nullability::nonNullable
                    }
                }
                None => Nullability::undetermined,
            };
            combineNullabilitiesForSubstitution(inherent, *declaredNullability)
        }
        other => declaredNullability(other),
    }
}

/// `DartType.withDeclaredNullability`.
pub fn withDeclaredNullability(ty: &DartType, n: u8) -> DartType {
    match ty {
        DartType::Invalid | DartType::Dynamic | DartType::Void | DartType::Null => ty.clone(),
        DartType::Never { .. } => DartType::Never { nullability: n },
        DartType::Interface { classReference, typeArguments, .. } => DartType::Interface {
            nullability: n,
            classReference: *classReference,
            typeArguments: typeArguments.clone(),
        },
        DartType::Typedef { typedefReference, typeArguments, .. } => DartType::Typedef {
            nullability: n,
            typedefReference: *typedefReference,
            typeArguments: typeArguments.clone(),
        },
        DartType::Function(f) => {
            let mut f = (**f).clone();
            f.nullability = n;
            DartType::Function(Box::new(f))
        }
        DartType::Record(r) => {
            let mut r = (**r).clone();
            r.nullability = n;
            DartType::Record(Box::new(r))
        }
        DartType::TypeParameter { parameter, .. } => {
            DartType::TypeParameter { declaredNullability: n, parameter: *parameter }
        }
        DartType::Extension { extensionTypeDeclarationReference, typeArguments, extensionTypeErasure, .. } => {
            DartType::Extension {
                declaredNullability: n,
                extensionTypeDeclarationReference: *extensionTypeDeclarationReference,
                typeArguments: typeArguments.clone(),
                extensionTypeErasure: extensionTypeErasure.clone(),
            }
        }
        DartType::FutureOr { typeArgument, .. } => {
            DartType::FutureOr { declaredNullability: n, typeArgument: typeArgument.clone() }
        }
        DartType::Intersection { left, .. } => withDeclaredNullability(left, n),
    }
}

/// `Substitution`.
#[derive(Debug, Clone, Default)]
pub struct Substitution {
    pub map: HashMap<TypeParamId, DartType>,
}

impl Substitution {
    /// `Substitution.fromPairs`.
    pub fn fromPairs(parameters: &[TypeParameter], types: &[DartType]) -> Self {
        assert_eq!(parameters.len(), types.len(), "Substitution.fromPairs");
        Substitution {
            map: parameters.iter().map(|p| p.id).zip(types.iter().cloned()).collect(),
        }
    }

    pub fn isEmpty(&self) -> bool {
        self.map.is_empty()
    }

    /// `substituteType`.
    pub fn substituteType(&self, ty: &DartType, index: &NodeIndex) -> DartType {
        if self.map.is_empty() {
            return ty.clone();
        }
        self.visit(ty, index)
    }

    /// `substituteSupertype`.
    pub fn substituteSupertype(&self, s: &Supertype, index: &NodeIndex) -> Supertype {
        Supertype {
            nullability: s.nullability,
            className: s.className,
            typeArguments: s.typeArguments.iter().map(|t| self.substituteType(t, index)).collect(),
        }
    }

    fn visit(&self, ty: &DartType, index: &NodeIndex) -> DartType {
        let list = |types: &[DartType]| -> Vec<DartType> { types.iter().map(|t| self.visit(t, index)).collect() };
        match ty {
            DartType::TypeParameter { parameter, declaredNullability } => match self.map.get(parameter) {
                Some(DartType::Invalid) => DartType::Invalid,
                Some(replacement) => withDeclaredNullability(
                    replacement,
                    combineNullabilitiesForSubstitution(nullability(replacement, index), *declaredNullability),
                ),
                None => ty.clone(),
            },
            DartType::Interface { nullability, classReference, typeArguments } => DartType::Interface {
                nullability: *nullability,
                classReference: *classReference,
                typeArguments: list(typeArguments),
            },
            DartType::Typedef { nullability, typedefReference, typeArguments } => DartType::Typedef {
                nullability: *nullability,
                typedefReference: *typedefReference,
                typeArguments: list(typeArguments),
            },
            DartType::Function(f) => DartType::Function(Box::new(FunctionType {
                nullability: f.nullability,
                typeParameters: f
                    .typeParameters
                    .iter()
                    .map(|p| TypeParameter {
                        bound: self.visit(&p.bound, index),
                        defaultType: self.visit(&p.defaultType, index),
                        ..p.clone()
                    })
                    .collect(),
                requiredParameterCount: f.requiredParameterCount,
                positionalParameters: list(&f.positionalParameters),
                namedParameters: f
                    .namedParameters
                    .iter()
                    .map(|n| NamedType { name: n.name, r#type: self.visit(&n.r#type, index), isRequired: n.isRequired })
                    .collect(),
                returnType: Box::new(self.visit(&f.returnType, index)),
            })),
            DartType::Record(r) => DartType::Record(Box::new(RecordType {
                nullability: r.nullability,
                positional: list(&r.positional),
                named: r
                    .named
                    .iter()
                    .map(|n| NamedType { name: n.name, r#type: self.visit(&n.r#type, index), isRequired: n.isRequired })
                    .collect(),
            })),
            DartType::FutureOr { declaredNullability, typeArgument } => DartType::FutureOr {
                declaredNullability: *declaredNullability,
                typeArgument: Box::new(self.visit(typeArgument, index)),
            },
            DartType::Extension { declaredNullability, extensionTypeDeclarationReference, typeArguments, extensionTypeErasure } => {
                DartType::Extension {
                    declaredNullability: *declaredNullability,
                    extensionTypeDeclarationReference: *extensionTypeDeclarationReference,
                    typeArguments: list(typeArguments),
                    extensionTypeErasure: Box::new(self.visit(extensionTypeErasure, index)),
                }
            }
            // `visitIntersectionType` substitutes the left side only.
            DartType::Intersection { left, .. } => self.visit(left, index),
            _ => ty.clone(),
        }
    }
}
