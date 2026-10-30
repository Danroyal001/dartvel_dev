// Tests of the element model port (not a mirrored file; see ../README.md):
// what the element oracle does not see on its corpus, or sees rarely.
//
// The files of each test are written to a directory of their own, with an
// SDK whose `libraries.dart` names a small `dart:core`, so that the tests
// read nothing else and run under Miri (with `-Zmiri-disable-isolation`,
// which lets them write and read files).
//
// - `resolve_relative_uri` resolves as `dart:core`'s `Uri.resolveUri` and
//   `_fe_analyzer_shared`'s `resolveRelativeUri` do (the corpus has few dot
//   segments and no `dart:` part with a path).
// - The JSON reader of the package config reads escapes and non-ASCII
//   names.
// - An ambiguous export keeps the first element (`ExportScope.export`), a
//   name exported twice keeps one entry, and `show`/`hide` apply to a
//   setter as to its getter (`Combinator.matches`, `_show`, `_hide`).
// - Getters and setters of one name share a variable unless one of them is
//   repeated (`_handleTopLevelGetterFragment`'s reset).
// - A file whose `part of` names another library is not a part of this
//   one (`isPartOf`), and a part included twice is one unit.

use std::path::{Path, PathBuf};
use std::rc::Rc;

use analyzer::src::context::packages::{Json, parse_package_config_json_file};
use analyzer::src::dart::analysis::file_state::FileSystemState;
use analyzer::src::dart::element::element::{DirectiveUri, ElementKind, ElementStore, LibraryId};
use analyzer::src::dart::resolver::scope::create_namespace_for_directive;
use analyzer::src::dart::sdk::sdk::FolderBasedDartSdk;
use analyzer::src::summary2::link::Linker;
use analyzer::src::utilities::uri_cache::{Uri, resolve_relative_uri};

/// A directory for one test, emptied.
fn test_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("element_builder_test_{}_{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn write(path: &Path, content: &str) {
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, content).unwrap();
}

/// Links `package:test/<file>` for each of [files] (path under `lib/`,
/// content) and returns the linker and the library of the first file.
fn link(name: &str, files: &[(&str, &str)]) -> (Linker, LibraryId) {
    let dir = test_dir(name);
    write(
        &dir.join("sdk/lib/_internal/sdk_library_metadata/lib/libraries.dart"),
        "const Map<String, LibraryInfo> libraries = const {\n  'core': const LibraryInfo('core/core.dart'),\n};\n",
    );
    write(&dir.join("sdk/lib/core/core.dart"), "library dart.core;\nclass Object {}\nclass Null {}\n");
    write(
        &dir.join("package_config.json"),
        "{\"configVersion\": 2, \"packages\": [{\"name\": \"test\", \"rootUri\": \"test/\", \"packageUri\": \"lib/\"}]}",
    );
    for (path, content) in files {
        write(&dir.join("test/lib").join(path), content);
    }
    let fs = FileSystemState::new(
        FolderBasedDartSdk::new(&dir.join("sdk")),
        parse_package_config_json_file(&dir.join("package_config.json")),
    );
    let mut linker = Linker::new(fs);
    let file = linker.fs.get_file_for_uri(&format!("package:test/{}", files[0].0)).unwrap();
    let library = linker.library_for(file).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    (linker, library)
}

fn names(store: &ElementStore, namespace: &[(Rc<str>, u32)]) -> Vec<String> {
    let mut result: Vec<String> = namespace
        .iter()
        .map(|(n, e)| {
            let element = store.element(*e);
            let library = &store.libraries[element.library as usize].uri;
            format!("{n} {} {library}", element.kind.name())
        })
        .collect();
    result.sort();
    result
}

#[test]
fn relative_uris_resolve_as_dart_core_resolves_them() {
    let cases = [
        ("dart:core", "bool.dart", "dart:core/bool.dart"),
        ("dart:core/core.dart", "bool.dart", "dart:core/bool.dart"),
        ("package:a/b/c.dart", "../d.dart", "package:a/d.dart"),
        ("package:a/b/c.dart", "./e/../f.dart", "package:a/b/f.dart"),
        ("package:a/b/c.dart", "package:x/y.dart", "package:x/y.dart"),
        ("file:///p/q/r.dart", "../../s.dart", "file:///s.dart"),
        ("file:///p/q/r.dart", "../../../s.dart", "file:///s.dart"),
        ("file:///p/q/r.dart", "/t/u.dart", "file:///t/u.dart"),
        ("file:///p/q/r.dart", "v.dart?w#x", "file:///p/q/v.dart?w#x"),
    ];
    for (base, contained, expected) in cases {
        let base = Uri::try_parse(base).unwrap();
        let contained = Uri::try_parse(contained).unwrap();
        assert_eq!(resolve_relative_uri(&base, &contained).to_string(), expected);
    }
    assert!(Uri::try_parse("1a:b").is_none());
    assert!(Uri::try_parse(":b").is_none());
}

#[test]
fn package_config_json_reads_escapes() {
    let json = Json::parse(r#"{"a": ["x\"y\\z", "éA", "é", 1.5e2, true, null, {}]}"#).unwrap();
    let Some(Json::Array(values)) = json.get("a") else {
        panic!("not an array");
    };
    match &values[..] {
        [
            Json::String(a),
            Json::String(b),
            Json::String(c),
            Json::Number(n),
            Json::Bool(true),
            Json::Null,
            Json::Object(o),
        ] => {
            assert_eq!(a, "x\"y\\z");
            assert_eq!(b, "éA");
            assert_eq!(c, "é");
            assert_eq!(*n, 150.0);
            assert!(o.is_empty());
        }
        other => panic!("{other:?}"),
    }
    assert!(Json::parse("{\"a\": 1,}").is_none());
    assert!(Json::parse("[1] 2").is_none());
}

#[test]
fn an_ambiguous_export_keeps_the_first_element() {
    let (linker, library) = link(
        "ambiguous",
        &[
            ("main.dart", "export 'a.dart';\nexport 'b.dart';\nexport 'a.dart' show A;\n"),
            ("a.dart", "class A {}\nclass Same {}\n"),
            ("b.dart", "class B {}\nint Same = 0;\n"),
        ],
    );
    let store = &linker.store;
    assert_eq!(
        names(store, &store.libraries[library as usize].export_namespace),
        [
            "A CLASS package:test/a.dart",
            "B CLASS package:test/b.dart",
            "Same CLASS package:test/a.dart",
            // `Same=` is not ambiguous: only b.dart declares it.
            "Same= SETTER package:test/b.dart",
        ]
    );
}

#[test]
fn combinators_apply_to_setters_as_to_getters() {
    let (linker, library) = link(
        "combinators",
        &[
            (
                "main.dart",
                "import 'a.dart' show x;\nimport 'a.dart' hide x;\nexport 'a.dart' hide y;\n",
            ),
            ("a.dart", "int x = 0;\nint y = 0;\nfinal z = 0;\n"),
        ],
    );
    let store = &linker.store;
    let unit = &store.units[store.libraries[library as usize].fragments[0] as usize];
    let namespace = |i: usize| {
        let import = &unit.library_imports[i];
        let DirectiveUri::WithLibrary { library, .. } = import.uri else {
            panic!("not a library");
        };
        names(store, &create_namespace_for_directive(store, library, &import.combinators))
    };
    assert_eq!(namespace(0), ["x GETTER package:test/a.dart", "x= SETTER package:test/a.dart"]);
    assert_eq!(
        namespace(1),
        [
            "y GETTER package:test/a.dart",
            "y= SETTER package:test/a.dart",
            "z GETTER package:test/a.dart",
        ]
    );
    assert_eq!(
        names(store, &store.libraries[library as usize].export_namespace),
        [
            "x GETTER package:test/a.dart",
            "x= SETTER package:test/a.dart",
            "z GETTER package:test/a.dart",
        ]
    );
    // The implicit import of dart:core comes last.
    assert!(unit.library_imports[2].is_synthetic);
}

#[test]
fn accessors_of_one_name_share_a_variable_unless_repeated() {
    let (linker, library) = link(
        "accessors",
        &["main.dart"]
            .iter()
            .map(|p| {
                (
                    *p,
                    "int get a => 0;\nset a(int v) {}\nint get b => 0;\nint get b => 1;\nclass C {\n  int get c => 0;\n  set c(int v) {}\n  set d(v) {}\n  set d(v) {}\n}\n",
                )
            })
            .collect::<Vec<_>>(),
    );
    let store = &linker.store;
    let lib = &store.libraries[library as usize];
    let variables: Vec<(String, bool, bool)> = lib
        .top_level_variables
        .iter()
        .map(|v| {
            let e = store.element(*v);
            (e.name.as_deref().unwrap().to_string(), e.getter != u32::MAX, e.setter != u32::MAX)
        })
        .collect();
    assert_eq!(
        variables,
        [
            ("a".to_string(), true, true),
            ("b".to_string(), true, false),
            ("b".to_string(), true, false),
        ]
    );
    let class = store.element(lib.classes[0]);
    let fields: Vec<(String, bool, bool)> = class
        .members()
        .fields
        .iter()
        .map(|f| {
            let e = store.element(*f);
            (e.name.as_deref().unwrap().to_string(), e.getter != u32::MAX, e.setter != u32::MAX)
        })
        .collect();
    assert_eq!(
        fields,
        [
            ("c".to_string(), true, true),
            ("d".to_string(), false, true),
            ("d".to_string(), false, true),
        ]
    );
    // The class gets the synthetic constructor.
    let constructor = store.element(class.members().constructors[0]);
    assert_eq!(constructor.kind, ElementKind::CONSTRUCTOR);
    assert_eq!(constructor.name.as_deref(), Some("new"));
}

#[test]
fn a_part_of_another_library_is_not_included() {
    let (linker, library) = link(
        "parts",
        &[
            ("main.dart", "library main;\npart 'p.dart';\npart 'q.dart';\npart 'p.dart';\n"),
            ("p.dart", "part of main;\nclass P {}\n"),
            ("q.dart", "part of other;\nclass Q {}\n"),
        ],
    );
    let store = &linker.store;
    let lib = &store.libraries[library as usize];
    assert_eq!(lib.fragments.len(), 2);
    let unit = &store.units[lib.fragments[0] as usize];
    let kinds: Vec<&str> = unit
        .parts
        .iter()
        .map(|p| match p.uri {
            DirectiveUri::WithUnit { .. } => "unit",
            DirectiveUri::WithSource { .. } => "source",
            _ => "other",
        })
        .collect();
    assert_eq!(kinds, ["unit", "source", "source"]);
    let classes: Vec<&str> = lib.classes.iter().map(|c| store.element(*c).name.as_deref().unwrap()).collect();
    assert_eq!(classes, ["P"]);
}
