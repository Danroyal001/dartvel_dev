// Port of lib/src/dart/analysis/experiments_impl.dart (the part that
// decides which features a language version enables).
//
// Explicit `--enable-experiment` flags are kept as lists of bools, as
// upstream keeps them; parsing a string never sets any.

use fe_analyzer_shared::experiments::flags::Version;

use crate::src::dart::analysis::experiments_g::knownFeatures;

/// Information about a single language feature whose presence or absence
/// is controlled by an experimental flag (the members that matter here).
#[derive(Clone, Copy, Debug)]
pub struct ExperimentalFeature {
    /// Index of this feature in the list of all features.
    pub index: usize,

    /// The string to enable this feature on the command line.
    pub enable_string: &'static str,

    /// Whether this feature is enabled by default.
    pub is_enabled_by_default: bool,

    /// The first language version in which this feature can be enabled by
    /// passing its flag.
    pub experimental_release_version: Option<Version>,

    /// The first language version in which this feature is enabled without
    /// a flag.
    pub release_version: Option<Version>,
}

/// `Version` comparison: `a >= b`. Language versions here have no patch.
pub fn version_ge(a: (i64, i64), b: Version) -> bool {
    a >= (b.major as i64, b.minor as i64)
}

pub fn restrict_enable_flags_to_version(
    sdk_language_version: (i64, i64),
    explicit_enabled_flags: &[bool],
    explicit_disabled_flags: &[bool],
    version: (i64, i64),
) -> Vec<bool> {
    let mut decoded_flags = vec![false; knownFeatures.len()];
    for feature in &knownFeatures {
        if explicit_disabled_flags[feature.index] {
            decoded_flags[feature.index] = false;
            continue;
        }

        let release_version = feature.release_version;
        if let Some(release_version) = release_version
            && version_ge(version, release_version)
        {
            decoded_flags[feature.index] = true;
        }

        if explicit_enabled_flags[feature.index] {
            let experimental_release_version = feature.experimental_release_version;
            match experimental_release_version {
                None => {
                    // Specifically, the current sdk version (whatever it is) is always
                    // used as the language version which opts code into the experiment
                    // when the experiment flag is passed.
                    if version == sdk_language_version {
                        decoded_flags[feature.index] = true;
                    }
                }
                Some(experimental_release_version) => {
                    if version_ge(version, experimental_release_version)
                        || version >= sdk_language_version
                    {
                        decoded_flags[feature.index] = true;
                    }
                }
            }
        }
    }
    decoded_flags
}
