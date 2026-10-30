// Port of rust/oracle/element_dump.dart: the Rust side of the element
// oracle (see ../../../README.md).
//
// Writes, for every library among the `.dart` files under the corpus
// roots, the elements the Rust port builds from its declarations, in
// exactly the format the Dart oracle writes for the analyzer, so the two
// outputs can be compared byte for byte.
//
// Usage: element_dump --sdk <dir> --packages <package_config.json>
//          [--types] [--bench=N] --out <dir> <root>...
//
// `--bench=N` links the corpus N times, each time from nothing (the files
// are read and parsed again, as a new analysis context does), and prints
// the fastest and median round.

#![forbid(unsafe_code)]

use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::Instant;

use analyzer::src::context::packages::parse_package_config_json_file;
use analyzer::src::dart::analysis::file_state::FileSystemState;
use analyzer::src::dart::element::element::{
    DirectiveUri, ElementId, ElementKind, ElementStore, FragmentFlag, FragmentId, FragmentKind,
    LibraryId, NamespaceCombinator, NO_ELEMENT, NO_LIBRARY,
};
use analyzer::src::dart::resolver::scope::create_namespace_for_directive;
use analyzer::src::dart::sdk::sdk::FolderBasedDartSdk;
use analyzer::src::generated::utilities_dart::ParameterKind;
use analyzer::src::summary2::link::Linker;

fn main() {
    let mut out: Option<String> = None;
    let mut sdk: Option<String> = None;
    let mut packages: Option<String> = None;
    let mut bench = 0usize;
    let mut types = false;
    let mut roots: Vec<String> = Vec::new();
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        if let Some(n) = arg.strip_prefix("--bench=") {
            bench = n.parse().expect("--bench=N");
        } else if arg == "--types" {
            types = true;
        } else if arg == "--out" {
            out = args.next();
        } else if arg == "--sdk" {
            sdk = args.next();
        } else if arg == "--packages" {
            packages = args.next();
        } else {
            roots.push(arg);
        }
    }
    let (Some(sdk), Some(packages)) = (sdk, packages) else {
        usage();
    };
    if roots.is_empty() || (out.is_none() && bench == 0) {
        usage();
    }
    if types {
        // Resolving the declared types is not ported yet.
        eprintln!("element_dump: --types is not ported yet");
        std::process::exit(70);
    }
    let sdk = std::path::absolute(&sdk).unwrap();
    let packages = std::path::absolute(&packages).unwrap();
    let inputs = corpus_files(&roots);

    if bench > 0 {
        let mut times = Vec::new();
        for round in 0..bench {
            let start = Instant::now();
            let (linker, libraries) = link_corpus(&sdk, &packages, &inputs);
            let elapsed = start.elapsed();
            eprintln!(
                "round {round}: {:.3} ms, {} libraries, {} elements",
                elapsed.as_secs_f64() * 1000.0,
                libraries.iter().filter(|l| l.is_some()).count(),
                linker.store.elements.len()
            );
            drop(linker);
            times.push(elapsed.as_micros());
        }
        times.sort();
        println!(
            "fastest {} ms, median {} ms, peak RSS {:.1} MiB",
            times[0] as f64 / 1000.0,
            times[times.len() / 2] as f64 / 1000.0,
            status_bytes("VmHWM") as f64 / (1024.0 * 1024.0)
        );
        return;
    }

    let out = out.unwrap();
    let (linker, libraries) = link_corpus(&sdk, &packages, &inputs);
    for ((_, relative), library) in inputs.iter().zip(libraries) {
        let Some(library) = library else {
            continue;
        };
        let dump = ElementDumper::new(&linker.store).dump_library(library);
        let target = PathBuf::from(format!("{out}/{relative}.elements"));
        fs::create_dir_all(target.parent().unwrap()).unwrap();
        fs::write(&target, dump).unwrap();
    }
}

fn usage() -> ! {
    eprintln!(
        "usage: element_dump --sdk <dir> --packages <file> [--types] [--bench=N] --out <dir> <root>..."
    );
    std::process::exit(64);
}

/// Links every library of the corpus (`getLibraryByUri` of each file's
/// URI): the library of each input, or `None` for a part.
fn link_corpus(sdk: &Path, packages: &Path, inputs: &[(PathBuf, String)]) -> (Linker, Vec<Option<LibraryId>>) {
    let fs = FileSystemState::new(FolderBasedDartSdk::new(sdk), parse_package_config_json_file(packages));
    let mut linker = Linker::new(fs);
    // One file at a time, as the oracle asks for them: which file is read
    // first can matter (see `FileSystemState.unlinked_is_dart_core`).
    let libraries = inputs
        .iter()
        .map(|(path, _)| {
            let uri = linker.fs.path_to_uri(path);
            let file = linker.fs.get_file_for_uri(&uri).expect("a corpus file has a URI");
            linker.library_for(file)
        })
        .collect();
    (linker, libraries)
}

/// Every `.dart` file under [roots] as (path, label/relative path), sorted
/// by relative path within each root, as the oracle lists them.
fn corpus_files(roots: &[String]) -> Vec<(PathBuf, String)> {
    let mut seen: std::collections::HashMap<String, usize> = Default::default();
    let mut result = Vec::new();
    for root in roots {
        let dir = std::path::absolute(root).expect("absolute corpus root");
        let base = dir.file_name().unwrap().to_string_lossy().to_string();
        let count = seen.entry(base.clone()).or_insert(0);
        *count += 1;
        let label = if *count == 1 { base } else { format!("{base}~{count}") };
        let mut files = Vec::new();
        walk(&dir, &dir, &label, &mut files);
        files.sort_by(|a: &(PathBuf, String), b| a.1.as_bytes().cmp(b.1.as_bytes()));
        result.extend(files);
    }
    result
}

fn walk(root: &Path, dir: &Path, label: &str, files: &mut Vec<(PathBuf, String)>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(meta) = fs::symlink_metadata(&path) else {
            continue;
        };
        if meta.is_dir() {
            walk(root, &path, label, files);
        } else if meta.is_file() && path.to_string_lossy().ends_with(".dart") {
            let relative = path.strip_prefix(root).unwrap().to_string_lossy().to_string();
            files.push((path.clone(), format!("{label}/{relative}")));
        }
    }
}

/// A field of /proc/self/status (`VmRSS`, `VmHWM`), in bytes.
fn status_bytes(field: &str) -> u64 {
    let status = fs::read_to_string("/proc/self/status").unwrap_or_default();
    for line in status.lines() {
        if let Some(rest) = line.strip_prefix(field).and_then(|r| r.strip_prefix(':')) {
            let kb: u64 = rest.trim().trim_end_matches(" kB").trim().parse().unwrap_or(0);
            return kb * 1024;
        }
    }
    0
}

fn escape(s: &str) -> String {
    let mut sb = String::with_capacity(s.len());
    for c in s.encode_utf16() {
        if (0x20..0x7f).contains(&c) && c != 0x5c && c != 0x22 {
            sb.push(c as u8 as char);
        } else {
            let _ = write!(sb, "\\u{c:04x}");
        }
    }
    sb
}

fn opt(value: Option<u32>) -> String {
    match value {
        Some(v) => v.to_string(),
        None => "-".to_string(),
    }
}

fn name(name: Option<&str>) -> String {
    match name {
        Some(n) => format!("\"{}\"", escape(n)),
        None => "-".to_string(),
    }
}

/// `ElementDumper` of the oracle.
struct ElementDumper<'a> {
    store: &'a ElementStore,
    sb: String,
    units: Vec<u32>,
}

impl<'a> ElementDumper<'a> {
    fn new(store: &'a ElementStore) -> ElementDumper<'a> {
        ElementDumper {
            store,
            sb: String::new(),
            units: Vec::new(),
        }
    }

    fn line(&mut self, depth: usize, text: &str) {
        for _ in 0..depth {
            self.sb.push_str("  ");
        }
        self.sb.push_str(text);
        self.sb.push('\n');
    }

    fn dump_library(mut self, library: LibraryId) -> String {
        let store = self.store;
        let lib = &store.libraries[library as usize];
        self.units = lib.fragments.clone();
        self.line(0, &format!("library {}", lib.uri));
        self.line(
            1,
            &format!("name {} {}+{}", name(Some(&lib.name)), lib.name_offset, lib.name_length),
        );
        if lib.is_synthetic {
            self.line(1, "isSynthetic");
        }
        for (i, &unit) in lib.fragments.iter().enumerate() {
            let u = &store.units[unit as usize];
            self.line(0, &format!("fragment u{i} {}", u.source_uri));
            if u.is_origin_not_existing_file {
                self.line(1, "isOriginNotExistingFile");
            }
            for import in &u.library_imports {
                self.line(
                    1,
                    &format!("import {} {}", import.import_keyword_offset, self.directive_uri(&import.uri)),
                );
                if import.is_synthetic {
                    self.line(2, "isSynthetic");
                }
                if let Some(prefix) = &import.prefix {
                    self.line(
                        2,
                        &format!(
                            "prefix {} {} {}{}",
                            name(prefix.name.as_deref()),
                            opt(prefix.name_offset),
                            prefix.offset,
                            if prefix.is_deferred { " deferred" } else { "" }
                        ),
                    );
                }
                self.combinators(&import.combinators);
                let namespace = match import.uri {
                    DirectiveUri::WithLibrary { library, .. } => {
                        create_namespace_for_directive(store, library, &import.combinators)
                    }
                    _ => Vec::new(),
                };
                self.namespace(2, "namespace", &namespace);
            }
            for export in &u.library_exports {
                self.line(
                    1,
                    &format!("export {} {}", export.export_keyword_offset, self.directive_uri(&export.uri)),
                );
                self.combinators(&export.combinators);
            }
            for part in &u.parts {
                self.line(1, &format!("part {} {}", part.part_keyword_offset, self.directive_uri(&part.uri)));
            }
        }
        for list in [
            &lib.classes,
            &lib.enums,
            &lib.extensions,
            &lib.extension_types,
            &lib.mixins,
            &lib.type_aliases,
            &lib.top_level_functions,
            &lib.top_level_variables,
            &lib.getters,
            &lib.setters,
        ] {
            for &e in list {
                self.element(0, e);
            }
        }
        let export_namespace = lib.export_namespace.clone();
        self.namespace(0, "exportNamespace", &export_namespace);
        self.sb
    }

    fn directive_uri(&self, uri: &DirectiveUri) -> String {
        match uri {
            DirectiveUri::WithLibrary { relative_uri_string, library } => format!(
                "DirectiveUriWithLibrary \"{}\" {}",
                escape(relative_uri_string),
                self.store.libraries[*library as usize].uri
            ),
            DirectiveUri::WithUnit { relative_uri_string, unit } => format!(
                "DirectiveUriWithUnit \"{}\" {}",
                escape(relative_uri_string),
                self.store.units[*unit as usize].source_uri
            ),
            DirectiveUri::WithSource { relative_uri_string, source_uri } => {
                format!("DirectiveUriWithSource \"{}\" {}", escape(relative_uri_string), source_uri)
            }
            DirectiveUri::WithRelativeUri { relative_uri_string, relative_uri } => format!(
                "DirectiveUriWithRelativeUri \"{}\" {}",
                escape(relative_uri_string),
                relative_uri
            ),
            DirectiveUri::WithRelativeUriString { relative_uri_string } => {
                format!("DirectiveUriWithRelativeUriString \"{}\"", escape(relative_uri_string))
            }
            DirectiveUri::None => "DirectiveUri".to_string(),
        }
    }

    fn combinators(&mut self, combinators: &[NamespaceCombinator]) {
        for c in combinators {
            let names: Vec<&str> = c.names.iter().map(|n| &**n).collect();
            self.line(
                2,
                &format!(
                    "{} {}-{} {}",
                    if c.is_show { "show" } else { "hide" },
                    c.offset,
                    c.end,
                    names.join(" ")
                ),
            );
        }
    }

    fn namespace(&mut self, depth: usize, title: &str, names: &[(Rc<str>, ElementId)]) {
        let mut sorted: Vec<&(Rc<str>, ElementId)> = names.iter().collect();
        sorted.sort_by(|a, b| a.0.as_bytes().cmp(b.0.as_bytes()));
        self.line(depth, &format!("{title} {}", sorted.len()));
        for (key, element) in sorted {
            let text = format!("{} {}", escape(key), self.reference(*element));
            self.line(depth + 1, &text);
        }
    }

    fn reference(&self, element: ElementId) -> String {
        let e = self.store.element(element);
        let library = if e.library == NO_LIBRARY {
            "-".to_string()
        } else {
            self.store.libraries[e.library as usize].uri.to_string()
        };
        let fragment = self.store.fragment(e.first_fragment);
        format!(
            "{} {} {}/{}",
            e.kind.name(),
            library,
            opt(fragment.first_token_offset),
            opt(fragment.name_offset)
        )
    }

    fn unit_of(&self, fragment: FragmentId) -> String {
        let unit = self.store.fragment(fragment).unit;
        match self.units.iter().position(|u| *u == unit) {
            Some(i) => format!("u{i}"),
            None => "u-".to_string(),
        }
    }

    /// The flags `flagsForTesting` reports as set, but `isPromotable`.
    fn flag_names(&self, fragment: FragmentId) -> Vec<&'static str> {
        let f = self.store.fragment(fragment);
        let mut names: Vec<&'static str> = f
            .set_flag_names()
            .into_iter()
            .filter(|n| *n != FragmentFlag::fieldFragment_isPromotable.testing_name())
            .collect();
        // Getters that upstream overrides: field and super formal
        // parameters are final, top-level variables are static.
        let overridden = match f.kind {
            FragmentKind::FieldFormalParameter | FragmentKind::SuperFormalParameter => Some("isFinal"),
            FragmentKind::TopLevelVariable => Some("isStatic"),
            _ => None,
        };
        if let Some(flag) = overridden {
            if !names.contains(&flag) {
                names.push(flag);
            }
        }
        names.sort_by(|a, b| a.as_bytes().cmp(b.as_bytes()));
        names
    }

    fn fragments(&mut self, depth: usize, element: ElementId) {
        for fragment in self.store.element_fragments(element) {
            let f = self.store.fragment(fragment);
            let flags = self.flag_names(fragment);
            let flag_text = if flags.is_empty() {
                String::new()
            } else {
                format!(" {}", flags.join(" "))
            };
            let text = format!(
                "fragment {} {}/{}{}",
                self.unit_of(fragment),
                opt(f.first_token_offset),
                opt(f.name_offset),
                flag_text
            );
            self.line(depth, &text);
        }
    }

    fn element(&mut self, depth: usize, element: ElementId) {
        let store = self.store;
        let e = store.element(element);
        self.line(depth, &format!("{} {}", e.kind.name(), name(e.name.as_deref())));
        let d = depth + 1;
        self.fragments(d, element);
        match e.kind {
            ElementKind::CLASS | ElementKind::ENUM | ElementKind::EXTENSION_TYPE | ElementKind::MIXIN => {
                self.type_parameters(d, element);
                let members = e.members();
                for list in [&members.fields, &members.getters, &members.setters] {
                    for &m in list {
                        self.element(d, m);
                    }
                }
                for &c in &members.constructors {
                    let first = store.element(c).first_fragment;
                    if store.fragment(first).has_flag(FragmentFlag::constructorFragment_isOriginMixinApplication) {
                        continue;
                    }
                    self.element(d, c);
                }
                for &m in &members.methods {
                    self.element(d, m);
                }
            }
            ElementKind::EXTENSION => {
                self.type_parameters(d, element);
                let members = e.members();
                for list in [&members.fields, &members.getters, &members.setters, &members.methods] {
                    for &m in list {
                        self.element(d, m);
                    }
                }
            }
            ElementKind::TYPE_ALIAS => self.type_parameters(d, element),
            ElementKind::GETTER | ElementKind::SETTER => {
                if e.is_extension_type_member {
                    self.line(d, "isExtensionTypeMember");
                }
                let variable = store.element(e.variable);
                self.line(
                    d,
                    &format!("variable {} {}", variable.kind.name(), name(variable.name.as_deref())),
                );
                self.executable(d, element);
            }
            ElementKind::CONSTRUCTOR | ElementKind::METHOD | ElementKind::FUNCTION => {
                if e.is_extension_type_member {
                    self.line(d, "isExtensionTypeMember");
                }
                self.executable(d, element);
            }
            ElementKind::FIELD | ElementKind::TOP_LEVEL_VARIABLE => {
                if e.getter != NO_ELEMENT {
                    let text = format!("getter {}", name(store.element(e.getter).name.as_deref()));
                    self.line(d, &text);
                }
                if e.setter != NO_ELEMENT {
                    let text = format!("setter {}", name(store.element(e.setter).name.as_deref()));
                    self.line(d, &text);
                }
            }
            other => panic!("StateError: {other:?}"),
        }
    }

    fn executable(&mut self, depth: usize, element: ElementId) {
        self.type_parameters(depth, element);
        self.formal_parameters(depth, element);
    }

    fn type_parameters(&mut self, depth: usize, element: ElementId) {
        for parameter in self.store.type_parameters(element) {
            let e = self.store.element(parameter);
            self.line(depth, &format!("{} {}", e.kind.name(), name(e.name.as_deref())));
            self.fragments(depth + 1, parameter);
        }
    }

    fn formal_parameters(&mut self, depth: usize, element: ElementId) {
        for parameter in self.store.formal_parameters(element) {
            let store = self.store;
            let e = store.element(parameter);
            self.line(depth, &format!("{} {}", e.kind.name(), name(e.name.as_deref())));
            let d = depth + 1;
            self.fragments(d, parameter);
            let first = store.fragment(e.first_fragment);
            let kind = match first.parameter_kind {
                ParameterKind::REQUIRED => "requiredPositional",
                ParameterKind::POSITIONAL => "optionalPositional",
                ParameterKind::NAMED_REQUIRED => "requiredNamed",
                ParameterKind::NAMED => "optionalNamed",
            };
            self.line(d, &format!("kind {kind}"));
            match store.formal_parameter_element_class(parameter) {
                FragmentKind::FieldFormalParameter => {
                    self.line(d, "fieldFormal");
                    if let Some(private_name) = &first.private_name {
                        self.line(d, &format!("privateName {}", name(Some(private_name))));
                    }
                }
                FragmentKind::SuperFormalParameter => self.line(d, "superFormal"),
                _ => {}
            }
            // `defaultValueCode`: the first fragment's default value; for a
            // super formal parameter, only its own, unless it is required.
            let is_super = store.formal_parameter_element_class(parameter) == FragmentKind::SuperFormalParameter;
            let is_required = matches!(first.parameter_kind, ParameterKind::REQUIRED | ParameterKind::NAMED_REQUIRED);
            let code = if is_super && is_required { None } else { first.default_value_code.as_ref() };
            if let Some(code) = code {
                self.line(d, &format!("default {}", name(Some(code))));
            }
        }
    }
}
