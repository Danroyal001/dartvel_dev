/// The environment this process was started with.
///
/// Read for the few decisions a process has to make before any startup code
/// could make them for it -- whether it is a preview, and which queues are its
/// own. Empty where there is no process environment: a browser build has none,
/// and is never a preview's server.
library;

import 'process_environment_unsupported.dart'
    if (dart.library.io) 'process_environment_io.dart'
    as impl;

/// The process environment, or an empty map where there is none.
Map<String, String> dvProcessEnvironment() => impl.processEnvironment();
