// Module of lib/transformations/type_flow (not a mirrored file).
use kernel::ast::Component;

/// What upstream's `PrintSummaries` (test/transformations/type_flow/
/// summary_collector_test.dart) prints for the main library of
/// [component]. Not ported yet.
pub fn print_summaries_for_testing(_component: &Component) -> String {
    String::new()
}
