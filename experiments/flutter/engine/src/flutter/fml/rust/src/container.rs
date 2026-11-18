// Port of flutter/fml/container.h.
//
// `erase_if(container, predicate)` removes the entries the predicate holds
// for, visiting them in the container's order (key order for a BTreeMap,
// as for std::map). Upstream's predicate takes an iterator; here it takes
// the entry, through which it may also change the value, as through a
// mutable iterator.

use std::collections::{BTreeMap, HashMap};
use std::hash::Hash;

/// A container `erase_if` works on.
pub trait EraseIf {
    type Key;
    type Value;
    fn erase_if(&mut self, predicate: &mut dyn FnMut(&Self::Key, &mut Self::Value) -> bool);
}

impl<K: Ord, V> EraseIf for BTreeMap<K, V> {
    type Key = K;
    type Value = V;
    fn erase_if(&mut self, predicate: &mut dyn FnMut(&K, &mut V) -> bool) {
        self.retain(|k, v| !predicate(k, v));
    }
}

impl<K: Eq + Hash, V> EraseIf for HashMap<K, V> {
    type Key = K;
    type Value = V;
    fn erase_if(&mut self, predicate: &mut dyn FnMut(&K, &mut V) -> bool) {
        self.retain(|k, v| !predicate(k, v));
    }
}

pub fn erase_if<C: EraseIf>(
    container: &mut C,
    mut predicate: impl FnMut(&C::Key, &mut C::Value) -> bool,
) {
    container.erase_if(&mut predicate);
}
