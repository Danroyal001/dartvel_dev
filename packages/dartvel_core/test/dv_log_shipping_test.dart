// dartvel.logging, and shipping a device's logs to the application's own
// backend.
//
// Shipping is off unless a project turns it on, and when it is on it sends
// less than a reader might assume: records at warn and above, already
// redacted on the device, with an install id and a release and nothing that
// names a person. These tests pin each of those, because every one of them
// would still "work" if it were wrong.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('DVLogConfig', () {
    test('defaults: info, a 2 MB file, native mirroring, no shipping', () {
      final DVLogConfig config = DVLogConfig.parse(null);

      expect(config.level, DVLogLevel.info);
      expect(config.native, isTrue);
      expect(config.file, isTrue);
      expect(config.fileMaxBytes * config.fileCount, 2 * 1024 * 1024);
      expect(config.fileRetention, const Duration(days: 7));
      expect(config.ship, isFalse,
          reason: 'logs leave the device only when a project says so');
      expect(config.shipLevel, DVLogLevel.warn);
    });

    test('reads every setting', () {
      final DVLogConfig config = DVLogConfig.parse(<String, Object?>{
        'level': 'debug',
        'native': false,
        'file': <String, Object?>{
          'maxBytes': 65536,
          'files': 4,
          'retentionDays': 2,
        },
        'ship': <String, Object?>{
          'enabled': true,
          'level': 'error',
          'batch': 20,
          'perInstallPerHour': 100,
          'maxBytes': 65536,
        },
      });

      expect(config.level, DVLogLevel.debug);
      expect(config.native, isFalse);
      expect(config.fileMaxBytes, 65536);
      expect(config.fileCount, 4);
      expect(config.fileRetention, const Duration(days: 2));
      expect(config.ship, isTrue);
      expect(config.shipLevel, DVLogLevel.error);
      expect(config.shipBatch, 20);
      expect(config.ingestPerInstallPerHour, 100);
      expect(config.ingestMaxBytes, 65536);
      expect(DVLogConfig.parse(config.toDeclaration()).toDeclaration(),
          config.toDeclaration(),
          reason: 'the generated runtime embeds the declaration');
    });

    test('file: false keeps nothing on the device', () {
      expect(DVLogConfig.parse(<String, Object?>{'file': false}).file, isFalse);
    });

    test('refuses what it cannot honour, naming the key', () {
      void refuses(Map<String, Object?> section, String key) => expect(
          () => DVLogConfig.parse(section),
          throwsA(isA<ArgumentError>()
              .having((ArgumentError error) => error.name, 'name', key)));

      refuses(<String, Object?>{'levle': 'info'}, 'dartvel.logging.levle');
      refuses(<String, Object?>{'level': 'loud'}, 'dartvel.logging.level');
      refuses(<String, Object?>{'native': 'yes'}, 'dartvel.logging.native');
      refuses(<String, Object?>{
        'file': <String, Object?>{'maxBytes': 10}
      }, 'dartvel.logging.file.maxBytes');
      refuses(<String, Object?>{
        'file': <String, Object?>{'files': 0}
      }, 'dartvel.logging.file.files');
      refuses(<String, Object?>{
        'ship': <String, Object?>{'enabled': 1}
      }, 'dartvel.logging.ship.enabled');
      refuses(<String, Object?>{
        'ship': <String, Object?>{'level': 'debug', 'enabled': true}
      }, 'dartvel.logging.ship.level');
      refuses(<String, Object?>{
        'ship': <String, Object?>{'endpoint': 'https://elsewhere'}
      }, 'dartvel.logging.ship.endpoint');
    });
  });

  group('DVLogShipper', () {
    late List<String> bodies;
    late int status;
    late DateTime now;

    DVLogShipper shipper({int batch = 3, int queue = 10}) => DVLogShipper(
          post: (String body) async {
            bodies.add(body);
            return status;
          },
          installId: '0123456789abcdef0123456789abcdef',
          release: '1.4.0',
          platform: 'android',
          batch: batch,
          queue: queue,
          interval: const Duration(days: 1),
        );

    DVLogRecord record(String message,
            {DVLogLevel level = DVLogLevel.warn, String? tag}) =>
        DVLogRecord(level: level, message: message, tag: tag, time: now);

    setUp(() {
      bodies = <String>[];
      status = 201;
      now = DateTime.utc(2026, 10, 9, 12);
    });

    test('sends warn and above, in batches, naming the install only', () async {
      final DVLogShipper sending = shipper();
      sending.write(record('below', level: DVLogLevel.info));
      sending.write(record('one'));
      sending.write(record('two', level: DVLogLevel.error));

      expect(await sending.flush(), 2);
      final Map<String, Object?> body =
          jsonDecode(bodies.single) as Map<String, Object?>;
      expect(body.keys.toSet(),
          <String>{'install', 'release', 'platform', 'records'},
          reason: 'nothing else describes the device or the person');
      expect(body['install'], '0123456789abcdef0123456789abcdef');
      expect(
          (body['records']! as List<Object?>)
              .map((Object? item) => (item! as Map<String, Object?>)['message']),
          <String>['one', 'two']);
      expect(sending.pending, 0);
    });

    test('a batch the backend could not take is kept and sent again',
        () async {
      final DVLogShipper sending = shipper();
      sending.write(record('kept'));

      status = 503;
      expect(await sending.flush(), 0);
      expect(sending.pending, 1);

      status = 201;
      expect(await sending.flush(), 1);
      expect(sending.pending, 0);
    });

    test('a batch the backend refuses outright is dropped, not retried',
        () async {
      final DVLogShipper sending = shipper();
      sending.write(record('refused'));

      status = 400;
      await sending.flush();
      expect(sending.pending, 0, reason: 'a 400 will never succeed');
      expect(sending.dropped, 1);
    });

    test('a full queue drops the oldest and counts them', () {
      final DVLogShipper sending = shipper(queue: 3, batch: 100);
      for (int index = 0; index < 5; index++) {
        sending.write(record('r$index'));
      }
      expect(sending.pending, 3);
      expect(sending.dropped, 2);
    });

    test('a send that throws never throws into the code that logged',
        () async {
      final DVLogShipper sending = DVLogShipper(
        post: (String body) => throw StateError('offline'),
        installId: '0123456789abcdef0123456789abcdef',
        release: '1',
        platform: 'web',
        interval: const Duration(days: 1),
      );
      sending.write(record('offline'));

      expect(await sending.flush(), 0);
      expect(sending.pending, 1);
    });
  });

  group('DVLogIngest', () {
    late DVMemoryLogSink serverLog;
    late DVLogger logger;
    late List<String> forwarded;
    late DateTime now;

    DVLogIngest ingest({int perInstallPerHour = 100, int maxBytes = 65536}) =>
        DVLogIngest(
          logger: logger,
          perInstallPerHour: perInstallPerHour,
          maxBytes: maxBytes,
          clock: () => now,
          forward: (String body) async => forwarded.add(body),
        );

    List<int> batch(List<Map<String, Object?>> records,
            {String install = '0123456789abcdef0123456789abcdef'}) =>
        utf8.encode(jsonEncode(<String, Object?>{
          'install': install,
          'release': '1.4.0',
          'platform': 'ios',
          'records': records,
        }));

    Map<String, Object?> line(String message, {Object? level = 'error'}) =>
        <String, Object?>{
          'time': '2026-10-09T11:59:00.000Z',
          'level': level,
          'message': message,
          'tag': 'checkout',
          'context': <String, Object?>{'orderId': 'o-1', 'password': 'pw'},
        };

    setUp(() {
      serverLog = DVMemoryLogSink();
      logger = DVLogger(sinks: <DVLogSink>[serverLog]);
      forwarded = <String>[];
      now = DateTime.utc(2026, 10, 9, 12);
    });

    test('writes each record into the server stream, as the client', () async {
      final DVLogIngestResult result =
          await ingest().accept(batch(<Map<String, Object?>>[line('declined')]));

      expect(result.status, 201);
      final DVLogRecord written = serverLog.records.single;
      expect(written.message, 'declined');
      expect(written.tag, 'checkout');
      expect(written.level, DVLogLevel.error);
      expect(written.time, DateTime.utc(2026, 10, 9, 11, 59),
          reason: 'when it happened on the device, not when it arrived');
      expect(written.context['client'], <String, Object?>{
        'install': '0123456789abcdef0123456789abcdef',
        'release': '1.4.0',
        'platform': 'ios',
      });
      expect(written.context['password'], DVLogger.redactedValue,
          reason: 'redacted again on the server, whatever the client did');
    });

    test('hands the accepted batch to the forwarding hook', () async {
      await ingest().accept(batch(<Map<String, Object?>>[line('declined')]));

      final Map<String, Object?> sent =
          jsonDecode(forwarded.single) as Map<String, Object?>;
      expect(sent['install'], '0123456789abcdef0123456789abcdef');
      final Map<String, Object?> first =
          (sent['records']! as List<Object?>).single! as Map<String, Object?>;
      expect((first['context']! as Map<String, Object?>)['password'],
          DVLogger.redactedValue);
      expect(sent.containsKey('source'), isFalse,
          reason: 'the client address is not forwarded');
    });

    test('refuses a body over the limit and anything that is not a batch',
        () async {
      expect((await ingest(maxBytes: 64).accept(batch(<Map<String, Object?>>[
        line('x' * 200),
      ])))
          .status, 413);
      expect((await ingest().accept(utf8.encode('not json'))).status, 400);
      expect(
          (await ingest().accept(batch(<Map<String, Object?>>[line('x')],
                  install: 'me@example.com')))
              .status,
          400,
          reason: 'an install id is 32 hex characters, never an identity');
      expect(serverLog.records, isEmpty);
    });

    test('drops a malformed record and keeps the rest', () async {
      final DVLogIngestResult result = await ingest().accept(batch(
          <Map<String, Object?>>[line('ok'), line('bad', level: 'loud')]));

      expect(result.status, 201);
      expect(serverLog.records.map((DVLogRecord record) => record.message),
          <String>['ok']);
    });

    test('counts records past the per-install hour rather than storing them',
        () async {
      final DVLogIngest limited = ingest(perInstallPerHour: 2);
      final DVLogIngestResult result = await limited.accept(batch(
          <Map<String, Object?>>[line('1'), line('2'), line('3')]));

      expect(result.status, 202);
      expect(serverLog.records.map((DVLogRecord record) => record.message),
          contains('1'));
      expect(
          serverLog.records
              .where((DVLogRecord record) => record.tag == 'checkout')
              .length,
          2);
      expect(limited.limited('0123456789abcdef0123456789abcdef'), 1);
    });
  });
}
