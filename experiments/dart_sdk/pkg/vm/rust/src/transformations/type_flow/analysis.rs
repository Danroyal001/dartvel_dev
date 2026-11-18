// Port of lib/transformations/type_flow/analysis.dart, so far the part the
// summary collector uses: `GenericInterfacesInfoImpl` and the
// `EntryPointsListener` interface. The analysis itself is not ported yet.
use std::cell::RefCell;
use std::collections::HashMap;

use kernel::ast::*;
use kernel::class_hierarchy::computeNullabilityFromBound;

use super::Env;
use super::calls::Selector;
use super::types::{Closure, MemberId, RecordShape, Type};

/// `EntryPointsListener`.
pub trait EntryPointsListener {
    fn addRawCall(&self, selector: Selector);
    fn addFieldUsedInConstant(&self, field: &MemberId, instance: &Type, value: &Type);
    /// Returns the class's `ConcreteType`.
    fn addAllocatedClass(&self, c: CnId) -> Type;
    fn addAllocatedRecord(&self, shape: &RecordShape) -> Type;
    fn getRecordPositionalField(&self, shape: &RecordShape, pos: usize) -> MemberId;
    fn getRecordNamedField(&self, shape: &RecordShape, name: &str) -> MemberId;
    fn recordMemberCalledViaThis(&self, target: &MemberId);
    fn recordTearOff(&self, target: CnId);
    fn getClosureCallMethod(&self, closure: &Closure) -> MemberId;
}

/// `GenericInterfacesInfoImpl` (the part the summary collector uses).
pub struct GenericInterfacesInfoImpl<'a> {
    env: &'a Env<'a>,
    supertypeOffsetsCache: RefCell<HashMap<(CnId, CnId), usize>>,
}

/// `findOverlap`: the smallest `i` such that `list.skip(i)` is a prefix of
/// [sublist].
fn findOverlap(list: &[DartType], sublist: &[DartType]) -> usize {
    for i in 0..list.len() {
        let rest = &list[i..];
        if rest.len() <= sublist.len() && rest.iter().zip(sublist.iter()).all(|(a, b)| a == b) {
            return i;
        }
    }
    list.len()
}

impl<'a> GenericInterfacesInfoImpl<'a> {
    pub fn new(env: &'a Env<'a>) -> Self {
        GenericInterfacesInfoImpl { env, supertypeOffsetsCache: RefCell::new(HashMap::new()) }
    }

    /// `flattenedTypeArgumentsFor` (upstream never fills its cache of
    /// these, so neither does the port).
    pub fn flattenedTypeArgumentsFor(&self, klass: CnId) -> Vec<DartType> {
        let index = self.env.index;
        let class = index.class(klass).expect("class");
        let mut flattened: Vec<DartType> = class
            .typeParameters
            .iter()
            .map(|p| DartType::TypeParameter { declaredNullability: computeNullabilityFromBound(p, index), parameter: p.id })
            .collect();
        for intf in self.env.hierarchy.genericSupertypesOf(klass) {
            let offset = findOverlap(&flattened, &intf.typeArguments);
            let skip = flattened.len() - offset;
            flattened.extend(intf.typeArguments.iter().skip(skip).cloned());
            self.supertypeOffsetsCache.borrow_mut().insert((klass, intf.className), offset);
        }
        flattened
    }

    /// `genericInterfaceOffsetFor`.
    pub fn genericInterfaceOffsetFor(&self, klass: CnId, iface: CnId) -> usize {
        if klass == iface {
            return 0;
        }
        if let Some(o) = self.supertypeOffsetsCache.borrow().get(&(klass, iface)) {
            return *o;
        }
        self.flattenedTypeArgumentsFor(klass);
        *self.supertypeOffsetsCache.borrow().get(&(klass, iface)).expect("Invalid call to genericInterfaceOffsetFor.")
    }
}
