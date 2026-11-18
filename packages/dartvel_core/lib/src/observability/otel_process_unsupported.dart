/// Where there is no process to describe: a browser.
library dartvel.observability.otel_process_unsupported;

/// Nothing: a browser tab has no pid or host name it may report.
Map<String, Object> dvOtelProcessResource() => const <String, Object>{};

/// Null: a browser does not expose the page's memory in a standard way.
({int current, int peak})? dvOtelProcessMemory() => null;

/// Empty: a browser has no environment variables.
Map<String, String> dvOtelEnvironment() => const <String, String>{};
