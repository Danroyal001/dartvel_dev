// Module of lib/transformations/type_flow (not a mirrored file).
use kernel::class_hierarchy::ClassHierarchy;
use kernel::core_types::CoreTypes;
use kernel::reference_index::NodeIndex;
use kernel::type_environment::TypeEnvironment;

pub mod analysis;
pub mod calls;
pub mod summary;
pub mod summary_collector;
pub mod types;

/// What upstream reaches through its nodes and its `TypeEnvironment`: the
/// component's index, core types, class hierarchy and type environment.
pub struct Env<'a> {
    pub index: &'a NodeIndex<'a>,
    pub coreTypes: &'a CoreTypes<'a>,
    pub hierarchy: &'a ClassHierarchy<'a>,
    pub typeEnvironment: &'a TypeEnvironment<'a>,
}
