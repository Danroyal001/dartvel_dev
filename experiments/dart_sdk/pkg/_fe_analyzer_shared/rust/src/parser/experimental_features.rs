// Port of lib/src/parser/experimental_features.dart.

use crate::experiments::flags::ExperimentalFlag;
use crate::scanner::abstract_scanner::ScannerConfiguration;

/// Interface for determining which features are enabled during parsing.
pub trait ExperimentalFeatures {
    fn is_experiment_enabled(&self, flag: ExperimentalFlag) -> bool;

    /// `ExperimentalFeaturesExtension.buildScannerConfiguration`.
    fn build_scanner_configuration(&self) -> ScannerConfiguration {
        ScannerConfiguration {
            enable_triple_shift: self.is_experiment_enabled(ExperimentalFlag::tripleShift),
            enable_augmentations: self.is_experiment_enabled(ExperimentalFlag::augmentations),
        }
    }
}

/// Implementation of [ExperimentalFeatures] that uses the enables the
/// experiments currently enabled by default.
///
/// This should only be used for testing. For actual parsing, the enabled
/// features should be determined by language version and enabled experiments.
#[derive(Clone, Copy, Default, Debug)]
pub struct DefaultExperimentalFeatures;

impl ExperimentalFeatures for DefaultExperimentalFeatures {
    fn is_experiment_enabled(&self, flag: ExperimentalFlag) -> bool {
        flag.is_enabled_by_default()
    }
}
