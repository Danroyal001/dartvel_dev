// Port of lib/src/dart/scanner/scanner.dart.
//
// The language-version callback upstream's `Scanner` hands the fasta
// scanner closes over the scanner itself; here the state it changes (the
// override version, the feature set and the errors it reports) is shared
// with the callback through an `Rc<RefCell<_>>`, and the errors are reported
// when `tokenize` returns, before anything else is reported.

use std::cell::RefCell;
use std::rc::Rc;

use fe_analyzer_shared::parser::experimental_features::ExperimentalFeatures;
use fe_analyzer_shared::scanner::abstract_scanner::LanguageVersionChanged;
use fe_analyzer_shared::scanner::scanner::{ScannerResult, scan_string};

use crate::dart::analysis::features::FeatureSet;
use crate::src::dart::analysis::experiments::{ExperimentStatus, ExperimentalFeaturesStatus};
use crate::src::diagnostic::diagnostic::LocatedDiagnostic;
use crate::src::diagnostic::diagnostic_g as diag;

/// What the language-version callback changes.
struct ScannerState {
    feature_set_for_overriding: FeatureSet,
    latest_language_version: (i64, i64),
    override_version: Option<(i64, i64)>,
    feature_set: FeatureSet,
    errors: Vec<LocatedDiagnostic>,
}

/// The class `Scanner` implements a scanner for Dart code.
pub struct Scanner {
    input_text: Rc<[u16]>,
    preserve_comments: bool,
    line_starts: Vec<i32>,
    state: Rc<RefCell<ScannerState>>,
}

impl Scanner {
    pub fn new(input_text: Rc<[u16]>) -> Scanner {
        Scanner {
            input_text,
            preserve_comments: true,
            line_starts: Vec::new(),
            state: Rc::new(RefCell::new(ScannerState {
                feature_set_for_overriding: FeatureSet::latest(),
                latest_language_version: ExperimentStatus::current_version(),
                override_version: None,
                feature_set: FeatureSet::latest(),
                errors: Vec::new(),
            })),
        }
    }

    pub fn feature_set(&self) -> FeatureSet {
        self.state.borrow().feature_set.clone()
    }

    pub fn line_starts(&self) -> &[i32] {
        &self.line_starts
    }

    pub fn override_version(&self) -> Option<(i64, i64)> {
        self.state.borrow().override_version
    }

    pub fn set_preserve_comments(&mut self, preserve_comments: bool) {
        self.preserve_comments = preserve_comments;
    }

    /// Configures the scanner appropriately for the given [feature_set].
    pub fn configure_features(
        &mut self,
        feature_set_for_overriding: FeatureSet,
        feature_set: FeatureSet,
        latest_language_version: Option<(i64, i64)>,
    ) {
        let mut state = self.state.borrow_mut();
        state.feature_set_for_overriding = feature_set_for_overriding;
        state.feature_set = feature_set;
        state.latest_language_version =
            latest_language_version.unwrap_or_else(ExperimentStatus::current_version);
    }

    /// Scans the input; returns the scanner result (the first token and the
    /// token store) and the errors the scanner reported, in order.
    pub fn tokenize(&mut self, report_error: &mut dyn FnMut(LocatedDiagnostic)) -> ScannerResult {
        let configuration =
            ExperimentalFeaturesStatus::new(self.state.borrow().feature_set.clone())
                .build_scanner_configuration();
        let state = self.state.clone();
        let result = scan_string(
            self.input_text.clone(),
            Some(configuration),
            self.preserve_comments,
            || Some(language_version_changed(state.clone())),
        );

        // fasta pretends there is an additional line at EOF so we skip the last one.
        let line_starts = &result.line_starts;
        self.line_starts = line_starts[..line_starts.len() - 1]
            .iter()
            .map(|&s| s as i32)
            .collect();

        for error in std::mem::take(&mut self.state.borrow_mut().errors) {
            report_error(error);
        }
        result
    }
}

/// `_languageVersionChanged`.
fn language_version_changed(state: Rc<RefCell<ScannerState>>) -> LanguageVersionChanged {
    Box::new(move |tokens, version_token| {
        let override_major = tokens.major(version_token);
        let override_minor = tokens.minor(version_token);
        if override_major < 0 || override_minor < 0 {
            return None;
        }

        let override_version = (override_major, override_minor);
        let mut state = state.borrow_mut();
        state.override_version = Some(override_version);

        let latest_version = state.latest_language_version;
        if override_version > latest_version {
            state.errors.push(
                diag::invalidLanguageVersionOverrideGreater
                    .with_arguments(vec![
                        latest_version.0.to_string(),
                        latest_version.1.to_string(),
                    ])
                    .at_offset(tokens.offset(version_token), tokens.length(version_token)),
            );
            state.override_version = None;
            None
        } else {
            state.feature_set = state
                .feature_set_for_overriding
                .restrict_to_version(override_version);
            Some(
                ExperimentalFeaturesStatus::new(state.feature_set.clone())
                    .build_scanner_configuration(),
            )
        }
    })
}
