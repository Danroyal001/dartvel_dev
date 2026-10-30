// Port of lib/src/dart/resolver/scope.dart: `Namespace` and the
// `NamespaceBuilder` methods that make the namespace of an import or an
// export from the export namespace of the library it names.
//
// A namespace is its defined names, in the order the map holds them; a
// prefixed namespace holds the same names (`PrefixedNamespace.definedNames2`
// returns them unprefixed).

use std::rc::Rc;

use crate::src::dart::element::element::{ElementId, ElementStore, LibraryId, NamespaceCombinator};

pub type Namespace = Vec<(Rc<str>, ElementId)>;

/// `NamespaceBuilder.createImportNamespaceForDirective` and
/// `createExportNamespaceForDirective2`: the export namespace of
/// [library], with [combinators] applied.
pub fn create_namespace_for_directive(
    store: &ElementStore,
    library: LibraryId,
    combinators: &[NamespaceCombinator],
) -> Namespace {
    let mut defined_names: Namespace = store.libraries[library as usize].export_namespace.clone();
    for combinator in combinators {
        defined_names = if combinator.is_show {
            show(&defined_names, &combinator.names)
        } else {
            hide(&defined_names, &combinator.names)
        };
    }
    defined_names
}

fn get(names: &Namespace, name: &str) -> Option<ElementId> {
    names.iter().find(|(n, _)| &**n == name).map(|(_, e)| *e)
}

/// `_hide`.
fn hide(defined_names: &Namespace, hidden_names: &[Rc<str>]) -> Namespace {
    let mut new_names = defined_names.clone();
    for name in hidden_names {
        let setter = format!("{name}=");
        new_names.retain(|(n, _)| **n != **name && **n != *setter);
    }
    new_names
}

/// `_show`.
fn show(defined_names: &Namespace, shown_names: &[Rc<str>]) -> Namespace {
    let mut new_names: Namespace = Vec::new();
    let put = |names: &mut Namespace, name: Rc<str>, element: ElementId| {
        match names.iter_mut().find(|(n, _)| *n == name) {
            Some(entry) => entry.1 = element,
            None => names.push((name, element)),
        }
    };
    for name in shown_names {
        if let Some(element) = get(defined_names, name) {
            put(&mut new_names, name.clone(), element);
        }
        let setter_name: Rc<str> = Rc::from(format!("{name}="));
        if let Some(element) = get(defined_names, &setter_name) {
            put(&mut new_names, setter_name, element);
        }
    }
    new_names
}
