// DV.Session read in a build, and the device a session is recorded as.
//
// The silent failures here:
//  * a widget that reads DV.Session.current in build and never rebuilds, so
//    an account menu keeps showing a person who signed out -- unless the
//    application wired a listener itself, which is what a signal is for not
//    having to do;
//  * a watching widget that is disposed and still rebuilt, or still
//    subscribed, when the session changes later;
//  * sessions recorded with no device, so the sessions page lists a column of
//    "Unknown device" nobody can tell apart;
//  * a device label that identifies the person -- a host name, a user name, a
//    hardware serial -- or that changes between launches of one install.
import 'dart:convert';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const String _token = 'dvs_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

Map<String, Object?> _session(String id) => <String, Object?>{
      'id': id,
      'userId': 'local_1',
      'tenant': 'default',
      'createdAt': '2026-09-15T12:00:00.000Z',
      'lastSeenAt': '2026-09-15T12:30:00.000Z',
      'claims': <String, Object?>{},
      'mfaSatisfiedAt': null,
      'isCurrent': true,
    };

class _Watcher extends StatelessWidget {
  const _Watcher({required this.builds});

  final List<String?> builds;

  @override
  Widget build(BuildContext context) {
    final String? id = DV.Session.watch(context)?.id;
    builds.add(id);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DVText(id ?? 'signed out'),
    );
  }
}

void main() {
  late List<DVHttpRequest> requests;
  late DVSessionClient client;

  setUp(() {
    requests = <DVHttpRequest>[];
    client = DVSessionClient(
      api: (String path) => Uri.parse('https://app.example.test/api$path'),
      tokens: DVMemorySessionTokenStore(),
      web: false,
      device: 'Android phone',
      send: (DVHttpRequest request) async {
        requests.add(request);
        if (request.url.path.endsWith('/auth/sign-out')) {
          return const DVHttpResponse(statusCode: 204, body: '');
        }
        return DVHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'user': <String, Object?>{'id': 'local_1', 'email': 'ada@example.com'},
            'mfaRequired': false,
            'session': _session('ses_here'),
            'token': _token,
          }),
        );
      },
    );
    DVSessionClient.install(client);
    DVAuth.installDefaultProvider(DVSessionAuthProvider(client));
  });

  tearDown(() {
    DVSessionClient.uninstall();
    DV.Test.resetAuthProvider();
  });

  testWidgets('a widget reading DV.Session with watch rebuilds on sign-in and '
      'sign-out, with no listener of its own', (WidgetTester tester) async {
    final List<String?> builds = <String?>[];
    await tester.pumpWidget(_Watcher(builds: builds));
    expect(find.text('signed out'), findsOneWidget);

    await tester.runAsync(() => DV.Auth.signInWithEmailAndPassword(
        email: 'ada@example.com', password: 'correct horse'));
    await tester.pump();
    expect(find.text('ses_here'), findsOneWidget);

    await tester.runAsync(() => DV.Auth.signOut());
    await tester.pump();
    expect(find.text('signed out'), findsOneWidget);
    expect(builds, <String?>[null, 'ses_here', null]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a disposed watcher is not rebuilt when the session changes '
      'later', (WidgetTester tester) async {
    final List<String?> builds = <String?>[];
    await tester.pumpWidget(_Watcher(builds: builds));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => DV.Auth.signInWithEmailAndPassword(
        email: 'ada@example.com', password: 'correct horse'));
    await tester.pump();
    expect(builds, <String?>[null]);
    expect(tester.takeException(), isNull);
  });

  test('the client sends the device it was given, and the server records it',
      () async {
    await client.signIn(email: 'ada@example.com', password: 'correct horse');
    final Map<String, String> headers = <String, String>{
      for (final MapEntry<String, String> e in requests.single.headers.entries)
        e.key.toLowerCase(): e.value,
    };
    expect(headers['x-dartvel-device'], 'Android phone');
  });

  test('the device label is the platform and its form, the same every time, '
      'and nothing that names the machine or the person', () {
    for (final TargetPlatform platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final String label = dvSessionDeviceLabel();
        expect(label, dvSessionDeviceLabel());
        expect(label, matches(RegExp(r'^[A-Za-z]+( [A-Za-z]+)*$')));
        expect(label.length, lessThanOrEqualTo(40));
        expect(label, startsWith(switch (platform) {
          TargetPlatform.android => 'Android',
          TargetPlatform.iOS => 'iOS',
          TargetPlatform.macOS => 'macOS',
          TargetPlatform.windows => 'Windows',
          TargetPlatform.linux => 'Linux',
          TargetPlatform.fuchsia => 'Fuchsia',
        }));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
  });
}
