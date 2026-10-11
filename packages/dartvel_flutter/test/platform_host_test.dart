import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _RecordingHost extends DVPlatformHost {
  _RecordingHost(
    this.id, {
    this.active = true,
    this.providers = const <String>{},
    this.flags = const <String>{},
    this.storage,
  });

  @override
  final String id;
  bool active;
  final Set<String> providers;
  @override
  final Set<String> flags;
  final DVFileStorageAdapter? storage;
  final List<String> events = <String>[];

  @override
  bool get isActive => active;

  @override
  DVFileStorageAdapter? get fileStorage => storage;

  @override
  Set<String> get signInProviders => providers;

  @override
  Widget frame(BuildContext context, Widget page) =>
      Directionality(textDirection: TextDirection.ltr, child: Column(children: <Widget>[Text('frame:$id'), Expanded(child: page)]));

  @override
  void attachRouter(GoRouter router) => events.add('attach');

  @override
  void detachRouter() => events.add('detach');

  @override
  DVHostCredential? signInCredential(String provider) =>
      DVHostCredential(identifier: '$id:user', secret: 'secret-$provider');
}

void main() {
  tearDown(DVPlatformHosts.reset);

  test('a free install has no hosts and nothing is active', () {
    expect(DV.Platform.hosts, isEmpty);
    expect(DV.Platform.activeHosts, isEmpty);
    expect(DV.Platform.host('telegram'), isNull);
    expect(DV.Platform.isChromiumExtension, isFalse);
    expect(DV.Platform.isFirefoxExtension, isFalse);
  });

  test('registering a host with a known id replaces it', () {
    final _RecordingHost first = _RecordingHost('demo');
    final _RecordingHost second = _RecordingHost('demo');
    DV.Platform.registerHost(first);
    DV.Platform.registerHost(second);
    expect(DV.Platform.hosts, <DVPlatformHost>[second]);
    expect(DV.Platform.host('demo'), same(second));
    DV.Platform.unregisterHost('demo');
    expect(DV.Platform.hosts, isEmpty);
  });

  test('only hosts that detect themselves are active', () {
    final _RecordingHost off = _RecordingHost('off', active: false);
    final _RecordingHost on = _RecordingHost('on');
    DV.Platform
      ..registerHost(off)
      ..registerHost(on);
    expect(DV.Platform.activeHosts, <DVPlatformHost>[on]);
    off.active = true;
    expect(DV.Platform.activeHosts, hasLength(2));
  });

  test('host flags answer the extension getters', () {
    DV.Platform.registerHost(
      _RecordingHost('ext', flags: const <String>{DVPlatformHost.chromiumExtensionFlag}),
    );
    expect(DV.Platform.isChromiumExtension, isTrue);
    expect(DV.Platform.isFirefoxExtension, isFalse);
  });

  test('an inactive host contributes no flags', () {
    DV.Platform.registerHost(
      _RecordingHost('ext', active: false, flags: const <String>{DVPlatformHost.firefoxExtensionFlag}),
    );
    expect(DV.Platform.isFirefoxExtension, isFalse);
  });

  testWidgets('DVHostFrame wraps a page in every active host', (WidgetTester tester) async {
    DV.Platform
      ..registerHost(_RecordingHost('outer'))
      ..registerHost(_RecordingHost('quiet', active: false));
    await tester.pumpWidget(const DVHostFrame(child: Text('page', textDirection: TextDirection.ltr)));
    expect(find.text('frame:outer'), findsOneWidget);
    expect(find.text('frame:quiet'), findsNothing);
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets('DVHostFrame is the page itself with no active host', (WidgetTester tester) async {
    await tester.pumpWidget(const DVHostFrame(child: Text('page', textDirection: TextDirection.ltr)));
    expect(find.text('page'), findsOneWidget);
  });

  test('attaching a router tells active hosts, detaching tells them again', () {
    final _RecordingHost host = _RecordingHost('router');
    final _RecordingHost quiet = _RecordingHost('quiet', active: false);
    DV.Platform
      ..registerHost(host)
      ..registerHost(quiet);
    final GoRouter router = GoRouter(routes: <RouteBase>[GoRoute(path: '/', builder: (_, __) => const SizedBox())]);
    addTearDown(router.dispose);
    DVNavigation.attach(router);
    expect(host.events, <String>['attach']);
    expect(quiet.events, isEmpty);
    DVNavigation.detach();
    expect(host.events, <String>['attach', 'detach']);
  });

  test('a host provides the credential for the sign-in providers it names', () async {
    DV.Platform.registerHost(_RecordingHost('demo', providers: const <String>{'demo'}));
    expect(DV.Platform.hostSignInCredential('demo')?.identifier, 'demo:user');
    expect(DV.Platform.hostSignInCredential('other'), isNull);
  });

  test('a host that is not active provides no sign-in credential', () {
    DV.Platform.registerHost(_RecordingHost('demo', active: false, providers: const <String>{'demo'}));
    expect(DV.Platform.hostSignInCredential('demo'), isNull);
  });

  test('an active host storage replaces the app default for DV.FileStorage', () async {
    final DVMemoryFileStorageAdapter hostDisk = DVMemoryFileStorageAdapter();
    DV.Platform.registerHost(_RecordingHost('disk', storage: hostDisk));
    await DV.FileStorage.put('k', <int>[1, 2, 3]);
    expect(await hostDisk.get('k'), <int>[1, 2, 3]);
    expect(await DV.FileStorage.get('k'), <int>[1, 2, 3]);
    await DV.FileStorage.delete('k');
    expect(await hostDisk.exists('k'), isFalse);
  });
}
