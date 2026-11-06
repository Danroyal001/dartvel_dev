// Not an upstream file: a hand-built SDK for the type algorithm tests:
// Object, Null, num, int, double, String, Function in dart:core, Future and
// FutureOr in dart:async, and a generic List<E>.

#![allow(dead_code)]

use std::rc::Rc;

use analyzer::dart::element::nullability_suffix::NullabilitySuffix;
use analyzer::src::dart::element::element::{
    ElementId, ElementKind, ElementStore, FragmentImpl, FragmentKind, LibraryElementImpl, LibraryFragmentImpl, LibraryId,
};
use analyzer::src::dart::element::r#type::{FormalParameter, FunctionTypeImpl, TypeImpl};
use analyzer::src::generated::utilities_dart::ParameterKind;

pub struct Sdk {
    pub store: ElementStore,
    pub core: LibraryId,
    pub object: ElementId,
    pub null: ElementId,
    pub num: ElementId,
    pub int: ElementId,
    pub double: ElementId,
    pub string: ElementId,
    pub list: ElementId,
    pub future: ElementId,
    pub future_or: ElementId,
    pub function: ElementId,
}

pub fn library(store: &mut ElementStore, uri: &str) -> LibraryId {
    let id = store.libraries.len() as LibraryId;
    store.libraries.push(LibraryElementImpl::new(Rc::from(uri), Rc::from(""), -1, 0));
    store.units.push(LibraryFragmentImpl::new(id, Rc::from(uri)));
    id
}

pub fn class(store: &mut ElementStore, library: LibraryId, name: &str, supertype: Option<TypeImpl>) -> ElementId {
    let fragment = store.add_fragment(FragmentImpl::new(FragmentKind::Class, Some(Rc::from(name))));
    let e = store.add_element(ElementKind::CLASS, fragment, library);
    store.libraries[library as usize].classes.push(e);
    store.elements[e as usize].type_ = supertype;
    e
}

/// Adds a type parameter named [name] to [class], with [bound].
pub fn type_parameter(store: &mut ElementStore, class: ElementId, name: &str, bound: Option<TypeImpl>) -> ElementId {
    let library = store.element(class).library;
    let fragment = store.add_fragment(FragmentImpl::new(FragmentKind::TypeParameter, Some(Rc::from(name))));
    let e = store.add_element(ElementKind::TYPE_PARAMETER, fragment, library);
    let first = store.element(class).first_fragment;
    store.fragment_mut(first).type_parameters.push(fragment);
    store.elements[e as usize].type_ = bound;
    e
}

/// A free type parameter [name] with [bound], as inference has.
pub fn free_type_parameter(store: &mut ElementStore, name: &str, bound: Option<TypeImpl>) -> ElementId {
    let e = store.add_synthetic_type_parameter(Some(Rc::from(name)), 0);
    store.elements[e as usize].type_ = bound;
    e
}

pub fn i(element: ElementId, args: Vec<TypeImpl>, s: NullabilitySuffix) -> TypeImpl {
    TypeImpl::interface(element, args, s)
}

pub fn tp(element: ElementId, s: NullabilitySuffix) -> TypeImpl {
    TypeImpl::type_parameter(element, s)
}

pub fn function(params: Vec<(TypeImpl, ParameterKind, Option<&str>)>, ret: TypeImpl) -> TypeImpl {
    generic_function(Vec::new(), params, ret)
}

pub fn generic_function(
    type_parameters: Vec<ElementId>,
    params: Vec<(TypeImpl, ParameterKind, Option<&str>)>,
    ret: TypeImpl,
) -> TypeImpl {
    let formal_parameters = params
        .into_iter()
        .map(|(t, kind, name)| FormalParameter { name: name.map(Rc::from), type_: t, kind })
        .collect();
    TypeImpl::Function(Rc::new(FunctionTypeImpl::new(type_parameters, formal_parameters, ret, NullabilitySuffix::none)))
}

pub fn sdk() -> Sdk {
    use NullabilitySuffix::none;
    let mut store = ElementStore::new();
    let core = library(&mut store, "dart:core");
    let object = class(&mut store, core, "Object", None);
    let o = i(object, vec![], none);
    let null = class(&mut store, core, "Null", Some(o.clone()));
    let num = class(&mut store, core, "num", Some(o.clone()));
    let int = class(&mut store, core, "int", Some(i(num, vec![], none)));
    let double = class(&mut store, core, "double", Some(i(num, vec![], none)));
    let string = class(&mut store, core, "String", Some(o.clone()));
    let function = class(&mut store, core, "Function", Some(o.clone()));
    let list = class(&mut store, core, "List", Some(o.clone()));
    type_parameter(&mut store, list, "E", None);
    let async_ = library(&mut store, "dart:async");
    let future = class(&mut store, async_, "Future", Some(o.clone()));
    type_parameter(&mut store, future, "T", None);
    let future_or = class(&mut store, async_, "FutureOr", Some(o));
    type_parameter(&mut store, future_or, "T", None);
    Sdk { store, core, object, null, num, int, double, string, list, future, future_or, function }
}

impl Sdk {
    pub fn int_(&self) -> TypeImpl {
        i(self.int, vec![], NullabilitySuffix::none)
    }
    pub fn num_(&self) -> TypeImpl {
        i(self.num, vec![], NullabilitySuffix::none)
    }
    pub fn object_q(&self) -> TypeImpl {
        i(self.object, vec![], NullabilitySuffix::question)
    }
    pub fn object_(&self) -> TypeImpl {
        i(self.object, vec![], NullabilitySuffix::none)
    }
    pub fn list_of(&self, t: TypeImpl) -> TypeImpl {
        i(self.list, vec![t], NullabilitySuffix::none)
    }
}
