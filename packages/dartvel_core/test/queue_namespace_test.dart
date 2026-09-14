// Queues under a namespace: a preview never consumes a production job, and
// production never consumes a preview's.
//
// A deployment writes DARTVEL_QUEUE_NAMESPACE and, until this, no queue read
// it -- so a preview pointed at the same broker as production reserved from
// the same `default` queue and ran production's jobs against its own seeded
// database. Nothing throws when that happens; the job just runs in the wrong
// place. So these assert on where the job actually is in the adapter, not on
// what the facade says it did.
//
// The namespace is applied in DVQueues, the one path every adapter is reached
// through, rather than in each adapter, so an adapter added later cannot
// forget it.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class Cleanup {
  const Cleanup(this.id);
  final String id;
}

const String namespace = 'preview-cart-c39f4dfa';

void main() {
  late DVInMemoryQueueAdapter adapter;
  final List<String> handled = <String>[];

  setUp(() {
    adapter = const DVTestHarness().fakeQueue();
    handled.clear();
    const DVQueues().register<Cleanup>((Cleanup job) async {
      handled.add(job.id);
    });
  });

  tearDown(() => const DVQueues().useNamespace(null));

  test('a namespaced process dispatches under its namespace', () async {
    const DVQueues().useNamespace(namespace);

    await const DVQueues().dispatch<Cleanup>(const Cleanup('a'));

    expect(await adapter.pending('$namespace.default'), hasLength(1));
    expect(
      await adapter.pending('default'),
      isEmpty,
      reason: 'production\'s queue must not receive a preview\'s job',
    );
  });

  test('a preview never consumes a production job', () async {
    await adapter.enqueue<Cleanup>('default', const Cleanup('production'));
    const DVQueues().useNamespace(namespace);

    final int completed = await const DVQueues().work(maxJobs: 5);

    expect(completed, 0);
    expect(handled, isEmpty);
    expect(
      await adapter.pending('default'),
      hasLength(1),
      reason: 'the production job is still waiting for production',
    );
  });

  test('production never consumes a preview job', () async {
    const DVQueues().useNamespace(namespace);
    await const DVQueues().dispatch<Cleanup>(const Cleanup('preview'));
    const DVQueues().useNamespace(null);

    final int completed = await const DVQueues().work(maxJobs: 5);

    expect(completed, 0);
    expect(handled, isEmpty);
    expect(await adapter.pending('$namespace.default'), hasLength(1));
  });

  test('a namespaced worker runs its own jobs', () async {
    const DVQueues().useNamespace(namespace);
    await const DVQueues().dispatch<Cleanup>(const Cleanup('mine'));

    expect(await const DVQueues().work(maxJobs: 5), 1);
    expect(handled, <String>['mine']);
  });

  test('pending, dead letters and flush read only the namespace', () async {
    await adapter.enqueue<Cleanup>('default', const Cleanup('production'));
    const DVQueues().useNamespace(namespace);
    await const DVQueues().dispatch<Cleanup>(const Cleanup('preview'));

    expect(await const DVQueues().pending(), hasLength(1));
    expect(await const DVQueues().deadLetters(), isEmpty);
    expect(await const DVQueues().flush(), 1);
    expect(
      await adapter.pending('default'),
      hasLength(1),
      reason: 'flushing a preview\'s queue must leave production\'s alone',
    );
  });

  test(
    'without a namespace, a queue named like a preview\'s is refused',
    () async {
      // Otherwise production could reach a preview's jobs by spelling the
      // qualified name out, which is the vice versa of the rule.
      expect(
        () => const DVQueues().dispatch<Cleanup>(
          const Cleanup('x'),
          queue: '$namespace.default',
        ),
        throwsArgumentError,
      );
      expect(
        () => const DVQueues().work(queue: '$namespace.default'),
        throwsArgumentError,
      );
    },
  );

  test('a namespace that could be read as part of a queue name is refused', () {
    expect(
      () => const DVQueues().useNamespace('preview.cart'),
      throwsArgumentError,
    );
    expect(() => const DVQueues().useNamespace(''), throwsArgumentError);
    expect(const DVQueues().namespace, isNull);
  });
}
