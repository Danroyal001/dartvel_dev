// Port of lib/src/dart/analysis/experiments.dart (`ExperimentStatus` and
// `ExperimentalFeaturesStatus`, without the storage encoding).

use fe_analyzer_shared::experiments::flags::ExperimentalFlag;
use fe_analyzer_shared::parser::experimental_features::ExperimentalFeatures;

use crate::dart::analysis::features::FeatureSet;
use crate::src::dart::analysis::experiments_g::{
    currentVersion, from_shared_experimental_flags, knownFeatures,
};
use crate::src::dart::analysis::experiments_impl::restrict_enable_flags_to_version;

/// Implementation of [ExperimentalFeatures] that reads a [FeatureSet].
#[derive(Clone, Debug)]
pub struct ExperimentalFeaturesStatus {
    pub feature_set: FeatureSet,
}

impl ExperimentalFeaturesStatus {
    pub fn new(feature_set: FeatureSet) -> ExperimentalFeaturesStatus {
        ExperimentalFeaturesStatus { feature_set }
    }
}

impl ExperimentalFeatures for ExperimentalFeaturesStatus {
    fn is_experiment_enabled(&self, flag: ExperimentalFlag) -> bool {
        self.feature_set
            .is_enabled(from_shared_experimental_flags(flag))
    }
}

/// A representation of the set of experiments that are active and whether
/// they are enabled.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct ExperimentStatus {
    pub sdk_language_version: (i64, i64),
    pub explicit_enabled_flags: Vec<bool>,
    pub explicit_disabled_flags: Vec<bool>,
    pub flags: Vec<bool>,
}

impl ExperimentStatus {
    /// `ExperimentStatus.currentVersion`.
    pub fn current_version() -> (i64, i64) {
        (currentVersion.major as i64, currentVersion.minor as i64)
    }

    /// `ExperimentStatus.fromStrings2` with no flags.
    pub fn from_strings2(sdk_language_version: (i64, i64)) -> ExperimentStatus {
        let explicit_enabled = vec![false; knownFeatures.len()];
        let explicit_disabled = vec![false; knownFeatures.len()];
        let decoded_flags = restrict_enable_flags_to_version(
            sdk_language_version,
            &explicit_enabled,
            &explicit_disabled,
            sdk_language_version,
        );
        ExperimentStatus {
            sdk_language_version,
            explicit_enabled_flags: explicit_enabled,
            explicit_disabled_flags: explicit_disabled,
            flags: decoded_flags,
        }
    }

    /// `ExperimentStatus.latestLanguageVersion()`.
    pub fn latest_language_version() -> ExperimentStatus {
        ExperimentStatus::from_strings2(ExperimentStatus::current_version())
    }

    pub fn is_enabled(&self, feature: usize) -> bool {
        self.flags[feature]
    }

    pub fn restrict_to_version(&self, version: (i64, i64)) -> ExperimentStatus {
        ExperimentStatus {
            sdk_language_version: self.sdk_language_version,
            explicit_enabled_flags: self.explicit_enabled_flags.clone(),
            explicit_disabled_flags: self.explicit_disabled_flags.clone(),
            flags: restrict_enable_flags_to_version(
                self.sdk_language_version,
                &self.explicit_enabled_flags,
                &self.explicit_disabled_flags,
                version,
            ),
        }
    }
}
