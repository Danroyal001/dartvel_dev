// Dart source: pkg/analysis_server/lib/src/services/refactoring/legacy/refactoring.dart (RefactoringWorkspace)
// Dart source: pkg/analysis_server/lib/src/services/search/search_engine.dart (SearchEngine)

//! What the refactorings need from a server: the resolved units, the
//! search engine and the change workspace (Dart `RefactoringWorkspace`).
//! The LSP server and the legacy server implement it.

use std::sync::Arc;

use dartr_project::AnalysisContextCollection;

use crate::correction::change_builder::ChangeWorkspace;
use crate::index::ElementKey;
use crate::server::{Match, ResolvedUnitRef, SElem, SearchScope};

/// Dart `RefactoringWorkspace` and `SearchEngine`.
pub trait RefactoringHost {
    /// The contexts of the workspace.
    fn collection(&self) -> Option<&AnalysisContextCollection>;

    /// The resolved unit of [path] in the driver of [context] (the context
    /// of the path when `None`).
    fn resolved_unit_in(&mut self, path: &str, context: Option<usize>) -> Option<ResolvedUnitRef>;

    /// Dart `SearchEngine.searchReferences`.
    fn search_references(&mut self, element: &SElem) -> Vec<Match>;

    /// Dart `getHierarchyMembersAndParameters(includeParametersForFields:
    /// true)`.
    fn hierarchy_members_and_parameters(&mut self, member: &SElem) -> (Vec<SElem>, Vec<SElem>);

    /// Dart `getHierarchyNamedParameters`.
    fn hierarchy_named_parameters(&mut self, parameter: &SElem) -> Vec<SElem>;

    /// Dart `SearchEngine.appendAllSubtypes`.
    fn append_all_subtypes(
        &mut self,
        class: &SElem,
        all: &mut Vec<SElem>,
        keys: &mut Vec<(usize, ElementKey)>,
    );

    /// The files that a search looks at, by driver.
    fn search_scope(&mut self) -> Arc<SearchScope>;

    /// Dart `FileState.referencingFiles` of [path] in the driver of
    /// [context]: the files with a directive that selects [path], in the
    /// order the Dart driver records them (see
    /// `DriverSession::dart_referencing_files`).
    fn referencing_files(&mut self, path: &str, context: usize) -> Vec<String>;

    /// Whether the file [path] mentions one of [names].
    fn mentions_any(&mut self, path: &str, names: &[String]) -> bool;

    /// Calls [f] with the workspace of a change builder.
    fn with_change_workspace(&mut self, f: &mut dyn FnMut(&mut dyn ChangeWorkspace));
}

/// Dart `FileState.referencingFiles` of [path] in the driver of [context],
/// for the hosts: the analysis order of the driver is its priority files
/// (Dart `AnalysisDriver._priorityFiles`, analyzed first by
/// `performWork`) then its added files (`_fileTracker` pending files, in
/// `addedFiles` order), filtered by [is_excluded].
pub fn referencing_files(
    session: &mut dartr_cli::DriverSession,
    collection: &AnalysisContextCollection,
    context: usize,
    path: &str,
    is_excluded: &dyn Fn(&str) -> bool,
) -> Vec<String> {
    let order = dart_analysis_order(session, collection, context, is_excluded);
    session.dart_referencing_files(context, &order, path)
}

/// The order in which the Dart driver of [context] analyzes its files: its
/// priority files when it first analyzed (Dart `performWork` analyzes
/// `_priorityFiles` first), then its added files (the pending files of
/// `_fileTracker`, in `addedFiles` order), without [is_excluded] files.
pub fn dart_analysis_order(
    session: &dartr_cli::DriverSession,
    collection: &AnalysisContextCollection,
    context: usize,
    is_excluded: &dyn Fn(&str) -> bool,
) -> Vec<String> {
    let Some(ctx) = collection.contexts.get(context) else {
        return Vec::new();
    };
    let added: Vec<String> = ctx
        .root
        .analyzed_files()
        .into_iter()
        .filter(|f| f.ends_with(".dart") && !is_excluded(f))
        .collect();
    let mut order: Vec<String> = session
        .analysis_priority()
        .iter()
        .filter(|p| added.contains(p))
        .cloned()
        .collect();
    order.extend(added);
    order
}
