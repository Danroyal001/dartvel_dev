// Port of lib/modular/target/vm.dart, so far the classes `VmTarget` names
// for the type-flow analysis (`concrete*Class`, the record class).
use std::cell::RefCell;
use std::collections::HashMap;

use kernel::ast::CnId;
use kernel::core_types::getClass;
use kernel::reference_index::NodeIndex;

pub struct VmTarget<'a> {
    index: &'a NodeIndex<'a>,
    classes: RefCell<HashMap<(&'static str, &'static str), CnId>>,
}

impl<'a> VmTarget<'a> {
    pub fn new(index: &'a NodeIndex<'a>) -> Self {
        VmTarget { index, classes: RefCell::new(HashMap::new()) }
    }

    fn class(&self, uri: &'static str, name: &'static str) -> CnId {
        if let Some(c) = self.classes.borrow().get(&(uri, name)) {
            return *c;
        }
        let c = getClass(self.index, uri, name).unwrap_or_else(|| panic!("no class {uri}::{name}"));
        self.classes.borrow_mut().insert((uri, name), c);
        c
    }

    pub fn concreteListLiteralClass(&self) -> Option<CnId> {
        Some(self.class("dart:core", "_GrowableList"))
    }
    pub fn concreteConstListLiteralClass(&self) -> Option<CnId> {
        Some(self.class("dart:core", "_ImmutableList"))
    }
    pub fn concreteMapLiteralClass(&self) -> Option<CnId> {
        Some(self.class("dart:_compact_hash", "_Map"))
    }
    pub fn concreteConstMapLiteralClass(&self) -> Option<CnId> {
        Some(self.class("dart:_compact_hash", "_ConstMap"))
    }
    pub fn concreteSetLiteralClass(&self) -> Option<CnId> {
        Some(self.class("dart:_compact_hash", "_Set"))
    }
    pub fn concreteConstSetLiteralClass(&self) -> Option<CnId> {
        Some(self.class("dart:_compact_hash", "_ConstSet"))
    }
    pub fn concreteConstSymbolLiteralClass(&self) -> Option<CnId> {
        Some(self.class("dart:_internal", "Symbol"))
    }
    pub fn getRecordImplementationClass(&self) -> CnId {
        self.class("dart:core", "_Record")
    }
    pub fn concreteIntLiteralClass(&self, value: i64) -> Option<CnId> {
        const smiMin32: i64 = -(1 << 30);
        const smiMax32: i64 = (1 << 30) - 1;
        if (smiMin32..=smiMax32).contains(&value) { Some(self.class("dart:core", "_Smi")) } else { None }
    }
    pub fn concreteDoubleLiteralClass(&self) -> Option<CnId> {
        Some(self.class("dart:core", "_Double"))
    }
    pub fn concreteStringLiteralClass(&self, value: &str) -> Option<CnId> {
        if value.encode_utf16().any(|u| u > 0xff) {
            Some(self.class("dart:core", "_TwoByteString"))
        } else {
            Some(self.class("dart:core", "_OneByteString"))
        }
    }
    pub fn concreteClosureClass(&self) -> Option<CnId> {
        Some(self.class("dart:core", "_Closure"))
    }
    pub fn concreteAsyncResultClass(&self) -> Option<CnId> {
        Some(self.class("dart:async", "_Future"))
    }
    pub fn concreteSyncStarResultClass(&self) -> Option<CnId> {
        Some(self.class("dart:async", "_SyncStarIterable"))
    }
}
