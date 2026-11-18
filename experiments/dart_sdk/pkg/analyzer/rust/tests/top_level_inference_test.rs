// Tests of the representation types that linking gives extension types (not a
// mirrored file; see ../README.md): what the element oracle's corpora reach
// rarely or not at all. Each expectation was read from upstream's
// `element_dump.dart --types` on the same declarations.
//
// - `TopLevelInference`: an untyped declaring parameter with no default
//   value gets `Object?` (`_PropertyInducingElementTypeInference.perform`).
// - `PropertyInducingElementImpl.type`: a recovery representation field
//   (no regular first parameter) has no type and no inference, so reading
//   it gives `InvalidType`; and `breakInterfaceCycles` reads the
//   representation of an extension type in an `implements` cycle before
//   inference runs, which fixes it to `InvalidType` as well.
// - `buildExtensionTypes`: extension types whose representation types
//   depend on each other get `InvalidType` for the representation and its
//   declaring parameter.
//
// The SDK is a `dart:core` with `Object`, `Null`, `int` and `List<E>`, so the tests
// run under Miri (with `-Zmiri-disable-isolation`).

use std::path::{Path, PathBuf};

use analyzer::src::context::packages::parse_package_config_json_file;
use analyzer::src::dart::analysis::file_state::FileSystemState;
use analyzer::src::dart::element::display_string_builder::display_string;
use analyzer::src::dart::element::element::{ElementId, ElementStore, LibraryId};
use analyzer::src::dart::sdk::sdk::FolderBasedDartSdk;
use analyzer::src::summary2::link::Linker;

fn test_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("top_level_inference_test_{}_{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn write(path: &Path, content: &str) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, content).unwrap();
}

/// Links `package:test/a.dart` with [content].
fn link(name: &str, content: &str) -> (Linker, LibraryId) {
    let dir = test_dir(name);
    write(
        &dir.join("sdk/lib/_internal/sdk_library_metadata/lib/libraries.dart"),
        "const Map<String, LibraryInfo> libraries = const {\n  'core': const LibraryInfo('core/core.dart'),\n};\n",
    );
    write(
        &dir.join("sdk/lib/core/core.dart"),
        "library dart.core;\nclass Object {}\nclass Null {}\nclass int {}\nclass List<E> {}\n",
    );
    write(
        &dir.join("package_config.json"),
        "{\"configVersion\": 2, \"packages\": [{\"name\": \"test\", \"rootUri\": \"test/\", \"packageUri\": \"lib/\"}]}",
    );
    write(&dir.join("test/lib/a.dart"), content);
    let fs = FileSystemState::new(
        FolderBasedDartSdk::new(&dir.join("sdk")),
        parse_package_config_json_file(&dir.join("package_config.json")),
    );
    let mut linker = Linker::new(fs);
    let file = linker.fs.get_file_for_uri("package:test/a.dart").unwrap();
    let library = linker.library_for(file).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    (linker, library)
}

fn extension_type(store: &ElementStore, library: LibraryId, name: &str) -> ElementId {
    store.libraries[library as usize]
        .extension_types
        .iter()
        .copied()
        .find(|&e| store.element(e).name.as_deref() == Some(name))
        .unwrap_or_else(|| panic!("no extension type {name}"))
}

/// The dump's `representationType`: the type of the first field, `-` when
/// it has none.
fn representation(store: &ElementStore, library: LibraryId, name: &str) -> String {
    let e = extension_type(store, library, name);
    let field = store.element(e).members().fields[0];
    match &store.element(field).type_ {
        Some(t) => display_string(store, t),
        None => "-".to_string(),
    }
}

/// The type of the primary constructor's first formal parameter.
fn first_formal_type(store: &ElementStore, library: LibraryId, name: &str) -> String {
    let e = extension_type(store, library, name);
    let constructor = store.element(e).members().constructors[0];
    let first = store.element(constructor).first_fragment;
    let formal = store.fragment(first).formal_parameters[0];
    let formal_element = store.fragment(formal).element;
    match &store.element(formal_element).type_ {
        Some(t) => display_string(store, t),
        None => "-".to_string(),
    }
}

#[test]
fn an_untyped_declaring_representation_is_object_question() {
    let (linker, library) = link(
        "untyped",
        "extension type A(x) {}\nextension type A2(final x) {}\nextension type K(x, final y) {}\n\
         extension type L(x) {\n  L.named(this.x);\n}\nextension type T(int x) {}\n",
    );
    let store = &linker.store;
    for name in ["A", "A2", "K", "L"] {
        assert_eq!(representation(store, library, name), "Object?", "{name}");
    }
    assert_eq!(representation(store, library, "T"), "int");
}

#[test]
fn a_recovery_representation_is_invalid() {
    let (linker, library) = link("recovery", "extension type B() {}\nextension type C(this.x) {}\n");
    let store = &linker.store;
    assert_eq!(representation(store, library, "B"), "InvalidType");
    assert_eq!(representation(store, library, "C"), "InvalidType");
}

#[test]
fn an_implements_cycle_reads_the_representation_before_inference() {
    let (linker, library) = link(
        "implements_cycle",
        "extension type D(x) implements D {}\nextension type G(x) implements H {}\n\
         extension type H(G g) implements G {}\n",
    );
    let store = &linker.store;
    assert_eq!(representation(store, library, "D"), "InvalidType");
    assert_eq!(representation(store, library, "G"), "InvalidType");
    assert_eq!(representation(store, library, "H"), "G");
}

#[test]
fn representations_that_depend_on_each_other_are_invalid() {
    let (linker, library) = link(
        "representation_cycle",
        "extension type E(F f) {}\nextension type F(E e) {}\nextension type I(I i) {}\n\
         extension type J(List<J> j) {}\nextension type M(List<E> m) {}\n",
    );
    let store = &linker.store;
    for name in ["E", "F", "I", "J"] {
        assert_eq!(representation(store, library, name), "InvalidType", "{name}");
        assert_eq!(first_formal_type(store, library, name), "InvalidType", "{name}");
    }
    assert_eq!(representation(store, library, "M"), "List<E>");
    let m = extension_type(store, library, "M");
    assert!(!store.types(m).is_some_and(|t| t.has_representation_self_reference));
    let i = extension_type(store, library, "I");
    assert!(store.types(i).is_some_and(|t| t.has_representation_self_reference));
}
