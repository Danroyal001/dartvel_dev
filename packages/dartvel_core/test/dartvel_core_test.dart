import 'dart:convert';
import 'dart:io' as io;
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/notifications/push.dart' as push;
import 'package:dartvel_core/src/notifications/push_notifications.dart'
    as legacy_push;
import 'package:dartvel_core/src/websocket/ws.dart' as websocket;
import 'package:dartvel_shelf/dartvel_shelf.dart' as shelf;
import 'package:test/test.dart';

void main() {
  test('Request.formData returns strongly typed form values', () async {
    final request = shelf.Request(
      method: 'POST',
      url: Uri.parse('https://example.test/forms'),
      headers: shelf.Headers(<String, String>{
        'content-type': 'application/x-www-form-urlencoded',
      }),
      bodyStream: Stream<List<int>>.value(
        utf8.encode('name=Ada&role=admin'),
      ),
    );

    expect(await request.formData(), <String, Object?>{
      'name': 'Ada',
      'role': 'admin',
    });
  });

  test('push notification payloads use exact object map types', () {
    final notification = push.PushNotification(
      id: 'message-1',
      data: <String, Object?>{'attempt': 1, 'urgent': true},
    );
    const legacyMessage = legacy_push.NotificationMessage(
      title: 'Update',
      body: 'Completed',
      data: <String, Object?>{'attempt': 1},
    );

    expect(notification.data, <String, Object?>{'attempt': 1, 'urgent': true});
    expect(legacyMessage.data, <String, Object?>{'attempt': 1});
  });

  test('platform settings use exact object map types', () {
    const config = PlatformConfig(
      enabledPlatforms: <Platform>{Platform.web},
      platformSettings: <Platform, Map<String, Object?>>{
        Platform.web: <String, Object?>{'renderer': 'canvaskit', 'debug': true},
      },
    );

    expect(config.getSettingsFor(Platform.web), <String, Object?>{
      'renderer': 'canvaskit',
      'debug': true,
    });
    expect(config.isPlatformEnabled(Platform.android), isFalse);
  });

  test('websocket messages round-trip typed JSON payloads', () {
    final original = websocket.WsMessage(
      type: 'status',
      data: <String, Object?>{'ready': true, 'count': 2},
      id: 'message-1',
    );
    final decoded = websocket.WsMessage.fromJson(original.toJson());

    expect(decoded.type, 'status');
    expect(decoded.id, 'message-1');
    expect(decoded.data, <String, Object?>{'ready': true, 'count': 2});
    expect(original.toJsonString(), contains('"type":"status"'));
  });

  test('DVModel contains only generation metadata', () {
    const model = DVModel(searchable: true, billable: true, nativePrice: 100);

    expect(model.searchable, isTrue);
    expect(model.billable, isTrue);
    expect(model.nativePrice, 100);
  });

  test('generated model factory and serializer registries are typed', () {
    registerDVModelFactory<int>(() => 42);
    registerDVModelSerializer<int>((value) => <String, Object?>{
          'value': value,
        });

    expect(createDVModel<int>(), 42);
    expect(serializeDVModel<int>(42), <String, Object?>{'value': 42});
  });

  test('analytics fails clearly without an explicit provider', () async {
    Analytics.clear();
    expect(Analytics.logEvent('missing_provider'), throwsStateError);

    final provider = LocalAnalyticsProvider();
    Analytics.register(provider);
    await Analytics.logEvent('configured', <String, Object>{'ok': true});
    expect(provider.events.single.name, 'configured');
    Analytics.clear();
  });

  test('in-memory search provider filters, facets, and paginates typed models',
      () async {
    final provider = DVInMemorySearchProvider<int, Set<int>>(
      records: <int>[1, 2, 3, 4],
      document: (value) => 'record $value',
      facetMatcher: (value, facets) => facets == null || facets.contains(value),
    );

    final result = await provider.query(
      'record',
      facets: <int>{2, 3, 4},
      page: 2,
      perPage: 2,
    );

    expect(result.items, <int>[4]);
    expect(result.total, 3);
    expect(result.page, 2);
    expect(result.perPage, 2);
  });

  test('unconfigured search provider fails instead of returning a false result',
      () async {
    const provider = DVUnconfiguredSearchProvider<int, void>();

    expect(
      () => provider.query('record'),
      throwsA(isA<StateError>()),
    );
  });

  test('Shorebird availability parsing does not report false positives', () {
    expect(ShorebirdUpdater.parseAvailability('{"available":true}'), isTrue);
    expect(
      ShorebirdUpdater.parseAvailability('{"updateAvailable":false}'),
      isFalse,
    );
    expect(
        ShorebirdUpdater.parseAvailability('No patches available.'), isFalse);
    expect(
      ShorebirdUpdater.parseAvailability('Patch available for production'),
      isTrue,
    );
    expect(ShorebirdUpdater.parseAvailability(''), isFalse);
  });

  group('Res', () {
    test('json creates correct response', () async {
      final data = {'message': 'hello'};
      final res = Res.json(data);
      expect(res.status, 200);
      expect(res.headers.get('content-type'), contains('application/json'));

      final body = await res.body!.text();
      expect(jsonDecode(body), data);
    });

    test('text creates correct response', () async {
      final text = 'hello world';
      final res = Res.text(text);
      expect(res.status, 200);
      final body = await res.body!.text();
      expect(body, text);
    });

    test('notFound creates 404 response', () async {
      final res = Res.notFound();
      expect(res.status, 404);
      final body = await res.body!.text();
      expect(body, 'Not found');
    });

    test('notFound with message', () async {
      final res = Res.notFound('Custom error');
      expect(res.status, 404);
      final body = await res.body!.text();
      expect(body, 'Custom error');
    });
  });

  group('DVCSRF', () {
    test('generates non-empty random-looking tokens', () {
      const csrf = DVCSRF();
      final first = csrf.token();
      final second = csrf.token();

      expect(first, hasLength(greaterThanOrEqualTo(32)));
      expect(second, hasLength(greaterThanOrEqualTo(32)));
      expect(first, isNot(second));
      expect(csrf.validate(first), isTrue);
    });

    test('validates unsafe requests with matching tokens', () {
      const csrf = DVCSRF();
      final token = csrf.token();

      expect(
        csrf.validateRequest(
          method: 'POST',
          headerToken: token,
          bodyToken: token,
        ),
        isTrue,
      );
      expect(
        csrf.validateRequest(method: 'POST', headerToken: null),
        isFalse,
      );
      expect(
        csrf.validateRequest(
          method: 'POST',
          headerToken: token,
          bodyToken: '${token}x',
        ),
        isFalse,
      );
      expect(
        csrf.validateRequest(method: 'GET', headerToken: null),
        isTrue,
      );
    });
  });

  group('AuthUser', () {
    test('serializes metadata with exact object map types', () {
      final user = AuthUser.fromJson(<String, Object?>{
        'id': 'user-1',
        'email': 'user@example.com',
        'name': 'User One',
        'metadata': <Object?, Object?>{
          'role': 'admin',
          'loginCount': 3,
        },
      });

      expect(user.metadata, <String, Object?>{
        'role': 'admin',
        'loginCount': 3,
      });
      expect(user.toJson(), <String, Object?>{
        'id': 'user-1',
        'email': 'user@example.com',
        'name': 'User One',
        'metadata': <String, Object?>{
          'role': 'admin',
          'loginCount': 3,
        },
      });
    });
  });

  group('UpdateCheckResult', () {
    test('parses metadata with exact object map types', () {
      final result = UpdateCheckResult.fromJson(<String, Object?>{
        'updateAvailable': true,
        'version': '1.2.3',
        'downloadUrl': 'https://updates.example.test/app.patch',
        'metadata': <Object?, Object?>{
          'provider': 'shorebird',
          'build': 7,
        },
      });

      expect(result.updateAvailable, isTrue);
      expect(result.metadata, <String, Object?>{
        'provider': 'shorebird',
        'build': 7,
      });
    });
  });

  group('Queues, signals, messaging, and policies', () {
    test('queues dispatch and run typed jobs', () async {
      const harness = DVTestHarness();
      harness.resetQueues();
      final processed = <String>[];

      const queues = DVQueues();
      queues.register<String>((payload) {
        processed.add(payload);
      });

      final envelope = await queues.dispatch<String>('welcome-email');
      expect(envelope.queue, 'default');

      expect(await queues.work(), 1);
      expect(processed, ['welcome-email']);
      expect(await queues.pending(), isEmpty);
    });

    test('signal payloads use queues for background delivery', () async {
      const harness = DVTestHarness();
      harness.resetSignals();

      const queues = DVQueues();
      final delivered = <int>[];
      queues.register<int>(delivered.add);

      await queues.dispatch<int>(42, queue: 'signals');
      expect(await queues.work(queue: 'signals'), 1);

      expect(delivered, [42]);
    });

    test('mail and notifications use concrete local providers', () async {
      const harness = DVTestHarness();
      final mailProvider = harness.fakeMail();

      await const DVNotificationMail().send(
        const DVMailMessage(
          from: DVMailAddress('system@example.com'),
          to: <DVMailAddress>[DVMailAddress('user@example.com')],
          subject: 'Welcome',
          text: 'Hello',
        ),
      );
      expect(mailProvider.sent.single.subject, 'Welcome');

      final notificationProvider = harness.fakeNotifications();

      await const DVNotificationsService().send(
        'user-1',
        const DVNotificationMessage(title: 'Hi', body: 'Body'),
      );
      expect(notificationProvider.sent.single.recipient, 'user-1');
    });

    test('mail and notifications fail without explicit providers', () async {
      const harness = DVTestHarness();
      harness.clearMailProvider();
      harness.clearNotificationProviders();

      expect(
        () => const DVNotificationMail().send(
          const DVMailMessage(
            from: DVMailAddress('system@example.com'),
            to: <DVMailAddress>[DVMailAddress('user@example.com')],
            subject: 'Missing provider',
            text: 'This must fail clearly.',
          ),
        ),
        throwsStateError,
      );
      expect(
        () => const DVNotificationsService().send(
          'user-1',
          const DVNotificationMessage(title: 'Missing', body: 'Provider'),
        ),
        throwsStateError,
      );

      harness.fakeMail();
      harness.fakeNotifications();
    });

    test('test harness installs explicit fake queue provider', () async {
      const harness = DVTestHarness();
      final adapter = harness.fakeQueue();
      const queues = DVQueues();

      await queues.dispatch<String>('queued', queue: 'tests');

      expect(await adapter.pending('tests'), hasLength(1));
    });

    test('authorization and cache invalidation are typed', () async {
      const authz = DVAuthAuthorization();
      authz.register<String, int>(DVPolicyAction.view, (user, resource) {
        return user == 'admin' && resource == 7;
      });

      expect(
        await authz.can<String, int>('admin', DVPolicyAction.view, 7),
        isTrue,
      );
      expect(
        await authz.can<String, int>('guest', DVPolicyAction.view, 7),
        isFalse,
      );
      expect(DVPolicies.refund, 'refund');

      const invalidation = DVCacheTags();
      invalidation.tag('users:7', <String>['users', 'users:7']);
      expect(invalidation.keysForTag('users'), contains('users:7'));
      expect(invalidation.revalidateTag('users'), contains('users:7'));
      expect(invalidation.keysForTag('users'), isEmpty);
    });

    test('dead-lettered jobs can be retried and flushed', () async {
      const harness = DVTestHarness();
      harness.resetQueues();
      const queues = DVQueues();

      await queues.dispatch<String>(
        'unhandled',
        queue: 'mail',
        maxAttempts: 1,
      );
      expect(await queues.work(queue: 'mail'), 0);

      final failed = await queues.deadLetters('mail');
      expect(failed, hasLength(1));
      expect(await queues.retry(failed.single.id), isTrue);
      expect(await queues.deadLetters('mail'), isEmpty);
      expect(await queues.pending('mail'), hasLength(1));

      expect(await queues.flush(queue: 'mail'), 1);
      expect(await queues.pending('mail'), isEmpty);
    });
  });

  group('DVShell', () {
    test('runs a command and returns typed output', () async {
      final temp = io.Directory.systemTemp.createTempSync('dartvel_core_shell');
      try {
        final script = io.File('${temp.path}/message.dart')
          ..writeAsStringSync("void main() => print('core-shell');");

        final result = await const DVShell().run(
          '${io.Platform.resolvedExecutable} ${script.path}',
        );

        expect(result.succeeded, isTrue);
        expect(result.exitCode, 0);
        expect(result.stdoutText, contains('core-shell'));
      } finally {
        temp.deleteSync(recursive: true);
      }
    });
  });

  group('DVShell', () {
    test('future extension returns stdout text', () async {
      final temp = io.Directory.systemTemp.createTempSync('dartvel_core_shell');
      try {
        final script = io.File('${temp.path}/print_message.dart')
          ..writeAsStringSync("void main() => print('dartvel-shell');");

        final text = await const DVShell()
            .run('${io.Platform.resolvedExecutable} ${script.path}')
            .text();

        expect(text, contains('dartvel-shell'));
      } finally {
        temp.deleteSync(recursive: true);
      }
    });

    test('expands glob arguments relative to the working directory', () async {
      final temp = io.Directory.systemTemp.createTempSync('dartvel_core_glob');
      try {
        final script = io.File('${temp.path}/print_args.dart')
          ..writeAsStringSync('void main(List<String> args) => print(args);');
        io.File('${temp.path}/a.dart').writeAsStringSync('');
        io.File('${temp.path}/b.dart').writeAsStringSync('');

        final result = await const DVShell().run(
          '${io.Platform.resolvedExecutable} ${script.path} *.dart',
          workingDirectory: temp.path,
        );

        expect(result.exitCode, 0);
        expect(result.stdoutText, contains('a.dart'));
        expect(result.stdoutText, contains('b.dart'));
      } finally {
        temp.deleteSync(recursive: true);
      }
    });

    test('runs typed commands with env helpers and safe arguments', () async {
      final temp =
          io.Directory.systemTemp.createTempSync('dartvel_core_shell_parts');
      try {
        final script = io.File('${temp.path}/print_env_args.dart')
          ..writeAsStringSync('''
import 'dart:io';

void main(List<String> args) {
  print(Platform.environment['DARTVEL_TEST_ENV']);
  print(args);
}
''');

        final command = DVShellCommand(io.Platform.resolvedExecutable)
            .arg(script.path)
            .arg('hello;not-a-second-command')
            .env('DARTVEL_TEST_ENV', 'typed-env');
        final result = await const DVShell().runCommand(command);

        expect(result.exitCode, 0);
        expect(result.stdoutText, contains('typed-env'));
        expect(result.stdoutText, contains('hello;not-a-second-command'));
      } finally {
        temp.deleteSync(recursive: true);
      }
    });
  });
}
