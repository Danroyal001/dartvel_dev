// Port of lib/src/summary2/export.dart (`Export`, `ExportEntry`,
// `ExportLocation`, `ExportScope`) and lib/src/summary2/combinator.dart.
//
// An entry's `reference` is the element it names: upstream compares the
// references of the reference tree, which name one element each.

use std::collections::HashMap;
use std::rc::Rc;

use crate::src::dart::element::element::{ElementId, NamespaceCombinator};

/// `Combinator`.
#[derive(Clone, Debug)]
pub struct Combinator {
    pub is_show: bool,
    pub names: Vec<Rc<str>>,
}

impl Combinator {
    /// `matches`: a setter name matches without its `=`.
    pub fn matches(&self, name: &str) -> bool {
        let name = name.strip_suffix('=').unwrap_or(name);
        self.names.iter().any(|n| &**n == name)
    }
}

/// `CombinatorListExtension.allows`.
pub fn allows(combinators: &[Combinator], name: &str) -> bool {
    for combinator in combinators {
        if combinator.is_show && !combinator.matches(name) {
            return false;
        }
        if !combinator.is_show && combinator.matches(name) {
            return false;
        }
    }
    true
}

/// `NamespaceCombinatorListExtension.build`.
pub fn build_combinators(combinators: &[NamespaceCombinator]) -> Vec<Combinator> {
    combinators
        .iter()
        .map(|c| Combinator {
            is_show: c.is_show,
            names: c.names.clone(),
        })
        .collect()
}

/// `ExportLocation`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ExportLocation {
    /// The index of the fragment with the `export` directive.
    pub fragment_index: u32,
    /// The index in `LibraryFragmentImpl.libraryExports`.
    pub export_index: u32,
}

/// `ExportEntry`.
#[derive(Clone, Debug)]
pub struct ExportEntry {
    pub name: Rc<str>,
    pub reference: ElementId,
    pub locations: Vec<ExportLocation>,
}

impl ExportEntry {
    pub fn is_re_exported(&self) -> bool {
        !self.locations.is_empty()
    }
}

/// `Export`: an `export` directive of [exporter] (a library builder's
/// index) that exports a library.
#[derive(Clone, Debug)]
pub struct Export {
    pub exporter: usize,
    pub location: ExportLocation,
    pub combinators: Vec<Combinator>,
}

/// `ExportScope`.
#[derive(Clone, Debug, Default)]
pub struct ExportScope {
    /// `entriesByName`, in insertion order.
    pub entries: Vec<ExportEntry>,
    index: HashMap<Rc<str>, usize>,
}

impl ExportScope {
    pub fn declare(&mut self, name: Rc<str>, reference: ElementId) {
        let entry = ExportEntry {
            name: name.clone(),
            reference,
            locations: Vec::new(),
        };
        match self.index.get(&name) {
            Some(&i) => self.entries[i] = entry,
            None => {
                self.index.insert(name, self.entries.len());
                self.entries.push(entry);
            }
        }
    }

    /// `export`: whether [entry] was added.
    pub fn export(&mut self, location: ExportLocation, entry: &ExportEntry) -> bool {
        if let Some(&i) = self.index.get(&entry.name) {
            let existing = &mut self.entries[i];
            if existing.reference == entry.reference {
                if existing.is_re_exported() && !existing.locations.contains(&location) {
                    existing.locations.push(location);
                }
            }
            // Same element, or an ambiguous declaration.
            return false;
        }
        self.index.insert(entry.name.clone(), self.entries.len());
        self.entries.push(ExportEntry {
            name: entry.name.clone(),
            reference: entry.reference,
            locations: vec![location],
        });
        true
    }
}
