// Port of lib/canonical_name.dart: the tree of names that references
// serialize as.
//
// Upstream's `CanonicalName` objects hold a map of children in insertion
// order; here every name is an entry of one arena, the root is entry 0, and
// each entry keeps its children in insertion order (the order the binary
// writer's link table walks them in).

use std::collections::HashMap;

use crate::ast::{CnId, StrId};

#[derive(Debug, Clone)]
pub struct CanonicalNameEntry {
    /// `parent`; the root's is itself.
    pub parent: CnId,
    /// `name`, in the component's string pool.
    pub name: StrId,
    /// `childrenOrNull`, in insertion order.
    pub children: Vec<CnId>,
    /// `nonRootTop`: the ancestor that is a child of the root (itself for a
    /// child of the root); `None` for the root.
    pub nonRootTop: Option<CnId>,
}

/// The arena of canonical names; entry 0 is the root.
#[derive(Debug, Clone)]
pub struct CanonicalNames {
    pub entries: Vec<CanonicalNameEntry>,
    lookup: HashMap<(CnId, StrId), CnId>,
}

impl Default for CanonicalNames {
    fn default() -> Self {
        Self::new()
    }
}

impl CanonicalNames {
    /// The root (`CanonicalName.root()`), whose name is the empty string,
    /// string 0 of every pool.
    pub const root: CnId = 0;

    pub fn new() -> Self {
        CanonicalNames {
            entries: vec![CanonicalNameEntry {
                parent: 0,
                name: 0,
                children: Vec::new(),
                nonRootTop: None,
            }],
            lookup: HashMap::new(),
        }
    }

    pub fn isRoot(&self, name: CnId) -> bool {
        name == Self::root
    }

    pub fn parent(&self, name: CnId) -> Option<CnId> {
        if name == Self::root {
            None
        } else {
            Some(self.entries[name as usize].parent)
        }
    }

    pub fn name(&self, name: CnId) -> StrId {
        self.entries[name as usize].name
    }

    pub fn nonRootTop(&self, name: CnId) -> Option<CnId> {
        self.entries[name as usize].nonRootTop
    }

    pub fn children(&self, name: CnId) -> &[CnId] {
        &self.entries[name as usize].children
    }

    /// The child of [parent] named [name], if there is one.
    pub fn child(&self, parent: CnId, name: StrId) -> Option<CnId> {
        self.lookup.get(&(parent, name)).copied()
    }

    /// `getChild`: the child of [parent] named [name], created (last in
    /// [parent]'s children) when there is none.
    pub fn getChild(&mut self, parent: CnId, name: StrId) -> CnId {
        if let Some(&existing) = self.lookup.get(&(parent, name)) {
            return existing;
        }
        let id = self.entries.len() as CnId;
        let nonRootTop = if parent == Self::root {
            Some(id)
        } else {
            self.entries[parent as usize].nonRootTop
        };
        self.entries.push(CanonicalNameEntry {
            parent,
            name,
            children: Vec::new(),
            nonRootTop,
        });
        self.entries[parent as usize].children.push(id);
        self.lookup.insert((parent, name), id);
        id
    }

    /// `removeChild`: detaches [name] from its parent. The entry stays in
    /// the arena, unreachable, so ids already handed out stay valid.
    pub fn removeChild(&mut self, parent: CnId, name: StrId) {
        if let Some(child) = self.lookup.remove(&(parent, name)) {
            self.entries[parent as usize].children.retain(|&c| c != child);
        }
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}
