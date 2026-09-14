/// A target without isolates.
///
/// No runner means the pool runs work inline and reports `DV-WORKER-001`.
library dartvel.compute.workers_host_stub;

import 'worker_types.dart';

DVWorkerRunner? dvHostWorkerRunner() => null;

int dvHostProcessors() => 1;
