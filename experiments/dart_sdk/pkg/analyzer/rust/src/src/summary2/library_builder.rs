// Port of lib/src/summary2/library_builder.dart: `LibraryBuilder`, which
// creates a library's element and its fragments, builds its directives and
// elements, and keeps its export scope while the linker computes it.
//
// The units' parsed trees are dropped once the elements are built: what the
// element model keeps of them (offsets, default values) is copied into the
// fragments.

use std::collections::HashSet;
use std::rc::Rc;

use crate::dart::analysis::features::Feature;
use crate::dart::analysis::utilities::ParseStringResult;
use crate::src::dart::analysis::file_state::{DirectiveUriState, FileId, FileSystemState, UnlinkedCombinator};
use crate::src::dart::ast::ast::AstNodeImpl;
use crate::src::dart::ast::ast_store::Ast;
use crate::src::dart::element::element::{
    DYNAMIC_ELEMENT, DirectiveUri, ElementKind, ElementStore, FragmentFlag, FragmentImpl, FragmentKind,
    LibraryElementImpl, LibraryExportImpl, LibraryFragmentImpl, LibraryId, LibraryImportImpl, NEVER_ELEMENT,
    NamespaceCombinator, PartIncludeImpl, PrefixFragmentImpl, UnitId,
};
use crate::src::summary2::element_builder::{ElementBuilder, FragmentBuilder, LibraryFragments};
use crate::src::summary2::export::{Export, ExportScope};

/// `LinkingUnit`: a unit's tree and its fragment.
pub struct LinkingUnit {
    pub parsed: Option<ParseStringResult>,
    pub fragment: UnitId,
}

/// `LibraryBuilder`.
pub struct LibraryBuilder {
    pub file: FileId,
    pub uri: Rc<str>,
    pub element: LibraryId,
    pub units: Vec<LinkingUnit>,
    /// `_includedFiles`.
    included_files: HashSet<FileId>,
    pub fragments: LibraryFragments,
    /// `exportScope`.
    pub export_scope: ExportScope,
    /// `exports`: the `export` directives that export this library.
    pub exports: Vec<Export>,
}

/// `buildNamespaceCombinators`.
fn build_namespace_combinators(combinators: &[UnlinkedCombinator]) -> Vec<NamespaceCombinator> {
    combinators
        .iter()
        .map(|c| NamespaceCombinator {
            is_show: c.is_show,
            offset: c.keyword_offset,
            end: c.end_offset,
            names: c.names.clone(),
        })
        .collect()
}

/// The `DirectiveUri` of the element model for an import or an export:
/// `buildLibraryImportUri` and `_buildLibraryExport`.
fn library_directive_uri(
    fs: &FileSystemState,
    state: DirectiveUriState,
    library_of_file: &dyn Fn(FileId) -> Option<LibraryId>,
) -> DirectiveUri {
    match state {
        DirectiveUriState::WithFile { relative_uri_str, file } => match library_of_file(file) {
            Some(library) if fs.is_library(file) => DirectiveUri::WithLibrary {
                relative_uri_string: relative_uri_str,
                library,
            },
            _ => DirectiveUri::WithSource {
                relative_uri_string: relative_uri_str,
                source_uri: fs.file(file).uri.clone(),
            },
        },
        DirectiveUriState::WithUri { relative_uri_str, relative_uri } => DirectiveUri::WithRelativeUri {
            relative_uri_string: relative_uri_str,
            relative_uri,
        },
        DirectiveUriState::WithString { relative_uri_str } => DirectiveUri::WithRelativeUriString {
            relative_uri_string: relative_uri_str,
        },
        DirectiveUriState::WithoutString => DirectiveUri::None,
    }
}

impl LibraryBuilder {
    /// `LibraryBuilder.build`: the library's element and its defining
    /// unit's fragment.
    pub fn build(store: &mut ElementStore, fs: &mut FileSystemState, file: FileId) -> LibraryBuilder {
        let parsed = fs.take_parsed(file);
        let ast = Ast::new(&parsed.ast, &parsed.tokens);
        let unit_node = ast.node(parsed.unit).as_compilation_unit_impl();

        let mut name = String::new();
        let mut name_offset = -1;
        let mut name_length = 0;
        for &directive in &unit_node.directives {
            if let AstNodeImpl::LibraryDirectiveImpl(d) = ast.node(directive) {
                if d.name != crate::src::dart::ast::ast_store::NO_NODE {
                    for &token in &ast.node(d.name).as_dotted_name_impl().tokens {
                        name.push_str(&ast.tokens.lexeme_string(token));
                    }
                    name_offset = ast.offset(d.name);
                    name_length = ast.length(d.name);
                }
                break;
            }
        }

        let uri = fs.file(file).uri.clone();
        let library_id = store.libraries.len() as LibraryId;
        let mut library = LibraryElementImpl::new(uri.clone(), Rc::from(name), name_offset, name_length);
        let exists = fs.file(file).exists;
        if !exists {
            library.is_synthetic = true;
        }
        let unit = store.units.len() as UnitId;
        let mut fragment = LibraryFragmentImpl::new(library_id, uri.clone());
        fragment.is_origin_not_existing_file = !exists;
        store.units.push(fragment);
        library.fragments.push(unit);
        store.libraries.push(library);

        let mut included_files = HashSet::new();
        included_files.insert(file);
        LibraryBuilder {
            file,
            uri,
            element: library_id,
            units: vec![LinkingUnit { parsed: Some(parsed), fragment: unit }],
            included_files,
            fragments: LibraryFragments::default(),
            export_scope: ExportScope::default(),
            exports: Vec::new(),
        }
    }

    /// `buildElements`: builds elements for declarations in the library
    /// units, and adds top-level declarations to the local scope, for
    /// combining into export scopes.
    pub fn build_elements(
        &mut self,
        store: &mut ElementStore,
        fs: &mut FileSystemState,
        library_of_file: &dyn Fn(FileId) -> Option<LibraryId>,
    ) {
        let defining_unit = self.units[0].fragment;
        self.build_directives(store, fs, self.file, defining_unit, true, library_of_file);

        // `_libraryBuilder.element.featureSet`: the defining unit's.
        let (primary_constructors, private_named_parameters) = {
            let parsed = self.units[0].parsed.as_ref().unwrap();
            let feature_set = &parsed.ast.node(parsed.unit).as_compilation_unit_impl().feature_set;
            (
                feature_set.is_enabled(Feature::primary_constructors),
                feature_set.is_enabled(Feature::private_named_parameters),
            )
        };
        for linking_unit in &self.units {
            let parsed = linking_unit.parsed.as_ref().unwrap();
            let ast = Ast::new(&parsed.ast, &parsed.tokens);
            let mut builder = FragmentBuilder::new(store, &mut self.fragments, ast, linking_unit.fragment);
            builder.primary_constructors = primary_constructors;
            builder.private_named_parameters = private_named_parameters;
            builder.build_declaration_fragments(parsed.unit);
        }

        let units: Vec<UnitId> = self.units.iter().map(|u| u.fragment).collect();
        let is_dart_core = &*self.uri == "dart:core";
        ElementBuilder::new(store, &mut self.fragments, self.element, &units, is_dart_core).build_elements();

        // `_declareDartCoreDynamicNever`: these elements are implicitly
        // declared in `dart:core`.
        if is_dart_core {
            self.fragments.declare(store, DYNAMIC_ELEMENT);
            self.fragments.declare(store, NEVER_ELEMENT);
        }

        // The trees are not needed any more.
        for unit in &mut self.units {
            unit.parsed = None;
        }
    }

    /// `_buildDirectives`: the directives of [file], whose fragment is
    /// [container_unit], and recursively of the parts it includes.
    fn build_directives(
        &mut self,
        store: &mut ElementStore,
        fs: &mut FileSystemState,
        file: FileId,
        container_unit: UnitId,
        is_library: bool,
        library_of_file: &dyn Fn(FileId) -> Option<LibraryId>,
    ) {
        let unlinked = fs.file(file).unlinked.clone();

        let mut exports = Vec::new();
        for export in &unlinked.exports {
            let state = fs.selected_uri(file, export.uri.as_deref(), &export.configurations);
            exports.push(LibraryExportImpl {
                combinators: build_namespace_combinators(&export.combinators),
                export_keyword_offset: export.export_keyword_offset,
                uri: library_directive_uri(fs, state, library_of_file),
            });
        }
        store.units[container_unit as usize].library_exports = exports;

        let mut imports = Vec::new();
        for import in &unlinked.imports {
            let state = fs.selected_uri(file, import.uri.as_deref(), &import.configurations);
            let prefix = import.prefix.as_ref().map(|p| PrefixFragmentImpl {
                name: p.name.as_ref().map(|(n, _)| n.clone()),
                name_offset: p.info_prefix_offset.map(|o| o as u32),
                offset: p.info_prefix_offset.unwrap_or(import.import_keyword_offset),
                is_deferred: p.deferred_offset.is_some(),
            });
            imports.push(LibraryImportImpl {
                is_synthetic: false,
                combinators: build_namespace_combinators(&import.combinators),
                import_keyword_offset: import.import_keyword_offset,
                prefix,
                uri: library_directive_uri(fs, state, library_of_file),
            });
        }
        if is_library && !unlinked.is_dart_core && !unlinked.has_dart_core_import {
            let state = fs.build_directive_uri(file, Some("dart:core"));
            imports.push(LibraryImportImpl {
                is_synthetic: true,
                combinators: Vec::new(),
                import_keyword_offset: -1,
                prefix: None,
                uri: library_directive_uri(fs, state, library_of_file),
            });
        }
        store.units[container_unit as usize].library_imports = imports;

        let mut parts = Vec::new();
        for part in &unlinked.parts {
            let state = fs.selected_uri(file, part.uri.as_deref(), &[]);
            let uri = match state {
                DirectiveUriState::WithFile { relative_uri_str, file: part_file } => {
                    let is_part = !fs.is_library(part_file) && fs.is_part_of(part_file, file);
                    if is_part && self.included_files.insert(part_file) {
                        let parsed = fs.take_parsed(part_file);
                        let library = self.element;
                        let unit = store.units.len() as UnitId;
                        let mut fragment = LibraryFragmentImpl::new(library, fs.file(part_file).uri.clone());
                        fragment.is_origin_not_existing_file = !fs.file(part_file).exists;
                        store.units.push(fragment);
                        store.libraries[library as usize].fragments.push(unit);
                        self.units.push(LinkingUnit { parsed: Some(parsed), fragment: unit });

                        self.build_directives(store, fs, part_file, unit, false, library_of_file);

                        DirectiveUri::WithUnit {
                            relative_uri_string: relative_uri_str,
                            unit,
                        }
                    } else {
                        DirectiveUri::WithSource {
                            relative_uri_string: relative_uri_str,
                            source_uri: fs.file(part_file).uri.clone(),
                        }
                    }
                }
                DirectiveUriState::WithUri { relative_uri_str, relative_uri } => DirectiveUri::WithRelativeUri {
                    relative_uri_string: relative_uri_str,
                    relative_uri,
                },
                DirectiveUriState::WithString { relative_uri_str } => DirectiveUri::WithRelativeUriString {
                    relative_uri_string: relative_uri_str,
                },
                DirectiveUriState::WithoutString => DirectiveUri::None,
            };
            parts.push(PartIncludeImpl {
                part_keyword_offset: part.part_keyword_offset,
                uri,
            });
        }
        store.units[container_unit as usize].parts = parts;
    }

    /// `buildInitialExportScope`.
    pub fn build_initial_export_scope(&mut self) {
        self.export_scope = ExportScope::default();
        for (name, element) in &self.fragments.declared {
            if name.starts_with('_') {
                continue;
            }
            self.export_scope.declare(name.clone(), *element);
        }
    }

    /// `storeExportScope`.
    pub fn store_export_scope(&self, store: &mut ElementStore) {
        store.libraries[self.element as usize].export_namespace =
            self.export_scope.entries.iter().map(|e| (e.name.clone(), e.reference)).collect();
    }

    /// `buildClassSyntheticConstructors`.
    pub fn build_class_synthetic_constructors(&self, store: &mut ElementStore) {
        for class in store.libraries[self.element as usize].classes.clone() {
            let first = store.element(class).first_fragment;
            if store.fragment(first).has_flag(FragmentFlag::classFragment_isMixinApplication) {
                continue;
            }
            if !store.element(class).members().constructors.is_empty() {
                continue;
            }
            let mut fragment = FragmentImpl::new(FragmentKind::Constructor, Some(Rc::from("new")));
            fragment.set_flag(FragmentFlag::constructorFragment_isOriginImplicitDefault, true);
            fragment.type_name = store.element(class).name.clone();
            fragment.unit = store.fragment(first).unit;
            fragment.enclosing_fragment = first;
            let fragment = store.add_fragment(fragment);
            store.fragment_mut(first).members_mut().constructors = vec![fragment];
            let element = store.add_element(ElementKind::CONSTRUCTOR, fragment, self.element);
            store.element_mut(class).members_mut().constructors = vec![element];
        }
    }

    /// `buildEnumSyntheticConstructors`.
    pub fn build_enum_synthetic_constructors(&self, store: &mut ElementStore) {
        for enum_ in store.libraries[self.element as usize].enums.clone() {
            let has_constructor = store.element(enum_).members().constructors.iter().any(|c| {
                let fragment = store.fragment(store.element(*c).first_fragment);
                fragment.is_generative() || store.element(*c).name.as_deref() == Some("new")
            });
            if has_constructor {
                continue;
            }
            let first = store.element(enum_).first_fragment;
            let mut fragment = FragmentImpl::new(FragmentKind::Constructor, Some(Rc::from("new")));
            fragment.set_flag(FragmentFlag::constructorFragment_isOriginImplicitDefault, true);
            fragment.set_flag(FragmentFlag::constructorFragment_isConst, true);
            fragment.type_name = store.element(enum_).name.clone();
            fragment.unit = store.fragment(first).unit;
            fragment.enclosing_fragment = first;
            let fragment = store.add_fragment(fragment);
            store.fragment_mut(first).members_mut().constructors.push(fragment);
            let element = store.add_element(ElementKind::CONSTRUCTOR, fragment, self.element);
            store.element_mut(enum_).members_mut().constructors.push(element);
        }
    }
}
