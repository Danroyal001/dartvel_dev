// DV.log: one structured stream for application code, the framework and the
// platform underneath it.
//
// What these pin down is the part a reader cannot see from a call site: a
// record carries its category and its fields as data, sensitive model fields
// and secrets never reach a sink however they were passed, and the record a
// device keeps can be read back exactly as it was written.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/dv.dart';
import 'package:test/test.dart';

class _Patient {
  _Patient(this.name, this.diagnosis);
  final String name;
  final String diagnosis;

  // What a generated data model has: its fields without the sensitive ones.
  Map<String, Object?> toPublicJson() => <String, Object?>{'name': name};

  @override
  String toString() => 'Patient($name, $diagnosis)';
}

void main() {
  setUp(() {
    DV.ObservabilityAndLogging.resetLogging();
    DVLogger.resetSensitiveFields();
  });
  tearDown(() {
    DV.ObservabilityAndLogging.resetLogging();
    DVLogger.resetSensitiveFields();
  });

  DVLogRecord last() => DV.ObservabilityAndLogging.recentLogs.last;

  group('DV.log', () {
    test('carries a category and fields as data, not as prose', () {
      DV.log('checkout completed',
          tag: 'checkout', context: <String, Object?>{'orderId': 'o-1'});

      expect(last().tag, 'checkout');
      expect(last().context['orderId'], 'o-1');
      expect(last().toJson()['tag'], 'checkout');
      expect(last().level, DVLogLevel.info);
    });

    test('levels below the floor are dropped, at or above are written', () {
      DV.log.debug('not written', tag: 'cache');
      DV.log.warn('written', tag: 'cache');
      DV.log.fatal('also written',
          tag: 'boot', error: StateError('no database'));

      final List<String> messages = DV.ObservabilityAndLogging.recentLogs
          .map((DVLogRecord record) => record.message)
          .toList();
      expect(messages, <String>['written', 'also written']);
      expect(last().level, DVLogLevel.fatal);
      expect(last().error, contains('no database'));
    });

    test('recent is the same buffer the diagnostics endpoint serves', () {
      DV.log('one');
      expect(DV.log.recent.single.message, 'one');
    });
  });

  group('redaction', () {
    test('a sensitive model field is redacted wherever it appears', () {
      dvRegisterSensitiveLogFields(<String>{'dateOfBirth', 'diagnosis'});

      DV.log('visit', context: <String, Object?>{
        'dateOfBirth': '1990-04-01',
        'visit': <String, Object?>{'diagnosis': 'flu', 'room': 4},
        'patients': <Object?>[
          <String, Object?>{'Diagnosis': 'cold'},
        ],
      });

      final Map<String, Object?> context = last().context;
      expect(context['dateOfBirth'], DVLogger.redactedValue);
      expect((context['visit']! as Map<Object?, Object?>)['diagnosis'],
          DVLogger.redactedValue);
      expect((context['visit']! as Map<Object?, Object?>)['room'], 4);
      expect(
          ((context['patients']! as List<Object?>).single!
              as Map<Object?, Object?>)['Diagnosis'],
          DVLogger.redactedValue,
          reason: 'field names match case-insensitively');
    });

    test('a sensitive field name is matched exactly, not as a substring', () {
      dvRegisterSensitiveLogFields(<String>{'number'});

      DV.log('order', context: <String, Object?>{'orderNumber': 12});

      expect(last().context['orderNumber'], 12,
          reason: 'a model field called number is not every key containing '
              'number');
    });

    test('a data model in the fields is written as its public form', () {
      DV.log('admitted',
          context: <String, Object?>{'patient': _Patient('Ada', 'flu')});

      expect(last().context['patient'], <String, Object?>{'name': 'Ada'},
          reason: 'toString would carry the diagnosis');
    });

    test('secret-shaped values are redacted without being declared', () {
      const String jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl';
      DV.log('call failed: Authorization: Bearer abc123def456ghi789 '
          'token=$jwt url=https://admin:hunter22@db.internal/app');

      final String message = last().message;
      expect(message, isNot(contains('abc123def456ghi789')));
      expect(message, isNot(contains(jwt)));
      expect(message, isNot(contains('hunter22')));
      expect(message, contains('db.internal'),
          reason: 'only the credential goes, not the host');
    });

    test('key names that look like credentials are still redacted', () {
      DV.log('signin', context: <String, Object?>{'password': 'pw'});
      expect(last().context['password'], DVLogger.redactedValue);
    });
  });

  group('DVLogRecord', () {
    test('reads back exactly what it wrote', () {
      final DVLogRecord written = DVLogRecord(
        level: DVLogLevel.error,
        message: 'payment declined',
        tag: 'billing',
        time: DateTime.utc(2026, 10, 9, 12),
        context: const <String, Object?>{'attempt': 2},
        code: 'DV-PAY-001',
        error: 'StateError: declined',
        stackTrace: '#0 main',
        traceId: '0af7651916cd43dd8448eb211c80319c',
        spanId: 'b7ad6b7169203331',
        event: 'payment_declined',
      );

      final DVLogRecord read = DVLogRecord.fromJson(written.toJson());

      expect(read.toJsonLine(), written.toJsonLine());
    });

    test('refuses something that is not a record', () {
      expect(() => DVLogRecord.fromJson(<String, Object?>{'message': 1}),
          throwsFormatException);
      expect(
          () => DVLogRecord.fromJson(<String, Object?>{
                'time': '2026-10-09T12:00:00Z',
                'level': 'loud',
                'message': 'x',
              }),
          throwsFormatException);
    });
  });
}
