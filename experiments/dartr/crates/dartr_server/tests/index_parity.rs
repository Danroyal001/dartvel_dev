//! The unit index (Dart `indexUnit`), against the index Dart 3.13.3 builds.
//!
//! The order of the elements of a unit index (Dart `_IndexAssembler`):
//! the element infos are created in the order the contributor first meets
//! the elements, then sorted by name with the unstable `List.sort` of the
//! Dart VM, so for elements with equal names (a class and the class of the
//! same name in an import with a prefix) the creation order decides the
//! ids, and with them the order of the references a search returns.
//!
//! The expected orders were printed from `AnalysisDriverUnitIndex` by
//! `package:analyzer` of the Dart SDK 3.13.3 (`AnalysisDriver.getIndex`).
//! Needs a Dart SDK (the first `dart` on `PATH`); skipped without one.

use dartr_cli::DriverSession;
use dartr_project::{AnalysisContextCollection, CollectionOptions};

fn temp_project(name: &str, files: &[(&str, String)]) -> std::path::PathBuf {
    let unique = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root = std::env::temp_dir().join(format!("dartr-index-order-{name}-{unique}"));
    std::fs::create_dir_all(root.join("lib")).unwrap();
    std::fs::write(
        root.join("pubspec.yaml"),
        format!("name: {name}\nenvironment:\n  sdk: ^3.9.0\n"),
    )
    .unwrap();
    for (path, text) in files {
        std::fs::write(root.join(path), text).unwrap();
    }
    root.canonicalize().unwrap()
}

/// The elements of the index of [file], as `<file name> <unit member>|
/// <class member>|<parameter> <kind>`.
fn index_elements(root: &std::path::Path, file: &str) -> Option<Vec<String>> {
    let root_str = root.to_string_lossy().to_string();
    let collection = AnalysisContextCollection::new(&[root_str], &CollectionOptions::default());
    if collection.sdk.is_none() {
        return None;
    }
    let path = root.join(file).to_string_lossy().to_string();
    let mut session = DriverSession::default();
    let library = session.resolved_library(&collection, &path).unwrap();
    let unit_index = library.unit_index(&path).unwrap();
    let sink = dartr_element::NoopSink;
    let ctx = library.ctx(unit_index, &sink);
    let unit = &library.library.units[unit_index];
    let index = dartr_server::index::index_unit(&ctx, &unit.ast, &unit.tables, unit.unit);
    Some(
        index
            .elements
            .iter()
            .map(|e| {
                let file = e.unit_path.rsplit('/').next().unwrap_or_default();
                let file = if e.unit_path.starts_with(&*root.to_string_lossy()) {
                    file
                } else {
                    "sdk"
                };
                format!(
                    "{file} {}|{}|{} {:?}",
                    e.unit_member.as_deref().unwrap_or(""),
                    e.class_member.as_deref().unwrap_or(""),
                    e.parameter.as_deref().unwrap_or(""),
                    e.kind
                )
            })
            .collect(),
    )
}

/// Dart `visitPrefixedIdentifier` calls `addPrefixForElement` with
/// `node.element`, which is `identifier.element`, before it visits the
/// prefix: in `a.E.x` the info of the imported `E` is created before the
/// info of the prefix `a`. With 47 infos the VM sort is a quicksort, which
/// orders the two `E` infos by their creation positions.
#[test]
fn prefixed_identifier_creates_the_element_info_before_the_prefix() {
    let mut main = String::from("import 'other.dart' as a;\n\nenum E { x }\n\n");
    for i in 0..40 {
        main.push_str(&format!("void f{i}() {{}}\n"));
    }
    main.push_str("\nObject h() {\n");
    for i in 0..12 {
        main.push_str(&format!("  f{i}();\n"));
    }
    main.push_str("  E.x;\n  a.E.x;\n");
    for i in 12..40 {
        main.push_str(&format!("  f{i}();\n"));
    }
    main.push_str("  return 0;\n}\n");
    let root = temp_project(
        "prefixed",
        &[
            ("lib/other.dart", "enum E { x }\n".to_string()),
            ("lib/main.dart", main),
        ],
    );
    let Some(elements) = index_elements(&root, "lib/main.dart") else {
        eprintln!("skipped: no Dart SDK");
        let _ = std::fs::remove_dir_all(&root);
        return;
    };
    let _ = std::fs::remove_dir_all(&root);
    let mut expected = vec![
        "other.dart E|| NotSynthetic",
        "main.dart E|| NotSynthetic",
        "main.dart E|.new| NotSynthetic",
        "main.dart E|x| Getter",
        "other.dart E|x| Getter",
        "sdk Object|| NotSynthetic",
        "main.dart a|| NotSynthetic",
    ]
    .into_iter()
    .map(String::from)
    .collect::<Vec<_>>();
    let mut functions: Vec<String> = (0..40).map(|i| format!("f{i}")).collect();
    functions.sort();
    expected.extend(
        functions
            .iter()
            .map(|f| format!("main.dart {f}|| NotSynthetic")),
    );
    assert_eq!(elements, expected);
}

/// The relations of the index of [file], as `<element> <kind> <offset>
/// <length> <qualified>` (element as in [index_elements]).
fn index_relations(root: &std::path::Path, file: &str) -> Option<Vec<String>> {
    let elements = index_elements(root, file)?;
    let root_str = root.to_string_lossy().to_string();
    let collection = AnalysisContextCollection::new(&[root_str], &CollectionOptions::default());
    let path = root.join(file).to_string_lossy().to_string();
    let mut session = DriverSession::default();
    let library = session.resolved_library(&collection, &path).unwrap();
    let unit_index = library.unit_index(&path).unwrap();
    let sink = dartr_element::NoopSink;
    let ctx = library.ctx(unit_index, &sink);
    let unit = &library.library.units[unit_index];
    let index = dartr_server::index::index_unit(&ctx, &unit.ast, &unit.tables, unit.unit);
    Some(
        index
            .relations
            .iter()
            .map(|r| {
                format!(
                    "{} {:?} {} {} {}",
                    elements[r.element], r.kind, r.offset, r.length, r.is_qualified
                )
            })
            .collect(),
    )
}

/// Dart `visitIndexExpression` records `IS_INVOKED_BY` of
/// `node.writeOrReadElement`, which is the `writeElement` of the
/// assignment, postfix or prefix expression the index expression is the
/// target of (`[]=`), else the index expression's own `element` (`[]`).
#[test]
fn index_expression_records_the_write_element() {
    let root = temp_project(
        "index_write",
        &[(
            "lib/main.dart",
            "void f(List<int> l, Map<String, int> m) {\n  l[0] = 1;\n  m['a'] = 2;\n  \
             m['b'] = m['b']! + 3;\n  l[1] += 4;\n  l[2]++;\n  l[3];\n}\n"
                .to_string(),
        )],
    );
    let Some(relations) = index_relations(&root, "lib/main.dart") else {
        eprintln!("skipped: no Dart SDK");
        let _ = std::fs::remove_dir_all(&root);
        return;
    };
    let _ = std::fs::remove_dir_all(&root);
    let expected = [
        "sdk List|| NotSynthetic IsReferencedBy 7 4 false",
        "sdk List|[]| NotSynthetic IsInvokedBy 118 1 true",
        "sdk List|[]=| NotSynthetic IsInvokedBy 45 1 true",
        "sdk List|[]=| NotSynthetic IsInvokedBy 95 1 true",
        "sdk List|[]=| NotSynthetic IsInvokedBy 108 1 true",
        "sdk Map|| NotSynthetic IsReferencedBy 20 3 false",
        "sdk Map|[]| NotSynthetic IsInvokedBy 80 1 true",
        "sdk Map|[]=| NotSynthetic IsInvokedBy 57 1 true",
        "sdk Map|[]=| NotSynthetic IsInvokedBy 71 1 true",
        "sdk String|| NotSynthetic IsReferencedBy 24 6 false",
        "main.dart f||l NotSynthetic IsReadBy 44 1 false",
        "main.dart f||l NotSynthetic IsReadBy 94 1 false",
        "main.dart f||l NotSynthetic IsReadBy 107 1 false",
        "main.dart f||l NotSynthetic IsReadBy 117 1 false",
        "main.dart f||m NotSynthetic IsReadBy 56 1 false",
        "main.dart f||m NotSynthetic IsReadBy 70 1 false",
        "main.dart f||m NotSynthetic IsReadBy 79 1 false",
        "sdk int|| NotSynthetic IsReferencedBy 12 3 false",
        "sdk int|| NotSynthetic IsReferencedBy 32 3 false",
        "sdk num|+| NotSynthetic IsInvokedBy 87 1 true",
        "sdk num|+| NotSynthetic IsInvokedBy 99 2 true",
        "sdk num|+| NotSynthetic IsInvokedBy 111 2 true",
    ];
    assert_eq!(relations, expected);
}
