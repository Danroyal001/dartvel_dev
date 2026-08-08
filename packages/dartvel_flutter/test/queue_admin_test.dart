// The queue dashboard, driven against a real queue.
//
// Retry and discard are the point: a dashboard that lists failed jobs but
// cannot act on them leaves an operator with a flush as the only tool, which
// takes healthy jobs with it. So the assertions are about what happened to
// the queue, not about what the screen printed.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class SendInvoice {
  final String account;
  const SendInvoice(this.account);
}

final invoiceCodec = DVJobPayloadCodec<SendInvoice>(
  name: 'send_invoice',
  encode: (SendInvoice job) => <String, Object?>{'account': job.account},
  decode: (Map<String, Object?> json) =>
      SendInvoice(json['account']! as String),
);

void main() {
  late DVInMemoryQueueAdapter adapter;

  setUp(() {
    const DVJobPayloadCodecs().clear();
    const DVJobPayloadCodecs().register(invoiceCodec);
    adapter = DVInMemoryQueueAdapter();
    const DVQueues().useAdapter(adapter);
  });

  tearDown(const DVJobPayloadCodecs().clear);

  /// Enqueues a job and fails it until it dead-letters.
  ///
  /// Reserving in a loop because reserve() hands back whichever job is at the
  /// head of the queue, which is not necessarily the one just enqueued —
  /// failing that id instead would quietly kill somebody else's job.
  Future<String> deadLetter(String account) async {
    final job = await adapter.enqueue(
      'billing',
      SendInvoice(account),
      maxAttempts: 1,
    );
    final requeue = <DVJobEnvelope<DVJobPayload>>[];
    while (true) {
      final reserved = await adapter.reserve('billing');
      if (reserved == null) {
        throw StateError('${job.id} never came up for reservation');
      }
      if (reserved.id == job.id) break;
      requeue.add(reserved);
    }
    await adapter.fail(job.id, 'card declined for $account', StackTrace.empty);
    // Put back anything reserved on the way past, so the queue looks as it
    // did apart from the job that died.
    for (final other in requeue) {
      await adapter.fail(other.id, 'set aside', StackTrace.empty);
      await adapter.retry(other.id);
    }
    return job.id;
  }

  Widget host() => const MaterialApp(
        home: Material(child: DVQueueAdmin(queues: <String>['billing'])),
      );

  testWidgets('pending and failed counts are reported per queue',
      (WidgetTester tester) async {
    await adapter.enqueue('billing', const SendInvoice('waiting'));
    await deadLetter('broken');

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('billing'), findsOneWidget);
    expect(find.text('1 pending, 1 failed'), findsOneWidget);
  });

  testWidgets('a failed job shows why it failed', (WidgetTester tester) async {
    await deadLetter('acme');

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // Retrying without knowing the reason is guessing.
    expect(find.text('card declined for acme'), findsOneWidget);
    expect(find.text('gave up after 1 of 1'), findsOneWidget);
  });

  testWidgets('retry puts the job back on the queue',
      (WidgetTester tester) async {
    final id = await deadLetter('acme');

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>('dv-queue-retry-$id')));
    await tester.pumpAndSettle();

    expect(await adapter.deadLetters('billing'), isEmpty);
    expect(await adapter.pending('billing'), hasLength(1));
    expect(find.text('1 pending, 0 failed'), findsOneWidget);
  });

  testWidgets('discard drops that job and leaves the others',
      (WidgetTester tester) async {
    final poison = await deadLetter('poison');
    await deadLetter('other');

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>('dv-queue-discard-$poison')));
    await tester.pumpAndSettle();

    final remaining = await adapter.deadLetters('billing');
    expect(remaining, hasLength(1));
    expect(remaining.single.lastError, contains('other'));
    expect(await adapter.pending('billing'), isEmpty);
  });

  testWidgets('an empty queue says so rather than looking broken',
      (WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Nothing pending.'), findsOneWidget);
    expect(find.text('No failed jobs.'), findsOneWidget);
    expect(find.text('0 pending, 0 failed'), findsOneWidget);
  });

  testWidgets('acting on a job that is already gone says so',
      (WidgetTester tester) async {
    final id = await deadLetter('acme');

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    // Something else cleared it between the render and the tap.
    await adapter.discard(id);
    await tester.tap(find.byKey(ValueKey<String>('dv-queue-retry-$id')));
    await tester.pumpAndSettle();

    // Reporting success here would leave an operator believing the job was
    // requeued.
    expect(find.text('No such job.'), findsOneWidget);
  });

  testWidgets('several queues are shown separately',
      (WidgetTester tester) async {
    await adapter.enqueue('billing', const SendInvoice('a'));
    await adapter.enqueue('mail', const SendInvoice('b'));

    await tester.pumpWidget(const MaterialApp(
      home: Material(
        child: DVQueueAdmin(queues: <String>['billing', 'mail']),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('billing'), findsOneWidget);
    expect(find.text('mail'), findsOneWidget);
    expect(find.text('1 pending, 0 failed'), findsNWidgets(2));
  });
}
