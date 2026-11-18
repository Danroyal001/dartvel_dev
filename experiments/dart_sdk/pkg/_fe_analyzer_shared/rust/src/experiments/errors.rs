// Port of lib/src/experiments/errors.dart.

use crate::experiments::flags::ExperimentalFlag;
use crate::messages::codes::Message;
use crate::messages::diagnostic as diag;

/// Returns the message used to report that [experimental_flag] feature is not
/// enabled.
pub fn get_experiment_not_enabled_message(experimental_flag: ExperimentalFlag) -> Message {
    if experimental_flag.is_enabled_by_default() {
        (diag::experimentNotEnabled.with_arguments)(
            experimental_flag.name(),
            &experimental_flag.experiment_enabled_version().to_text(),
        )
    } else {
        (diag::experimentNotEnabledOffByDefault.with_arguments)(experimental_flag.name())
    }
}
