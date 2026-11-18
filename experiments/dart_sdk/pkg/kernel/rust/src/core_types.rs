// Port of lib/core_types.dart (with the lookups of lib/library_index.dart it
// uses): the classes and members of the core libraries that analyses refer
// to by name. Ported as far as the type-flow summary collector needs.
use crate::ast::*;
use crate::reference_index::NodeIndex;

pub mod Nullability {
    pub const undetermined: u8 = 0;
    pub const nullable: u8 = 1;
    pub const nonNullable: u8 = 2;
}

/// What [CoreTypes::newLenient] gives for a class or member the component
/// does not have.
pub const MISSING: CnId = CnId::MAX;

pub struct CoreTypes<'a> {
    pub index: &'a NodeIndex<'a>,
    pub objectClass: CnId,
    pub boolClass: CnId,
    pub intClass: CnId,
    pub numClass: CnId,
    pub doubleClass: CnId,
    pub stringClass: CnId,
    pub symbolClass: CnId,
    pub typeClass: CnId,
    pub functionClass: CnId,
    pub recordClass: CnId,
    pub futureClass: CnId,
    pub futureImplClass: CnId,
    pub deprecatedFutureOrClass: CnId,
    pub deprecatedNullClass: CnId,
    pub listClass: CnId,
    pub setClass: CnId,
    pub mapClass: CnId,
    pub iterableClass: CnId,
    pub objectEquals: CnId,
    pub identicalProcedure: CnId,
}

impl<'a> CoreTypes<'a> {
    pub fn new(index: &'a NodeIndex<'a>) -> Self {
        Self::build(index, false)
    }

    /// Upstream looks each class and member up on first use, so a
    /// component without some of them (`createMockSdkComponent`) still has
    /// core types; here the missing ones are [MISSING], which no lookup
    /// finds.
    pub fn newLenient(index: &'a NodeIndex<'a>) -> Self {
        Self::build(index, true)
    }

    fn build(index: &'a NodeIndex<'a>, lenient: bool) -> Self {
        let class = |uri: &str, name: &str| match getClass(index, uri, name) {
            Some(c) => c,
            None if lenient => MISSING,
            None => panic!("no class {uri}::{name}"),
        };
        let member = |found: Option<CnId>, what: &str| match found {
            Some(m) => m,
            None if lenient => MISSING,
            None => panic!("no member {what}"),
        };
        CoreTypes {
            index,
            objectClass: class("dart:core", "Object"),
            boolClass: class("dart:core", "bool"),
            intClass: class("dart:core", "int"),
            numClass: class("dart:core", "num"),
            doubleClass: class("dart:core", "double"),
            stringClass: class("dart:core", "String"),
            symbolClass: class("dart:core", "Symbol"),
            typeClass: class("dart:core", "Type"),
            functionClass: class("dart:core", "Function"),
            recordClass: class("dart:core", "Record"),
            futureClass: class("dart:async", "Future"),
            futureImplClass: class("dart:async", "_Future"),
            deprecatedFutureOrClass: class("dart:async", "FutureOr"),
            deprecatedNullClass: class("dart:core", "Null"),
            listClass: class("dart:core", "List"),
            setClass: class("dart:core", "Set"),
            mapClass: class("dart:core", "Map"),
            iterableClass: class("dart:core", "Iterable"),
            objectEquals: member(getMember(index, "dart:core", Some("Object"), "=="), "Object.=="),
            identicalProcedure: member(getMember(index, "dart:core", None, "identical"), "identical"),
        }
    }

    /// `rawType` / `nonNullableRawType` / `nullableRawType`: the class with
    /// `dynamic` for each type parameter.
    pub fn rawType(&self, klass: CnId, nullability: u8) -> DartType {
        let n = self.index.class(klass).map(|c| c.typeParameters.len()).unwrap_or(0);
        DartType::Interface { nullability, classReference: klass, typeArguments: vec![DartType::Dynamic; n] }
    }

    pub fn nonNullableRawType(&self, klass: CnId) -> DartType {
        self.rawType(klass, Nullability::nonNullable)
    }

    pub fn nullableRawType(&self, klass: CnId) -> DartType {
        self.rawType(klass, Nullability::nullable)
    }

    pub fn boolNonNullableRawType(&self) -> DartType {
        self.nonNullableRawType(self.boolClass)
    }

    pub fn intNonNullableRawType(&self) -> DartType {
        self.nonNullableRawType(self.intClass)
    }

    /// `bottomInterfaceType`.
    pub fn bottomInterfaceType(&self, klass: CnId, nullability: u8) -> DartType {
        let n = self.index.class(klass).map(|c| c.typeParameters.len()).unwrap_or(0);
        DartType::Interface {
            nullability,
            classReference: klass,
            typeArguments: vec![DartType::Never { nullability: Nullability::nonNullable }; n],
        }
    }
}

/// `LibraryIndex.getClass` (null when absent: `tryGetClass`).
pub fn getClass(index: &NodeIndex, uri: &str, name: &str) -> Option<CnId> {
    let library = index.component.libraries.iter().find(|l| index.importUri(l) == uri)?;
    library.classes.iter().find(|c| index.string(c.name) == name).map(|c| c.reference)
}

/// `LibraryIndex.getProcedure`/`getTopLevelProcedure`/`getMember`: a member
/// of a class ([className]) or of the library itself, by name.
pub fn getMember(index: &NodeIndex, uri: &str, className: Option<&str>, name: &str) -> Option<CnId> {
    let library = index.component.libraries.iter().find(|l| index.importUri(l) == uri)?;
    let (fields, procedures, constructors): (&[Field], &[Procedure], &[Constructor]) = match className {
        Some(c) => {
            let class = library.classes.iter().find(|k| index.string(k.name) == c)?;
            (&class.fields, &class.procedures, &class.constructors)
        }
        None => (&library.fields, &library.procedures, &[]),
    };
    if let Some(p) = procedures.iter().find(|p| index.string(p.name.text) == name) {
        return Some(p.reference);
    }
    if let Some(f) = fields.iter().find(|f| index.string(f.name.text) == name) {
        return Some(f.fieldReference);
    }
    constructors.iter().find(|k| index.string(k.name.text) == name).map(|k| k.reference)
}
