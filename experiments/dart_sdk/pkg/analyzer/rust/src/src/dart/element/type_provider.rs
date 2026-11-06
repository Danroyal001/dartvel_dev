// Port of lib/src/dart/element/type_provider.dart: TypeProviderImpl's five
// non-generic core types used by context-independent literal resolution.
use crate::dart::element::nullability_suffix::NullabilitySuffix;
use crate::src::dart::element::element::{ElementStore, LibraryId};
use crate::src::dart::element::r#type::TypeImpl;

pub struct TypeProviderImpl {
    pub bool_type: TypeImpl,
    pub double_type: TypeImpl,
    pub null_type: TypeImpl,
    pub string_type: TypeImpl,
    pub symbol_type: TypeImpl,
}

impl TypeProviderImpl {
    pub fn new(store: &ElementStore, core: LibraryId) -> Self {
        let core_type = |name: &str| {
            let class = store.libraries[core as usize]
                .classes
                .iter()
                .copied()
                .find(|&id| store.element(id).name.as_deref() == Some(name))
                .unwrap_or_else(|| panic!("dart:core is missing {name}"));
            TypeImpl::interface(class, Vec::new(), NullabilitySuffix::none)
        };
        Self {
            bool_type: core_type("bool"),
            double_type: core_type("double"),
            null_type: core_type("Null"),
            string_type: core_type("String"),
            symbol_type: core_type("Symbol"),
        }
    }
}
