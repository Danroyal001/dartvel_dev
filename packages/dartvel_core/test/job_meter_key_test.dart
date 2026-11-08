// A job records usage under its own id, so a retried job counts once.
//
// A job that recorded usage and then failed is run again. Without a key
// from the job, the handler's recording either throws (no key at all) or --
// worse -- takes a key somebody generated per attempt and counts on every
// attempt, which is a bill too high by exactly the number of retries.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class ResizeImage {
  const ResizeImage(this.imageId);
  final String imageId;
}

void main() {
  late DVMeters meters;
  final DVMeterDefinition resizes = DVMeterDefinition('resizes', unit: 'image');
  late int attempts;
  late bool failFirst;

  setUp(() {
    attempts = 0;
    failFirst = false;
    meters = DVMeters(
      store: DVMemoryMeterStore(),
      clock: () => DateTime.utc(2026, 9, 15, 12),
    );
    const DVQueues().useAdapter(DVInMemoryQueueAdapter());
    const DVQueues().register<ResizeImage>((ResizeImage job) async {
      attempts++;
      await meters.record(resizes, 1);
      if (failFirst && attempts == 1) throw StateError('the disk was full');
    });
  });

  tearDown(() {
    const DVQueues().useAdapter(DVInMemoryQueueAdapter());
    DVTenants.reset();
  });

  test('a job records with no key of its own, under the job id', () async {
    await const DVQueues().dispatch(const ResizeImage('a'));
    expect(await const DVQueues().work(), 1);
    expect(await meters.usage(resizes, tenant: DVTenants.defaultTenant), 1);
  });

  test('a retried job counts once however many attempts it took', () async {
    failFirst = true;
    await const DVQueues()
        .dispatch(const ResizeImage('a'), backoff: Duration.zero);
    await const DVQueues().work();
    await const DVQueues().work();
    expect(attempts, 2, reason: 'the first attempt failed and was retried');
    expect(await meters.usage(resizes, tenant: DVTenants.defaultTenant), 1);
  });

  test('two jobs are two recordings', () async {
    await const DVQueues().dispatch(const ResizeImage('a'));
    await const DVQueues().dispatch(const ResizeImage('b'));
    expect(await const DVQueues().work(maxJobs: 2), 2);
    expect(await meters.usage(resizes, tenant: DVTenants.defaultTenant), 2);
  });
}
