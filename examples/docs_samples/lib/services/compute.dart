import '../dartvel_client/dartvel_client.dart';

// docs:start workers-run
// A task is a top-level function, so it can be sent to another isolate.
int checksum(List<int> bytes, DVWorkerReporter reporter) {
  int sum = 0;
  for (int i = 0; i < bytes.length; i++) {
    sum = (sum + bytes[i]) & 0xffffffff;
    if (i % 100000 == 0) reporter.progress(i / bytes.length);
  }
  return sum;
}

Future<int> checksumOf(List<int> upload) async {
  final DVWorkerResult<int> result = await DV.Workers.run(
    checksum,
    input: upload,
    onProgress: (DVProgress progress) => DV.log('${progress.fraction}'),
    // Stop the work when the app shuts down.
    cancellation: DVCancellation.until(
      DV.lifecycle.app,
      (DVAppLifecycle state) => state == DVAppLifecycle.shuttingDown,
    ),
    timeout: const Duration(seconds: 10),
  );
  return result.value; // rethrows if the task failed, timed out or was cancelled
}
// docs:end

Future<void> scaleSamples() async {
  // docs:start memory-arena
  final DVPlatformMemory arena = DV.Memory.allocate(megabytes: 512);
  final MemorySlice<double> samples = arena.float64(10000000)..fill(0);

  // Yields to the event loop between batches, so the UI keeps drawing.
  await samples.transformAsync((double v) => v * 0.5 + 1);

  DV.log('reserved ${arena.securedBytes} bytes, used ${arena.usedBytes}');
  arena.reset(); // every slice from before the reset now throws if touched
  // docs:end
}
