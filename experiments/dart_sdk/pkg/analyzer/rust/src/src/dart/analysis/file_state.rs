// Port of lib/src/dart/analysis/file_state.dart: the files of an analysis,
// their URIs, their unlinked directives (`serializeAstUnlinked2`'s
// directives) and their kinds (library or part), and how a directive's URI
// selects a file.
//
// Upstream keeps the state of a file system that changes; here the files
// are read once. A file is parsed when it is first asked for, and its tree
// stays with it until the linker takes it (`takeParsedUnitForLinking`).
// URIs are resolved by the source factory upstream builds from the SDK and
// the package config (`DartUriResolver`, `PackageMapUriResolver`,
// `ResourceUriResolver`); here `get_file_for_uri` does the same with the
// `FolderBasedDartSdk` and the `Packages`. No variables are declared, so a
// configuration (`if (dart.library.io)`) never selects its URI, as with
// the analyzer's default `DeclaredVariables`. Augmentation imports and doc
// imports are not ported.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::rc::Rc;

use crate::dart::analysis::utilities::{ParseStringResult, parse_string};
use crate::src::context::packages::Packages;
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::{Ast, NO_NODE, NodeId};
use crate::src::dart::sdk::sdk::FolderBasedDartSdk;
use crate::src::utilities::uri_cache::{Uri, resolve_relative};
use fe_analyzer_shared::scanner::token::NO_TOKEN;

pub type FileId = u32;

/// `UnlinkedCombinator`.
#[derive(Clone, Debug)]
pub struct UnlinkedCombinator {
    pub keyword_offset: i32,
    pub end_offset: i32,
    pub is_show: bool,
    pub names: Vec<Rc<str>>,
}

/// `UnlinkedNamespaceDirectiveConfiguration`.
#[derive(Clone, Debug)]
pub struct UnlinkedConfiguration {
    pub name: String,
    pub value: String,
    pub uri: Option<String>,
}

/// `UnlinkedLibraryImportPrefix`, with the `prefixOffset` of the
/// informative data (`prefixName.offsetIfNotEmpty`).
#[derive(Clone, Debug)]
pub struct UnlinkedImportPrefix {
    pub deferred_offset: Option<i32>,
    pub name_offset: i32,
    /// `UnlinkedLibraryImportPrefixName`: the name, unless synthetic.
    pub name: Option<(Rc<str>, i32)>,
    pub info_prefix_offset: Option<i32>,
}

/// `UnlinkedLibraryImportDirective`.
#[derive(Clone, Debug)]
pub struct UnlinkedImport {
    pub combinators: Vec<UnlinkedCombinator>,
    pub configurations: Vec<UnlinkedConfiguration>,
    pub import_keyword_offset: i32,
    pub is_synthetic_dart_core: bool,
    pub prefix: Option<UnlinkedImportPrefix>,
    pub uri: Option<String>,
}

/// `UnlinkedLibraryExportDirective`.
#[derive(Clone, Debug)]
pub struct UnlinkedExport {
    pub combinators: Vec<UnlinkedCombinator>,
    pub configurations: Vec<UnlinkedConfiguration>,
    pub export_keyword_offset: i32,
    pub uri: Option<String>,
}

/// `UnlinkedPartDirective`.
#[derive(Clone, Debug)]
pub struct UnlinkedPart {
    pub part_keyword_offset: i32,
    pub uri: Option<String>,
}

/// The directives of `UnlinkedUnit`.
#[derive(Clone, Debug, Default)]
pub struct UnlinkedUnit {
    /// `libraryDirective`, with its name (`None` when it has none).
    pub library_directive: Option<Option<String>>,
    pub part_of_name_directive: Option<String>,
    /// `partOfUriDirective`, with its URI string.
    pub part_of_uri_directive: Option<Option<String>>,
    pub imports: Vec<UnlinkedImport>,
    pub exports: Vec<UnlinkedExport>,
    pub parts: Vec<UnlinkedPart>,
    pub has_dart_core_import: bool,
    pub is_dart_core: bool,
}

/// `FileKind`.
#[derive(Clone, Debug)]
pub enum FileKind {
    /// `LibraryFileKind`, with the name of its library directive.
    Library { name: Option<String> },
    /// `PartOfNameFileKind`.
    PartOfName { name: String },
    /// `PartOfUriKnownFileKind`.
    PartOfUriKnown { uri_file: FileId },
    /// `PartOfUriUnknownFileKind`.
    PartOfUriUnknown,
}

/// `DirectiveUri` of file_state.dart: what a directive's URI string selects.
#[derive(Clone, Debug)]
pub enum DirectiveUriState {
    /// `DirectiveUriWithoutString`.
    WithoutString,
    /// `DirectiveUriWithString`: the string is not a URI.
    WithString { relative_uri_str: Rc<str> },
    /// `DirectiveUriWithUri`: no file has the URI.
    WithUri { relative_uri_str: Rc<str>, relative_uri: Rc<str> },
    /// `DirectiveUriWithFile`.
    WithFile { relative_uri_str: Rc<str>, file: FileId },
}

/// `FileState`.
pub struct FileState {
    pub path: PathBuf,
    pub uri: Rc<str>,
    pub exists: bool,
    pub unlinked: UnlinkedUnit,
    pub kind: FileKind,
    /// The parsed unit, until the linker takes it.
    pub parsed: Option<ParseStringResult>,
}

/// `FileSystemState`.
pub struct FileSystemState {
    pub sdk: FolderBasedDartSdk,
    pub packages: Packages,
    pub files: Vec<FileState>,
    path_to_file: HashMap<PathBuf, FileId>,
    uri_to_file: HashMap<Rc<str>, FileId>,
}

impl FileSystemState {
    pub fn new(sdk: FolderBasedDartSdk, packages: Packages) -> FileSystemState {
        FileSystemState {
            sdk,
            packages,
            files: Vec::new(),
            path_to_file: HashMap::new(),
            uri_to_file: HashMap::new(),
        }
    }

    pub fn file(&self, id: FileId) -> &FileState {
        &self.files[id as usize]
    }

    /// The source factory's `forUri2(uri)?.fullName`: the path of the file
    /// [uri] names, or `None` when no resolver understands it.
    fn path_for_uri(&self, uri: &Uri) -> Option<PathBuf> {
        match uri.scheme.as_str() {
            "dart" => self.sdk.map_dart_uri(&uri.path),
            "package" => {
                let slash = uri.path.find('/')?;
                let package = self.packages.get(&uri.path[..slash])?;
                Some(package.lib_folder.join(&uri.path[slash + 1..]))
            }
            "file" => Some(PathBuf::from(&uri.path)),
            _ => None,
        }
    }

    /// The source factory's `pathToUri`: `dart:` for a file of the SDK,
    /// `package:` for a file in the `lib` of a package, `file:` otherwise.
    pub fn path_to_uri(&self, path: &Path) -> Rc<str> {
        if let Some(uri) = self.sdk.path_to_uri(path) {
            return Rc::from(uri);
        }
        for package in &self.packages.packages {
            if let Ok(relative) = path.strip_prefix(&package.lib_folder) {
                return Rc::from(format!("package:{}/{}", package.name, relative.display()));
            }
        }
        Rc::from(format!("file://{}", path.display()))
    }

    /// `getFileForUri`.
    pub fn get_file_for_uri(&mut self, uri: &str) -> Option<FileId> {
        if let Some(&file) = self.uri_to_file.get(uri) {
            return Some(file);
        }
        let parsed = Uri::try_parse(uri)?;
        let path = self.path_for_uri(&parsed)?;
        if let Some(&file) = self.path_to_file.get(&path) {
            return Some(file);
        }
        let canonical = self.path_to_uri(&path);
        Some(self.new_file(path, canonical))
    }

    /// `getFileForPath`.
    pub fn get_file_for_path(&mut self, path: &Path) -> FileId {
        if let Some(&file) = self.path_to_file.get(path) {
            return file;
        }
        let uri = self.path_to_uri(path);
        self.new_file(path.to_path_buf(), uri)
    }

    fn new_file(&mut self, path: PathBuf, uri: Rc<str>) -> FileId {
        let id = self.files.len() as FileId;
        let (exists, content) = match std::fs::read(&path) {
            Ok(bytes) => (true, String::from_utf8_lossy(&bytes).into_owned()),
            Err(_) => (false, String::new()),
        };
        let units: Vec<u16> = content.encode_utf16().collect();
        let parsed = parse_string(Rc::from(units), None, path.to_str());
        let unlinked = serialize_ast_unlinked2(&parsed, &uri);
        self.path_to_file.insert(path.clone(), id);
        self.uri_to_file.insert(uri.clone(), id);
        self.files.push(FileState {
            path,
            uri,
            exists,
            unlinked,
            kind: FileKind::Library { name: None },
            parsed: Some(parsed),
        });
        self.update_kind(id);
        id
    }

    /// `_updateKind`.
    fn update_kind(&mut self, id: FileId) {
        let unlinked = &self.files[id as usize].unlinked;
        let kind = if let Some(name) = &unlinked.library_directive {
            FileKind::Library { name: name.clone() }
        } else if let Some(name) = &unlinked.part_of_name_directive {
            FileKind::PartOfName { name: name.clone() }
        } else if let Some(uri) = unlinked.part_of_uri_directive.clone() {
            match self.file_for_relative_uri(id, uri.as_deref()) {
                Some(uri_file) => FileKind::PartOfUriKnown { uri_file },
                None => FileKind::PartOfUriUnknown,
            }
        } else {
            FileKind::Library { name: None }
        };
        self.files[id as usize].kind = kind;
    }

    /// `_fileForRelativeUri`.
    fn file_for_relative_uri(&mut self, id: FileId, relative_uri_str: Option<&str>) -> Option<FileId> {
        let relative = Uri::try_parse(relative_uri_str?)?;
        let absolute = resolve_relative(&self.files[id as usize].uri, &relative);
        self.get_file_for_uri(&absolute)
    }

    /// `_buildDirectiveUri`.
    pub fn build_directive_uri(&mut self, container: FileId, relative_uri_str: Option<&str>) -> DirectiveUriState {
        let Some(relative_uri_str) = relative_uri_str else {
            return DirectiveUriState::WithoutString;
        };
        let Some(relative_uri) = Uri::try_parse(relative_uri_str) else {
            return DirectiveUriState::WithString { relative_uri_str: Rc::from(relative_uri_str) };
        };
        let absolute = resolve_relative(&self.files[container as usize].uri, &relative_uri);
        match self.get_file_for_uri(&absolute) {
            None => DirectiveUriState::WithUri {
                relative_uri_str: Rc::from(relative_uri_str),
                relative_uri: Rc::from(relative_uri.to_string()),
            },
            Some(file) => DirectiveUriState::WithFile { relative_uri_str: Rc::from(relative_uri_str), file },
        }
    }

    /// `_buildConfigurableDirectiveUris(...).selected`: no configuration is
    /// selected, as no variable is declared, so the primary URI. The URIs
    /// of the configurations are built anyway, as upstream does, which
    /// creates their files.
    pub fn selected_uri(
        &mut self,
        container: FileId,
        uri: Option<&str>,
        configurations: &[UnlinkedConfiguration],
    ) -> DirectiveUriState {
        let primary = self.build_directive_uri(container, uri);
        for configuration in configurations {
            self.build_directive_uri(container, configuration.uri.as_deref());
        }
        primary
    }

    /// `PartFileKind.isPartOf`.
    pub fn is_part_of(&self, part: FileId, container: FileId) -> bool {
        match &self.file(part).kind {
            FileKind::PartOfName { name } => match &self.file(container).kind {
                FileKind::Library { name: library_name } => library_name.as_deref() == Some(name.as_str()),
                _ => false,
            },
            FileKind::PartOfUriKnown { uri_file } => *uri_file == container,
            _ => false,
        }
    }

    /// Whether [file] is a library (`kind is LibraryFileKind`).
    pub fn is_library(&self, file: FileId) -> bool {
        matches!(self.file(file).kind, FileKind::Library { .. })
    }

    /// `takeParsedUnitForLinking() ?? parse(...)`.
    pub fn take_parsed(&mut self, file: FileId) -> ParseStringResult {
        if let Some(parsed) = self.files[file as usize].parsed.take() {
            return parsed;
        }
        let content = std::fs::read(&self.files[file as usize].path)
            .map(|b| String::from_utf8_lossy(&b).into_owned())
            .unwrap_or_default();
        let units: Vec<u16> = content.encode_utf16().collect();
        parse_string(Rc::from(units), None, self.files[file as usize].path.to_str())
    }
}

/// `StringLiteral.stringValue`.
pub fn string_value(ast: Ast<'_>, node: NodeId) -> Option<String> {
    fn append(ast: Ast<'_>, node: NodeId, buffer: &mut Vec<u16>) -> bool {
        match ast.node(node) {
            AstNodeImpl::SimpleStringLiteralImpl(s) => {
                buffer.extend_from_slice(&s.value);
                true
            }
            AstNodeImpl::AdjacentStringsImpl(a) => a.strings.iter().all(|s| append(ast, *s, buffer)),
            _ => false,
        }
    }
    if node == NO_NODE {
        return None;
    }
    let mut buffer = Vec::new();
    if append(ast, node, &mut buffer) {
        Some(String::from_utf16_lossy(&buffer))
    } else {
        None
    }
}

/// The joined lexemes of a `DottedName` (`tokens.map((e) => e.lexeme).join()`).
pub fn dotted_name(ast: Ast<'_>, node: NodeId) -> String {
    let mut name = String::new();
    for &token in &ast.node(node).as_dotted_name_impl().tokens {
        name.push_str(&ast.tokens.lexeme_string(token));
    }
    name
}

/// `Token.offsetIfNotEmpty`.
pub fn offset_if_not_empty(ast: Ast<'_>, token: fe_analyzer_shared::scanner::token::TokenId) -> Option<i32> {
    if ast.tokens.lexeme(token).is_empty() {
        None
    } else {
        Some(ast.tokens.offset(token))
    }
}

fn serialize_combinators(ast: Ast<'_>, combinators: &[NodeId]) -> Vec<UnlinkedCombinator> {
    combinators
        .iter()
        .map(|&combinator| {
            let (is_show, keyword, names) = match ast.node(combinator) {
                AstNodeImpl::ShowCombinatorImpl(c) => (true, c.keyword, &c.names),
                AstNodeImpl::HideCombinatorImpl(c) => (false, c.keyword, &c.names),
                other => panic!("{} is not a Combinator", other.runtime_type()),
            };
            UnlinkedCombinator {
                keyword_offset: ast.tokens.offset(keyword),
                end_offset: ast.end(combinator),
                is_show,
                names: names
                    .iter()
                    .map(|&n| {
                        let name = ast.node(n).as_combinator_name_impl().name;
                        Rc::from(ast.tokens.lexeme_string(name))
                    })
                    .collect(),
            }
        })
        .collect()
}

fn serialize_configurations(ast: Ast<'_>, configurations: &[NodeId]) -> Vec<UnlinkedConfiguration> {
    configurations
        .iter()
        .map(|&c| {
            let configuration = ast.node(c).as_configuration_impl();
            UnlinkedConfiguration {
                name: dotted_name(ast, configuration.name),
                value: string_value(ast, configuration.value).unwrap_or_default(),
                uri: string_value(ast, configuration.uri),
            }
        })
        .collect()
}

/// The directives of `FileState.serializeAstUnlinked2`.
fn serialize_ast_unlinked2(parsed: &ParseStringResult, uri: &str) -> UnlinkedUnit {
    let ast = Ast::new(&parsed.ast, &parsed.tokens);
    let unit = ast.node(parsed.unit).as_compilation_unit_impl();
    let mut result = UnlinkedUnit {
        is_dart_core: uri == "dart:core",
        ..UnlinkedUnit::default()
    };
    for &directive in &unit.directives {
        match ast.node(directive) {
            AstNodeImpl::ExportDirectiveImpl(d) => result.exports.push(UnlinkedExport {
                combinators: serialize_combinators(ast, &d.combinators),
                configurations: serialize_configurations(ast, &d.configurations),
                export_keyword_offset: ast.tokens.offset(d.export_keyword),
                uri: string_value(ast, d.uri),
            }),
            AstNodeImpl::ImportDirectiveImpl(d) => {
                let prefix = if d.prefix_name != NO_TOKEN {
                    let synthetic = ast.tokens.is_synthetic(d.prefix_name);
                    Some(UnlinkedImportPrefix {
                        deferred_offset: if d.deferred_keyword != NO_TOKEN {
                            Some(ast.tokens.offset(d.deferred_keyword))
                        } else {
                            None
                        },
                        name_offset: ast.tokens.offset(d.prefix_name),
                        name: if synthetic {
                            None
                        } else {
                            Some((
                                Rc::from(ast.tokens.lexeme_string(d.prefix_name)),
                                ast.tokens.offset(d.prefix_name),
                            ))
                        },
                        info_prefix_offset: offset_if_not_empty(ast, d.prefix_name),
                    })
                } else {
                    None
                };
                let import = UnlinkedImport {
                    combinators: serialize_combinators(ast, &d.combinators),
                    configurations: serialize_configurations(ast, &d.configurations),
                    import_keyword_offset: ast.tokens.offset(d.import_keyword),
                    is_synthetic_dart_core: false,
                    prefix,
                    uri: string_value(ast, d.uri),
                };
                if import.uri.as_deref() == Some("dart:core") {
                    result.has_dart_core_import = true;
                }
                result.imports.push(import);
            }
            AstNodeImpl::LibraryDirectiveImpl(d) => {
                if result.library_directive.is_none() {
                    result.library_directive =
                        Some(if d.name != NO_NODE { Some(dotted_name(ast, d.name)) } else { None });
                }
            }
            AstNodeImpl::PartDirectiveImpl(d) => result.parts.push(UnlinkedPart {
                part_keyword_offset: ast.tokens.offset(d.part_keyword),
                uri: string_value(ast, d.uri),
            }),
            AstNodeImpl::PartOfDirectiveImpl(d) => {
                if d.library_name != NO_NODE {
                    if result.part_of_name_directive.is_none() {
                        result.part_of_name_directive = Some(dotted_name(ast, d.library_name));
                    }
                } else if d.uri != NO_NODE {
                    if result.part_of_uri_directive.is_none() {
                        result.part_of_uri_directive = Some(string_value(ast, d.uri));
                    }
                }
            }
            _ => {}
        }
    }
    result
}
