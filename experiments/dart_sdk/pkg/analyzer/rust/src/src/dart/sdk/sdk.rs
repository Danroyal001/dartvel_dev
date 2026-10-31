// Port of lib/src/dart/sdk/sdk.dart (`FolderBasedDartSdk`: the library map
// read from the SDK's `libraries.dart`, and mapping `dart:` URIs to files
// and back) and of the library map reader of lib/src/generated/sdk.dart
// (`SdkLibrariesReader_LibraryBuilder`).

use std::path::{Path, PathBuf};
use std::rc::Rc;

use crate::dart::analysis::utilities::parse_string;
use crate::dart::ast::visitor_g::RecursiveAstVisitor2;
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{Ast, NodeId};

/// `SdkLibraryImpl`: the short name (`dart:core`) and the path of the
/// defining file relative to the SDK's `lib` directory.
#[derive(Clone, Debug)]
pub struct SdkLibrary {
    pub short_name: Rc<str>,
    pub path: String,
}

/// `FolderBasedDartSdk`.
#[derive(Clone, Debug)]
pub struct FolderBasedDartSdk {
    /// `libraryDirectory`.
    pub library_directory: PathBuf,
    /// `libraryMap.sdkLibraries`, in the order `libraries.dart` lists them
    /// (a repeated name keeps its first position and its last value, as a
    /// Dart map does).
    pub sdk_libraries: Vec<SdkLibrary>,
}

impl FolderBasedDartSdk {
    pub fn new(sdk_directory: &Path) -> FolderBasedDartSdk {
        let library_directory = sdk_directory.join("lib");
        let mut sdk_libraries = Vec::new();
        // `_libraryMapLocations`.
        for file in [
            library_directory.join("_internal/sdk_library_metadata/lib/libraries.dart"),
            library_directory.join("_internal/libraries.dart"),
        ] {
            if let Ok(contents) = std::fs::read_to_string(&file) {
                sdk_libraries = read_libraries(&contents, &file);
                break;
            }
        }
        FolderBasedDartSdk { library_directory, sdk_libraries }
    }

    /// `getSdkLibrary`.
    pub fn get_sdk_library(&self, dart_uri: &str) -> Option<&SdkLibrary> {
        self.sdk_libraries.iter().find(|l| &*l.short_name == dart_uri)
    }

    /// `internalMapDartUri`, given the path of a `dart:` URI (`core` or
    /// `core/bool.dart`): the file, or `None` for an unknown library.
    pub fn map_dart_uri(&self, uri_path: &str) -> Option<PathBuf> {
        let (library_name, relative_path) = match uri_path.find('/') {
            Some(index) => (&uri_path[..index], &uri_path[index + 1..]),
            None => (uri_path, ""),
        };
        let library = self.get_sdk_library(&format!("dart:{library_name}"))?;
        let src_path = if relative_path.is_empty() {
            library.path.clone()
        } else {
            let index = library.path.rfind('/')?;
            format!("{}{}", &library.path[..index + 1], relative_path)
        };
        Some(self.library_directory.join(src_path))
    }

    /// `pathToUri` (`_getPath`): `dart:core` for the defining file of a
    /// library, `dart:core/bool.dart` for another file in its directory.
    pub fn path_to_uri(&self, path: &Path) -> Option<String> {
        let relative = path.strip_prefix(&self.library_directory).ok()?;
        let relative = relative.to_str()?;
        for library in &self.sdk_libraries {
            if library.path == relative {
                return Some(library.short_name.to_string());
            }
        }
        for library in &self.sdk_libraries {
            let Some(index) = library.path.rfind('/') else {
                continue;
            };
            let prefix = &library.path[..index + 1];
            if let Some(rest) = relative.strip_prefix(prefix) {
                return Some(format!("{}/{}", library.short_name, rest));
            }
        }
        None
    }
}

/// `SdkLibrariesReader.readFromFile`.
fn read_libraries(contents: &str, file: &Path) -> Vec<SdkLibrary> {
    let units: Vec<u16> = contents.encode_utf16().collect();
    let result = parse_string(Rc::from(units), None, file.to_str());
    let mut builder = LibraryBuilder { libraries: Vec::new() };
    if result.errors.is_empty() {
        let ast = Ast::new(&result.ast, &result.tokens);
        ast.accept2(result.unit, &mut builder);
    }
    builder.libraries
}

/// `SdkLibrariesReader_LibraryBuilder`.
struct LibraryBuilder {
    libraries: Vec<SdkLibrary>,
}

fn string_value(ast: Ast<'_>, node: NodeId) -> Option<String> {
    match ast.node(node) {
        AstNodeImpl::SimpleStringLiteralImpl(s) => Some(String::from_utf16_lossy(&s.value)),
        _ => None,
    }
}

impl RecursiveAstVisitor2 for LibraryBuilder {
    fn visit_map_literal_entry(&mut self, ast: Ast<'_>, node: NodeId) -> Option<()> {
        let entry = ast.node(node).as_map_literal_entry_impl();
        let key = string_value(ast, entry.key2).expect("the key is a SimpleStringLiteral");
        let library_name = format!("dart:{key}");
        if let AstNodeImpl::ConstructorInvocationImpl(value) = ast.node(entry.value2) {
            let mut path = None;
            let arguments = &ast.node(value.argument_list).as_argument_list_impl().arguments2;
            for &argument in arguments {
                if let Some(value) = string_value(ast, argument) {
                    path = Some(value);
                } else if let AstNodeImpl::NamedArgumentImpl(named) = ast.node(argument) {
                    let name = ast.tokens.lexeme_string(named.name);
                    if &*name == "dart2jsPath" {
                        if let Some(value) = string_value(ast, named.argument_expression2) {
                            path = Some(value);
                        }
                    }
                }
            }
            // `late String path`: an entry without one would throw when
            // read; the SDK's file always has one.
            let library = SdkLibrary {
                short_name: Rc::from(library_name.as_str()),
                path: path.unwrap_or_default(),
            };
            // `LibraryMap.setLibrary`: a map keyed by the short name.
            match self.libraries.iter_mut().find(|l| l.short_name == library.short_name) {
                Some(existing) => *existing = library,
                None => self.libraries.push(library),
            }
        }
        None
    }
}

recursive_ast_visitor2!(LibraryBuilder, ());
