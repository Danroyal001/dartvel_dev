// Port of lib/src/summary2/link.dart: `Linker`, the steps of linking that
// build the element model from declarations: `LibraryBuilder.build` for
// every library, `_computeLibraryScopes` (`buildElements` and
// `_buildExportScopes`), and the synthetic constructors of classes and enums
// (`_buildClassSyntheticConstructors`, `_buildEnumSyntheticConstructors`).
//
// Upstream links one library cycle at a time, after the cycles it depends
// on, and reads the libraries it already linked from their summaries. Here
// every library that the inputs import or export, transitively, is linked
// at once, as one set of builders: the export scopes, computed as upstream
// computes them for a cycle, come out the same, since a library's export
// scope depends only on the libraries it exports.
//
// The steps after these (resolving types, top-level inference, constants,
// metadata) and writing summaries are not ported yet.

use std::collections::HashMap;

use crate::src::dart::analysis::file_state::{DirectiveUriState, FileId, FileSystemState};
use crate::src::dart::element::element::{DirectiveUri, ElementStore, LibraryId};
use crate::src::summary2::export::{Export, ExportLocation, build_combinators};
use crate::src::summary2::library_builder::LibraryBuilder;

/// `Linker`.
pub struct Linker {
    pub store: ElementStore,
    pub fs: FileSystemState,
    pub builders: Vec<LibraryBuilder>,
    /// The library of each linked library file.
    pub library_of_file: HashMap<FileId, LibraryId>,
    /// The builder of each library.
    builder_of_library: HashMap<LibraryId, usize>,
}

impl Linker {
    pub fn new(fs: FileSystemState) -> Linker {
        Linker {
            store: ElementStore::new(),
            fs,
            builders: Vec::new(),
            library_of_file: HashMap::new(),
            builder_of_library: HashMap::new(),
        }
    }

    /// The library of [file], linking it, and every library it depends on,
    /// first if needed. `None` when [file] is not a library.
    pub fn library_for(&mut self, file: FileId) -> Option<LibraryId> {
        if !self.fs.is_library(file) {
            return None;
        }
        if !self.library_of_file.contains_key(&file) {
            self.link(&[file]);
        }
        self.library_of_file.get(&file).copied()
    }

    /// Links the libraries [inputs] and every library they import or
    /// export, transitively, that is not linked yet.
    pub fn link(&mut self, inputs: &[FileId]) {
        let first_new = self.builders.len();

        // `LibraryBuilder.build` for every library, discovering the
        // libraries that the directives of each one (and of its parts)
        // name.
        let mut queue: Vec<FileId> = inputs.to_vec();
        let mut index = 0;
        while index < queue.len() {
            let file = queue[index];
            index += 1;
            if !self.fs.is_library(file) || self.library_of_file.contains_key(&file) {
                continue;
            }
            let builder = LibraryBuilder::build(&mut self.store, &mut self.fs, file);
            self.library_of_file.insert(file, builder.element);
            self.builder_of_library.insert(builder.element, self.builders.len());
            self.builders.push(builder);
            queue.extend(self.dependencies(file));
        }

        // `_computeLibraryScopes`.
        for i in first_new..self.builders.len() {
            let library_of_file = self.library_of_file.clone();
            let lookup = move |f: FileId| library_of_file.get(&f).copied();
            self.builders[i].build_elements(&mut self.store, &mut self.fs, &lookup);
        }
        self.build_export_scopes(first_new);

        self.build_class_synthetic_constructors(first_new);
        self.build_enum_synthetic_constructors(first_new);
    }

    /// The library files the imports and exports of [file] and of the parts
    /// it includes select, and `dart:core`.
    fn dependencies(&mut self, file: FileId) -> Vec<FileId> {
        let mut result = Vec::new();
        let mut included = vec![file];
        let mut index = 0;
        while index < included.len() {
            let container = included[index];
            index += 1;
            let unlinked = self.fs.file(container).unlinked.clone();
            let mut targets = Vec::new();
            for import in &unlinked.imports {
                targets.push(self.fs.selected_uri(container, import.uri.as_deref(), &import.configurations));
            }
            for export in &unlinked.exports {
                targets.push(self.fs.selected_uri(container, export.uri.as_deref(), &export.configurations));
            }
            if container == file && !unlinked.is_dart_core && !unlinked.has_dart_core_import {
                targets.push(self.fs.build_directive_uri(container, Some("dart:core")));
            }
            for target in targets {
                if let DirectiveUriState::WithFile { file: target, .. } = target {
                    if self.fs.is_library(target) {
                        result.push(target);
                    }
                }
            }
            for part in &unlinked.parts {
                if let DirectiveUriState::WithFile { file: part, .. } =
                    self.fs.selected_uri(container, part.uri.as_deref(), &[])
                {
                    if !self.fs.is_library(part) && self.fs.is_part_of(part, container) && !included.contains(&part) {
                        included.push(part);
                    }
                }
            }
        }
        result
    }

    /// `_buildExportScopes`, for the builders from [first_new].
    fn build_export_scopes(&mut self, first_new: usize) {
        for builder in &mut self.builders[first_new..] {
            builder.build_initial_export_scope();
        }

        // `addExporters`.
        for exporter in first_new..self.builders.len() {
            let library = self.builders[exporter].element;
            let fragments = self.store.libraries[library as usize].fragments.clone();
            for (fragment_index, unit) in fragments.iter().enumerate() {
                let exports = self.store.units[*unit as usize].library_exports.clone();
                for (export_index, export) in exports.iter().enumerate() {
                    let DirectiveUri::WithLibrary { library: exported, .. } = export.uri else {
                        continue;
                    };
                    let export = Export {
                        exporter,
                        location: ExportLocation {
                            fragment_index: fragment_index as u32,
                            export_index: export_index as u32,
                        },
                        combinators: build_combinators(&export.combinators),
                    };
                    let exported_builder = self.builder_of_library[&exported];
                    if exported_builder >= first_new {
                        self.builders[exported_builder].exports.push(export);
                    } else {
                        // Linked before: its export scope is final.
                        let entries = self.builders[exported_builder].export_scope.entries.clone();
                        for entry in &entries {
                            self.add_to_export_scope(&export, entry);
                        }
                    }
                }
            }
        }

        let mut exporting = Vec::new();
        let mut exported = Vec::new();
        for i in first_new..self.builders.len() {
            if !self.builders[i].exports.is_empty() {
                exported.push(i);
                for export in &self.builders[i].exports {
                    if !exporting.contains(&export.exporter) {
                        exporting.push(export.exporter);
                    }
                }
            }
        }

        let mut both = Vec::new();
        for &e in &exported {
            if exporting.contains(&e) {
                both.push(e);
            }
            let exports = self.builders[e].exports.clone();
            let entries = self.builders[e].export_scope.entries.clone();
            for export in &exports {
                for entry in &entries {
                    self.add_to_export_scope(export, entry);
                }
            }
        }

        // A queue of export entries to propagate: first every library that
        // both exports and is exported, then only the entries that were
        // added.
        let mut additional: Vec<(usize, crate::src::summary2::export::ExportEntry)> = Vec::new();
        for &e in &both {
            let exports = self.builders[e].exports.clone();
            let entries = self.builders[e].export_scope.entries.clone();
            for export in &exports {
                for entry in &entries {
                    if self.add_to_export_scope(export, entry) {
                        additional.push((export.exporter, entry.clone()));
                    }
                }
            }
        }
        while let Some((library, entry)) = additional.pop() {
            let exports = self.builders[library].exports.clone();
            for export in &exports {
                if self.add_to_export_scope(export, &entry) {
                    additional.push((export.exporter, entry.clone()));
                }
            }
        }

        for builder in &self.builders[first_new..] {
            builder.store_export_scope(&mut self.store);
        }
    }

    /// `Export.addToExportScope`.
    fn add_to_export_scope(&mut self, export: &Export, entry: &crate::src::summary2::export::ExportEntry) -> bool {
        if crate::src::summary2::export::allows(&export.combinators, &entry.name) {
            return self.builders[export.exporter].export_scope.export(export.location, entry);
        }
        false
    }

    fn build_class_synthetic_constructors(&mut self, first_new: usize) {
        for builder in &self.builders[first_new..] {
            builder.build_class_synthetic_constructors(&mut self.store);
        }
    }

    fn build_enum_synthetic_constructors(&mut self, first_new: usize) {
        for builder in &self.builders[first_new..] {
            builder.build_enum_synthetic_constructors(&mut self.store);
        }
    }
}
