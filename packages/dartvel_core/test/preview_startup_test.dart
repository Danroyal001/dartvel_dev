// Preview Environments, started: what a preview process installs before it
// serves anything, and that nothing at all is installed in any other
// environment.
//
// Every silent failure here has a production twin that looks identical from
// inside a preview test -- middleware installed everywhere passes every
// "is it installed in a preview" assertion -- so each group carries its
// control.
import 'dart:convert';
import 'dart:io' hide Platform;
import 'dart:io' as io show Platform;

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

final DVPreviewIdentity id = DVPreviewIdentity.forBranch(
  app: 'shop',
  branch: 'feature/cart',
);

const String productionUrl = 'postgres://app:pw@db.internal:5432/shop';

Map<String, String> previewEnvironment({
  DVPreviewVisibility visibility = DVPreviewVisibility.public,
  Map<String, String> overrides = const <String, String>{},
  Set<String> remove = const <String>{},
}) => <String, String>{
  ...DVPreviewDeployment(
    identity: id,
    visibility: visibility,
    secrets: const <String, String>{'DATABASE_URL': productionUrl},
    productionOrigin: 'https://shop.example',
    productionDatabase: 'shop',
  ).variables,
  ...overrides,
}..removeWhere((String key, String _) => remove.contains(key));

class RecordingMail implements DVMailProvider {
  final List<DVMailMessage> sent = <DVMailMessage>[];
  @override
  Future<void> send(DVMailMessage message) async => sent.add(message);
}

const DVMailMessage welcome = DVMailMessage(
  from: DVMailAddress('shop@example.com'),
  to: <DVMailAddress>[DVMailAddress('ada@example.com')],
  subject: 'Welcome',
  text: 'Hello',
);

Request request(String path) => Request(
  method: 'GET',
  url: Uri.parse('https://preview.example$path'),
  headers: Headers(const <String, String>{}),
  bodyStream: const Stream<List<int>>.empty(),
);

void main() {
  late RecordingMail mail;

  setUp(() {
    mail = RecordingMail();
    const DVNotificationMail().useProvider(mail);
  });

  tearDown(() {
    DVPreviewServer.reset();
    const DVDatabase().unconfigure();
  });

  group('outside a preview', () {
    test(
      'nothing is installed, even with every preview variable present',
      () async {
        // A production deploy whose settings were copied from a preview's.
        final DVPreviewServer? server = DVPreviewServer.start(
          previewEnvironment(
            overrides: const <String, String>{
              'DARTVEL_ENVIRONMENT': 'production',
            },
          ),
        );

        expect(server, isNull);
        expect(DVPreviewServer.current, isNull);
        expect(DVPreviewOutbound.isActive, isFalse);
        await const DVNotificationMail().send(welcome);
        expect(mail.sent, hasLength(1), reason: 'production mail is sent');
        expect(const DVQueues().namespace, isNull);
        expect(
          () => const DVDatabase().adapter,
          throwsStateError,
          reason: 'production\'s database is the application\'s to configure',
        );
      },
    );

    test('an environment that names nothing is not a preview', () {
      expect(DVPreviewServer.start(const <String, String>{}), isNull);
      expect(DVPreviewOutbound.isActive, isFalse);
    });
  });

  group('in a preview', () {
    test(
      'mail is captured, queues are namespaced and the database is its own',
      () async {
        final DVPreviewServer server = DVPreviewServer.start(
          previewEnvironment(),
        )!;

        expect(DVPreviewServer.current, same(server));
        await const DVNotificationMail().send(welcome);
        expect(mail.sent, isEmpty);
        expect(DVPreviewOutbound.mail, hasLength(1));

        expect(const DVQueues().namespace, id.queueNamespace);

        final DVDatabaseAdapter adapter = const DVDatabase().adapter;
        expect(adapter, isA<DVPostgresDatabaseAdapter>());
        expect(
          (adapter as DVPostgresDatabaseAdapter).database,
          id.database,
          reason:
              'DATABASE_URL names production\'s database; the preview '
              'resolves its own on the same server',
        );
        expect(adapter.host, 'db.internal');
      },
    );

    test(
      'the wrapped handler is noindex and serves a disallow-all robots.txt',
      () async {
        final DVPreviewServer server = DVPreviewServer.start(
          previewEnvironment(),
        )!;
        final handler = server.wrap((Request r) async => Response.text('pong'));

        final Response ping = await handler(request('/api/ping'));
        expect(ping.headers.get('x-robots-tag'), contains('noindex'));
        final Response robots = await handler(request('/robots.txt'));
        expect(await robots.body!.text(), contains('Disallow: /'));
      },
    );

    test('starting twice is the one preview', () {
      final DVPreviewServer first = DVPreviewServer.start(
        previewEnvironment(),
      )!;
      expect(DVPreviewServer.start(previewEnvironment()), same(first));
    });

    test('a later attempt to configure production\'s database is refused', () {
      DVPreviewServer.start(previewEnvironment());
      expect(
        () => const DVDatabase().configure(
          DVPostgresDatabaseAdapter(host: 'db.internal', database: 'shop'),
        ),
        throwsStateError,
      );
      // Its own database is still allowed, under whatever connection.
      const DVDatabase().configure(
        DVPostgresDatabaseAdapter(
          host: 'other.internal',
          database: id.database,
        ),
      );
    });
  });

  group('a preview refuses to start', () {
    void refused(Map<String, String> environment, String because) {
      expect(
        () => DVPreviewServer.start(environment),
        throwsA(
          isA<DVPreviewStartupException>().having(
            (DVPreviewStartupException e) => e.message,
            'message',
            contains(because),
          ),
        ),
      );
      expect(DVPreviewServer.current, isNull);
    }

    test('when it cannot read its identity', () {
      refused(
        previewEnvironment(remove: const <String>{'DARTVEL_PREVIEW'}),
        'DARTVEL_PREVIEW',
      );
    });

    test('when its queue namespace is missing or is not its own', () {
      refused(
        previewEnvironment(remove: const <String>{'DARTVEL_QUEUE_NAMESPACE'}),
        'DARTVEL_QUEUE_NAMESPACE',
      );
      refused(
        previewEnvironment(
          overrides: const <String, String>{
            'DARTVEL_QUEUE_NAMESPACE': 'default',
          },
        ),
        'DARTVEL_QUEUE_NAMESPACE',
      );
    });

    test('when its database is missing or is not its identity\'s', () {
      refused(
        previewEnvironment(remove: const <String>{'DARTVEL_DATABASE'}),
        'DARTVEL_DATABASE',
      );
      refused(
        previewEnvironment(
          overrides: const <String, String>{
            'DARTVEL_DATABASE': 'shop_preview_other_0000abcd',
          },
        ),
        'DARTVEL_DATABASE',
      );
    });

    test('when its database is production\'s', () {
      // Named exactly as the identity would name it, so only the comparison
      // with production's catches it.
      refused(
        previewEnvironment(
          overrides: <String, String>{
            'DARTVEL_PRODUCTION_DATABASE': id.database,
          },
        ),
        'production',
      );
    });

    test('when DATABASE_URL cannot be read', () {
      refused(
        previewEnvironment(
          overrides: const <String, String>{
            'DATABASE_URL': 'redis://cache.internal/0',
          },
        ),
        'DATABASE_URL',
      );
    });

    test('when it is members-only and has no way to check membership', () {
      refused(
        previewEnvironment(visibility: DVPreviewVisibility.members),
        'membership',
      );
    });

    test('and a refused preview still sends nothing', () async {
      // The refusal is an exception somebody could catch. Capture is on
      // before any check that can refuse, so a caller that carries on anyway
      // still mails nobody.
      expect(
        () => DVPreviewServer.start(
          previewEnvironment(
            overrides: const <String, String>{
              'DARTVEL_QUEUE_NAMESPACE': 'default',
            },
          ),
        ),
        throwsA(isA<DVPreviewStartupException>()),
      );
      await const DVNotificationMail().send(welcome);
      expect(mail.sent, isEmpty);
    });
  });

  group('a process started in a preview', () {
    // Its own process, because the question is what happens before any
    // startup code runs -- which only the environment it was started with can
    // answer.
    Future<Map<String, Object?>> probe(Map<String, String> environment) async {
      final ProcessResult result = await Process.run(
        io.Platform.resolvedExecutable,
        <String>['test/support/preview_process_probe.dart'],
        includeParentEnvironment: false,
        environment: <String, String>{
          for (final String key in <String>[
            'PATH',
            'HOME',
            'PUB_CACHE',
            'TMPDIR',
          ])
            if (io.Platform.environment[key] != null)
              key: io.Platform.environment[key]!,
          ...environment,
        },
      ).timeout(const Duration(minutes: 2));
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final String line = const LineSplitter()
          .convert('${result.stdout}')
          .lastWhere((String l) => l.startsWith('{'));
      return jsonDecode(line) as Map<String, Object?>;
    }

    test(
      'captures mail and namespaces queues before anything starts it',
      () async {
        final Map<String, Object?> seen = await probe(<String, String>{
          'DARTVEL_ENVIRONMENT': 'preview',
          'DARTVEL_PREVIEW': id.name,
          'DARTVEL_QUEUE_NAMESPACE': id.queueNamespace,
        });
        expect(seen['providerSent'], 0);
        expect(seen['captured'], 1);
        expect(seen['queue'], '${id.queueNamespace}.default');
      },
    );

    test('with no queue namespace uses no queue at all', () async {
      final Map<String, Object?> seen = await probe(const <String, String>{
        'DARTVEL_ENVIRONMENT': 'preview',
      });
      expect(
        seen['providerSent'],
        0,
        reason: 'even a preview that cannot say which it is sends nothing',
      );
      expect(seen['queue'], isNull);
      expect(seen['queueError'], contains('DARTVEL_QUEUE_NAMESPACE'));
    });

    test(
      'control: a production process sends and uses plain queue names',
      () async {
        final Map<String, Object?> seen = await probe(const <String, String>{});
        expect(seen['providerSent'], 1);
        expect(seen['captured'], 0);
        expect(seen['queue'], 'default');
      },
    );

    test(
      'control: a production process carrying a preview\'s variables uses '
      'production\'s queues',
      () async {
        // A production deploy whose settings were copied from a preview's.
        // DARTVEL_QUEUE_NAMESPACE is a preview deployment's variable, and
        // outside a preview it must take no effect: honoured here, production
        // would dispatch into the preview's queues and stop consuming its
        // own.
        final Map<String, Object?> seen = await probe(<String, String>{
          'DARTVEL_ENVIRONMENT': 'production',
          'DARTVEL_PREVIEW': id.name,
          'DARTVEL_QUEUE_NAMESPACE': id.queueNamespace,
        });
        expect(seen['providerSent'], 1);
        expect(seen['queue'], 'default');
      },
    );
  },
      // Each probe compiles dartvel_core cold in a child process. Beside another
      // suite that takes longer than the runner's default 30 seconds, which
      // timed the tests out before the child's own two-minute bound could.
      timeout: const Timeout(Duration(minutes: 3)));
}
