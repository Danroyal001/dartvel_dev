// Port of lib/dart/analysis/features.dart.
//
// `FeatureSet` has one implementation, `ExperimentStatus`, which it is here;
// a `Feature` is its index in the feature table (experiments_g.rs).

pub use crate::src::dart::analysis::experiments::ExperimentStatus as FeatureSet;
pub use crate::src::dart::analysis::experiments_g::Feature;

impl FeatureSet {
    /// `FeatureSet.latestLanguageVersion()`.
    pub fn latest() -> FeatureSet {
        FeatureSet::latest_language_version()
    }
}
