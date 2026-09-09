// The specification says secret values are excluded from logs, traces,
// diagnostics and error messages by construction. What the logger actually
// had was a list of suspicious key names -- password, token, apikey -- which
// is a guess about where a secret might be, not a guarantee about the values
// themselves.
//
// The guess misses the cases that matter most. A connection string under the
// key `url`, an upstream error quoting the credential back at you, a message
// a developer wrote by hand during an incident: all three carry the value
// straight into the log store. Meanwhile the resolved secrets are an
// enumerable set, because DV.Secrets is the only thing that hands them out,
// so the framework can match on the value rather than guess about the key.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  setUp(DVSecrets.reset);
  tearDown(DVSecrets.reset);

  group('redacting resolved secret values', () {
    test('a secret pasted into a log message does not reach the sink', () {
      DVSecrets.configure(<String, String>{
        'PAYSTACK_SECRET': 'sk_live_9f2c4ab7d1e6',
      });
      const DVSecrets().get('PAYSTACK_SECRET');

      final DVMemoryLogSink sink = DVMemoryLogSink();
      final DVLogger logger = DVLogger(sinks: <DVLogSink>[sink]);
      logger.error('gateway refused key sk_live_9f2c4ab7d1e6');

      expect(
        sink.records.single.message,
        isNot(contains('sk_live_9f2c4ab7d1e6')),
      );
      expect(sink.records.single.message, contains(DVLogger.redactedValue));
      // The surrounding sentence has to survive, or an incident loses the one
      // line that said which call failed.
      expect(sink.records.single.message, contains('gateway refused key'));
    });

    test('a secret under an innocuous context key is redacted', () {
      // The exact miss in the key-name approach. Nothing about `url` looks
      // like a credential, and the password sits inside the value.
      DVSecrets.configure(<String, String>{
        'DATABASE_PASSWORD': 'hunter2-correct-horse',
      });
      const DVSecrets().get('DATABASE_PASSWORD');

      final DVMemoryLogSink sink = DVMemoryLogSink();
      final DVLogger logger = DVLogger(sinks: <DVLogSink>[sink]);
      logger.info('connecting', context: <String, Object?>{
        'url': 'postgres://app:hunter2-correct-horse@db.internal:5432/shop',
      });

      expect(
        sink.records.single.context['url'],
        isNot(contains('hunter2-correct-horse')),
      );
      expect(sink.records.single.context['url'], contains('db.internal'));
    });

    test('a secret quoted back by an upstream error is redacted', () {
      DVSecrets.configure(<String, String>{
        'OPENAI_API_KEY': 'sk-proj-abcdef123456',
      });
      const DVSecrets().get('OPENAI_API_KEY');

      final DVMemoryLogSink sink = DVMemoryLogSink();
      final DVLogger logger = DVLogger(sinks: <DVLogSink>[sink]);
      logger.error(
        'upstream rejected the request',
        error: StateError('invalid key sk-proj-abcdef123456 for org'),
      );

      expect(
        sink.records.single.error,
        isNot(contains('sk-proj-abcdef123456')),
      );
      expect(sink.records.single.error, contains('for org'));
    });

    test('a secret nested inside a context map is redacted too', () {
      DVSecrets.configure(<String, String>{
        'WEBHOOK_SIGNING_KEY': 'whsec_0123456789ab',
      });
      const DVSecrets().get('WEBHOOK_SIGNING_KEY');

      final DVMemoryLogSink sink = DVMemoryLogSink();
      final DVLogger logger = DVLogger(sinks: <DVLogSink>[sink]);
      logger.warn('replaying', context: <String, Object?>{
        'request': <String, Object?>{
          'headers': <String>['x-signature: whsec_0123456789ab'],
        },
      });

      expect(
        sink.records.single.context.toString(),
        isNot(contains('whsec_0123456789ab')),
      );
    });

    test('a PUBLIC_ value is left alone', () {
      // Deliberately shipped to every visitor. Blanking it out of the logs
      // hides configuration people are trying to read and protects nothing
      // that was ever private.
      DVSecrets.configure(<String, String>{
        'PUBLIC_STRIPE_KEY': 'pk_live_visible123',
      });
      const DVSecrets().get('PUBLIC_STRIPE_KEY');

      final DVMemoryLogSink sink = DVMemoryLogSink();
      final DVLogger logger = DVLogger(sinks: <DVLogSink>[sink]);
      logger.info('publishable key pk_live_visible123 in use');

      expect(sink.records.single.message, contains('pk_live_visible123'));
    });

    test('a value too short to match safely does not shred the line', () {
      // Substring replacement on a two-character value strikes inside
      // ordinary words and leaves a log nobody can read, which is its own
      // outage. The floor is documented on DVSecrets rather than silent.
      DVSecrets.configure(<String, String>{'MODE': 'on'});
      const DVSecrets().get('MODE');

      final DVMemoryLogSink sink = DVMemoryLogSink();
      final DVLogger logger = DVLogger(sinks: <DVLogSink>[sink]);
      logger.info('connection established, retrying once');

      expect(
        sink.records.single.message,
        'connection established, retrying once',
      );
    });

    test('rotation redacts the new value and still hides the old one', () async {
      // A rotated credential is not safe to print merely because it was
      // replaced: the old value stays live until every holder has caught up.
      DVSecrets.configure(<String, String>{
        'PAYSTACK_SECRET': 'sk_live_oldvalue00',
      });
      const DVSecrets().get('PAYSTACK_SECRET');
      await const DVSecrets().rotate('PAYSTACK_SECRET', 'sk_live_newvalue11');

      final DVMemoryLogSink sink = DVMemoryLogSink();
      final DVLogger logger = DVLogger(sinks: <DVLogSink>[sink]);
      logger.info('rotated sk_live_oldvalue00 to sk_live_newvalue11');

      expect(
        sink.records.single.message,
        isNot(contains('sk_live_oldvalue00')),
      );
      expect(
        sink.records.single.message,
        isNot(contains('sk_live_newvalue11')),
      );
    });

    test('a record carrying no secret is unchanged', () {
      DVSecrets.configure(<String, String>{
        'PAYSTACK_SECRET': 'sk_live_9f2c4ab7d1e6',
      });
      const DVSecrets().get('PAYSTACK_SECRET');

      final DVMemoryLogSink sink = DVMemoryLogSink();
      final DVLogger logger = DVLogger(sinks: <DVLogSink>[sink]);
      logger.info('order placed',
          context: <String, Object?>{'orderId': 'A-1938'});

      expect(sink.records.single.message, 'order placed');
      expect(sink.records.single.context['orderId'], 'A-1938');
    });
  });

  group('traces', () {
    // The spec names traces alongside logs, and a trace is the worse of the
    // two to get wrong: spans usually leave the building for a hosted trace
    // backend, so a credential in an attribute is a credential handed to a
    // third party.
    test('a secret in a span attribute does not reach the exporter', () {
      DVSecrets.configure(<String, String>{
        'DATABASE_PASSWORD': 'hunter2-correct-horse',
      });
      const DVSecrets().get('DATABASE_PASSWORD');

      final DVMemoryTraceExporter exporter = DVMemoryTraceExporter();
      final DVSpan span = DVTracer(exporter: exporter).startSpan('query')
        ..setAttribute(
          'db.url',
          'postgres://app:hunter2-correct-horse@db.internal:5432/shop',
        )
        ..end();

      expect(
        span.attributes['db.url'],
        isNot(contains('hunter2-correct-horse')),
      );
      expect(span.attributes['db.url'], contains('db.internal'));
      expect(exporter.spans, hasLength(1));
    });

    test('a secret quoted by a recorded error is redacted', () {
      DVSecrets.configure(<String, String>{
        'OPENAI_API_KEY': 'sk-proj-abcdef123456',
      });
      const DVSecrets().get('OPENAI_API_KEY');

      final DVSpan span = DVTracer().startSpan('call')
        ..recordError(StateError('rejected sk-proj-abcdef123456 by org'));

      expect(
        span.attributes['error'],
        isNot(contains('sk-proj-abcdef123456')),
      );
      expect(span.attributes['error'], contains('by org'));
    });
  });

  group('the redactable set', () {
    test('a secret that was never resolved is not in it', () {
      // Honest about its own reach. Only a value DV.Secrets has handed out
      // can be matched, which is fine in practice -- code cannot log a secret
      // it never read -- and worth stating rather than implying.
      DVSecrets.configure(<String, String>{
        'UNUSED_SECRET': 'never_read_value_1',
      });

      expect(
        dvRedactSecrets('saw never_read_value_1'),
        'saw never_read_value_1',
      );
    });

    test('reset clears it, so one test cannot redact another run', () {
      DVSecrets.configure(<String, String>{
        'A_SECRET': 'value_from_test_one',
      });
      const DVSecrets().get('A_SECRET');
      expect(
        dvRedactSecrets('x value_from_test_one'),
        isNot(contains('value_from_test_one')),
      );

      DVSecrets.reset();
      expect(dvRedactSecrets('x value_from_test_one'), 'x value_from_test_one');
    });

    test('withSecrets puts the redaction set back as well as the values',
        () async {
      // Otherwise a value supplied for one test goes on blanking text in
      // every test after it, and the failure looks like a bug in the code
      // under test.
      await const DVTestHarness().withSecrets(
        <String, String>{'SCOPED_SECRET': 'inside_this_test_only'},
        () {
          const DVSecrets().get('SCOPED_SECRET');
          expect(
            dvRedactSecrets('v inside_this_test_only'),
            isNot(contains('inside_this_test_only')),
          );
        },
      );

      expect(
        dvRedactSecrets('v inside_this_test_only'),
        'v inside_this_test_only',
      );
    });
  });
}
