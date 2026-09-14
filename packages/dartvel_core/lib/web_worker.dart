/// The entry a web worker script imports.
///
/// Web only: it is the code that runs inside the worker, and it touches the
/// worker's global scope. The page imports `package:dartvel_core/dartvel.dart`
/// as usual; the worker script imports this and registers the same tasks.
library dartvel_core.web_worker;

export 'src/compute/web_worker_entry.dart' show dvWebWorkerMain;
export 'src/compute/web_worker_protocol.dart' show DVWorkerTasks;
export 'src/compute/worker_types.dart' show DVWorkerReporter, DVWorkerTask;
