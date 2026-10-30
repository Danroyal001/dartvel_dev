// Not an upstream file: tests of the port of display_string_builder.dart's
// type writers (`DartType.getDisplayString()`) and of type_algebra.dart's
// substitution, for cases the element oracle's corpus rarely reaches. The
// expected strings are what the Dart analyzer prints for the same types.

use std::rc::Rc;

use analyzer::dart::element::nullability_suffix::NullabilitySuffix;
use analyzer::src::dart::element::display_string_builder::display_string;
use analyzer::src::dart::element::element::{ElementId, ElementKind, ElementStore, FragmentImpl, FragmentKind, NO_LIBRARY};
use analyzer::src::dart::element::r#type::{FormalParameter, FunctionTypeImpl, RecordTypeImpl, TypeImpl};
use analyzer::src::dart::element::type_algebra::{substitute, Substitution};
use analyzer::src::generated::utilities_dart::ParameterKind;

use NullabilitySuffix::{none, question};

fn class(store: &mut ElementStore, name: &str) -> ElementId {
    let fragment = store.add_fragment(FragmentImpl::new(FragmentKind::Class, Some(Rc::from(name))));
    store.add_element(ElementKind::CLASS, fragment, NO_LIBRARY)
}

fn type_parameter(store: &mut ElementStore, name: &str) -> ElementId {
    store.add_synthetic_type_parameter(Some(Rc::from(name)), NO_LIBRARY)
}

fn interface(element: ElementId, arguments: Vec<TypeImpl>, suffix: NullabilitySuffix) -> TypeImpl {
    TypeImpl::interface(element, arguments, suffix)
}

fn tp(element: ElementId, suffix: NullabilitySuffix) -> TypeImpl {
    TypeImpl::type_parameter(element, suffix)
}

fn parameter(name: Option<&str>, type_: TypeImpl, kind: ParameterKind) -> FormalParameter {
    FormalParameter {
        name: name.map(Rc::from),
        type_,
        kind,
    }
}

fn function(
    type_parameters: Vec<ElementId>,
    parameters: Vec<FormalParameter>,
    return_type: TypeImpl,
    suffix: NullabilitySuffix,
) -> TypeImpl {
    TypeImpl::Function(Rc::new(FunctionTypeImpl::new(type_parameters, parameters, return_type, suffix)))
}

#[test]
fn simple_types() {
    let store = ElementStore::new();
    assert_eq!(display_string(&store, &TypeImpl::Dynamic), "dynamic");
    assert_eq!(display_string(&store, &TypeImpl::Void), "void");
    assert_eq!(display_string(&store, &TypeImpl::Invalid), "InvalidType");
    assert_eq!(display_string(&store, &TypeImpl::Never(none)), "Never");
    assert_eq!(display_string(&store, &TypeImpl::Never(question)), "Never?");
}

#[test]
fn interface_types() {
    let mut store = ElementStore::new();
    let int = class(&mut store, "int");
    let map = class(&mut store, "Map");
    let string = class(&mut store, "String");
    let t = interface(
        map,
        vec![interface(string, vec![], none), interface(int, vec![], question)],
        question,
    );
    assert_eq!(display_string(&store, &t), "Map<String, int?>?");
}

#[test]
fn function_type_parameter_groups() {
    let mut store = ElementStore::new();
    let int = class(&mut store, "int");
    let string = class(&mut store, "String");
    let i = interface(int, vec![], none);
    let s = interface(string, vec![], none);
    // Positional names are not written; named ones are; `required` prefixes
    // required named parameters.
    let f = function(
        vec![],
        vec![
            parameter(Some("a"), i.clone(), ParameterKind::REQUIRED),
            parameter(Some("b"), s.clone(), ParameterKind::POSITIONAL),
        ],
        TypeImpl::Void,
        none,
    );
    assert_eq!(display_string(&store, &f), "void Function(int, [String])");
    let g = function(
        vec![],
        vec![
            parameter(Some("x"), i.clone(), ParameterKind::REQUIRED),
            parameter(Some("b"), s.clone(), ParameterKind::NAMED_REQUIRED),
            parameter(Some("a"), i.clone(), ParameterKind::NAMED),
        ],
        i.clone(),
        question,
    );
    // The named parameters are sorted by name.
    assert_eq!(display_string(&store, &g), "int Function(int, {int a, required String b})?");
}

#[test]
fn generic_function_types() {
    let mut store = ElementStore::new();
    let object = class(&mut store, "Object");
    let t = type_parameter(&mut store, "T");
    store.elements[t as usize].type_ = Some(interface(object, vec![], none));
    let f = function(vec![t], vec![parameter(None, tp(t, question), ParameterKind::REQUIRED)], tp(t, none), none);
    assert_eq!(display_string(&store, &f), "T Function<T extends Object>(T?)");
}

#[test]
fn generic_function_type_parameters_are_renamed_when_they_clash() {
    // `_uniqueTypeParameters`: an inner `T` referenced alongside an outer `T`
    // becomes `T₀`.
    let mut store = ElementStore::new();
    let list = class(&mut store, "List");
    let outer = type_parameter(&mut store, "T");
    let inner = type_parameter(&mut store, "T");
    let f = function(
        vec![inner],
        vec![parameter(None, interface(list, vec![tp(outer, none)], none), ParameterKind::REQUIRED)],
        tp(inner, none),
        none,
    );
    assert_eq!(display_string(&store, &f), "T\u{2080} Function<T\u{2080}>(List<T>)");
}

#[test]
fn record_types() {
    let mut store = ElementStore::new();
    let int = class(&mut store, "int");
    let i = interface(int, vec![], none);
    let one = TypeImpl::Record(Rc::new(RecordTypeImpl::new(vec![i.clone()], vec![], none)));
    assert_eq!(display_string(&store, &one), "(int,)");
    let mixed = TypeImpl::Record(Rc::new(RecordTypeImpl::new(
        vec![i.clone()],
        vec![(Rc::from("b"), i.clone()), (Rc::from("a"), i.clone())],
        question,
    )));
    assert_eq!(display_string(&store, &mixed), "(int, {int a, int b})?");
    let empty = TypeImpl::Record(Rc::new(RecordTypeImpl::new(vec![], vec![], none)));
    assert_eq!(display_string(&store, &empty), "()");
}

#[test]
fn substitution_unites_nullability_and_keeps_unchanged_types() {
    let mut store = ElementStore::new();
    let int = class(&mut store, "int");
    let list = class(&mut store, "List");
    let t = type_parameter(&mut store, "T");
    let substitution = Substitution::from_pairs(vec![t], vec![interface(int, vec![], none)]);
    let nullable = substitute(&mut store, &substitution, &interface(list, vec![tp(t, question)], none));
    assert_eq!(display_string(&store, &nullable), "List<int?>");
    // A type that does not mention `T` comes back as the same object.
    let unrelated = interface(list, vec![interface(int, vec![], none)], none);
    let same = substitute(&mut store, &substitution, &unrelated);
    assert!(Rc::ptr_eq(unrelated.as_interface().unwrap(), same.as_interface().unwrap()));
}

#[test]
fn substitution_freshens_inner_type_parameters() {
    // Substituting into a generic function type gives it fresh type
    // parameters whose bounds are substituted too.
    let mut store = ElementStore::new();
    let int = class(&mut store, "int");
    let t = type_parameter(&mut store, "T");
    let u = type_parameter(&mut store, "U");
    store.elements[u as usize].type_ = Some(tp(t, none));
    let f = function(vec![u], vec![parameter(None, tp(t, none), ParameterKind::REQUIRED)], tp(u, none), none);
    let substitution = Substitution::from_pairs(vec![t], vec![interface(int, vec![], none)]);
    let g = substitute(&mut store, &substitution, &f);
    assert_eq!(display_string(&store, &g), "U Function<U extends int>(int)");
    let TypeImpl::Function(g) = g else { panic!() };
    assert_ne!(g.type_parameters[0], u);
}
