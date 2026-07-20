import 'dart:async';

import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

StreamSubscription<String>? _subscription;
bool _demoNativeBindingsRegistered = false;

@DVPage()
@DVFunctionalWidget()
Widget indexPage(BuildContext context) {
  _registerDemoNativeBindings();

  final counter = context.signal(0);
  final isStreaming = context.signal(false);
  final ticks = context.signal(<String>[]);

  final currentLangScope = DvI18nScope.of(context).localeTag;
  final currentLang = currentLangScope.isEmpty ? 'system' : currentLangScope;

  return DVBox.list([
    ShowcaseHero(
      DV.Platform.currentPlatform,
      DV.Platform.deviceType,
      DartvelRuntime.baseUrl,
    ),
    DVBox.wrap([
      ShowcaseButton('Toggle Theme', () {
        final next =
            DV.Theme.mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
        DV.Theme.setMode(next);
        _showMessage(context, 'Theme mode set to ${DV.Theme.mode}');
      }),
      ShowcaseButton('Typed Blog Route', () {
        context.navigateToPage(DVRoutes.blog(id: '777'));
      }),
      ShowcaseButton('Start SSE Stream', () {
        ticks.value = [];
        isStreaming.value = true;
        _subscription = getTicks().listen(
          (tick) => ticks.value = [...ticks.value, tick],
          onDone: () => isStreaming.value = false,
        );
      }),
    ]).modifier(_quickActionsStyle),
    ShowcaseSection('State & Signals', [
      DVText('Local counter signal value: ${counter.value}'),
      ShowcaseButton('Increment Counter Signal', () {
        counter.value = counter.value + 1;
      }),
    ]),
    ShowcaseSection('Runtime Platform', [
      DVBox.grid([
        ShowcaseMetric('Platform', DV.Platform.currentPlatform),
        ShowcaseMetric('Device type', DV.Platform.deviceType),
        ShowcaseMetric('Breakpoint', DV.Platform.breakpoint),
        ShowcaseMetric('Orientation', DV.Platform.orientation.name),
        ShowcaseMetric('Chromium extension',
            DV.Platform.isChromiumExtension ? 'yes' : 'no'),
        ShowcaseMetric(
            'Firefox extension', DV.Platform.isFirefoxExtension ? 'yes' : 'no'),
      ], columns: 2),
      DVBox.wrap([
        ShowcaseButton('Window Title', () async {
          await DV.Platform.Window.setTitle('Dartvel Showcase');
          if (context.mounted) _showMessage(context, 'Window title requested');
        }),
        ShowcaseButton('Fullscreen', () async {
          await DV.Platform.display.enterFullscreen(
            const DVFullscreenOptions(lockOrientation: true),
          );
          if (context.mounted) _showMessage(context, 'Fullscreen requested');
        }),
        ShowcaseButton('Exit Fullscreen', () async {
          await DV.Platform.display.exitFullscreen();
          if (context.mounted) _showMessage(context, 'Fullscreen exited');
        }),
        ShowcaseButton('Kiosk Mode', () async {
          await DV.Platform.display.enableKiosk(
            const DVKioskOptions(allowedExitKeys: <String>['Escape']),
          );
          if (context.mounted) _showMessage(context, 'Kiosk mode requested');
        }),
        ShowcaseButton('Exit Kiosk', () async {
          await DV.Platform.display.disableKiosk();
          if (context.mounted) _showMessage(context, 'Kiosk mode exited');
        }),
      ]),
    ]),
    ShowcaseSection('Generated Config, Env, PWA & SEO', [
      DVBox.grid([
        ShowcaseMetric('Database', DartvelConfig.databaseProvider),
        ShowcaseMetric('Storage', DartvelConfig.storageProvider),
        ShowcaseMetric('Auth providers', DartvelConfig.authProviders.join(',')),
        ShowcaseMetric('AI provider', DartvelConfig.aiProvider),
        ShowcaseMetric('PWA', DartvelConfig.pwaEnabled ? 'enabled' : 'off'),
        ShowcaseMetric('Public env', Env.PUBLIC_GREETING),
      ], columns: 2),
      DVText('Runtime backend: ${DartvelRuntime.baseUrl}'),
      const DVText(
          'SEO defaults are generated into the deferred router wrapper.'),
    ]),
    ShowcaseSection('Authentication & Tenancy', [
      DVText('Current Tenant: ${DV.currentTenant}'),
      DVText('User status: ${DV.Auth.currentUser ?? "Not signed in"}'),
      DVBox.wrap([
        ShowcaseButton('Sign In', () async {
          await DV.Auth.signIn();
          if (context.mounted) _showMessage(context, 'Signed in successfully');
        }),
        ShowcaseButton('Sign Out', () async {
          await DV.Auth.signOut();
          if (context.mounted) _showMessage(context, 'Signed out successfully');
        }),
      ]),
    ]),
    ShowcaseSection('Models, Forms & Generated Model Helpers', [
      const DVForm<User>(User(name: 'John Doe', email: 'john@example.com')),
      DVText(
        'Generated model SQL: ${const User(name: 'Ada', email: 'ada@example.com').createTableSql}',
      ),
      DVBox.wrap([
        ShowcaseButton('Monthly Report', () {
          final report = UserReport.monthly(const <User>[
            User(name: 'Ada Lovelace', email: 'ada@example.com'),
            User(name: 'Grace Hopper', email: 'grace@example.com'),
          ]);
          _showMessage(context, 'Report count: ${report.metrics['count']}');
        }),
        ShowcaseButton('Schedule Report', () {
          final scheduled = UserReport.scheduleMonthly(
            cron: '0 8 1 * *',
            metadata: const <String, String>{'tenant': 'demo'},
          );
          _showMessage(
              context, 'Scheduled ${scheduled.name}: ${scheduled.cron}');
        }),
        ShowcaseButton('Dispatch Report Job', () async {
          final job = await UserReport.dispatchMonthly(
            queue: 'reports',
            metadata: const <String, String>{'source': 'showcase'},
          );
          if (context.mounted) {
            _showMessage(context, 'Report job queued: ${job.queue}');
          }
        }),
      ]),
    ]),
    ShowcaseSection('Streaming Functions', [
      ShowcaseButton(isStreaming.value ? 'Stop SSE Stream' : 'Start SSE Stream',
          () {
        if (isStreaming.value) {
          _subscription?.cancel();
          isStreaming.value = false;
        } else {
          ticks.value = [];
          isStreaming.value = true;
          _subscription = getTicks().listen(
            (tick) => ticks.value = [...ticks.value, tick],
            onDone: () => isStreaming.value = false,
          );
        }
      }),
      if (ticks.value.isNotEmpty)
        DVBox.builder<String>(
          ticks.value,
          (tick) => DVText(tick).modifier(_pillStyle),
        ).scrollable().modifier(const DVModifier().height(120)),
    ]),
    ShowcaseSection('i18n, Deferred Pages & Typed Router Actions', [
      DVText('Current Language Locale: $currentLang'),
      DVBox.wrap([
        ShowcaseButton('Set Locale: EN-US', () {
          DvI18n.updateLang(context, 'lang', 'en-US');
        }),
        ShowcaseButton('Set Locale: FR-FR', () {
          DvI18n.updateLang(context, 'lang', 'fr-FR');
        }),
        ShowcaseButton('Dynamic Route', () {
          context.push('/blog/101');
        }),
        ShowcaseButton('Typed Blog Route', () {
          context.navigateToPage(DVRoutes.blog(id: '777'));
        }),
      ]),
    ]),
    ShowcaseSection('Typed API Client', [
      DVBox.wrap([
        ShowcaseButton('GET /hello', () async {
          final data = await getHelloApi(name: 'Tester');
          if (context.mounted) _showMessage(context, 'API: $data');
        }),
        ShowcaseButton('POST /echo', () async {
          final data = await postEchoApi(msg: 'System OK');
          if (context.mounted) _showMessage(context, 'Echo: $data');
        }),
        ShowcaseButton('POST /sum', () async {
          final total = await postSumApi(a: 20, b: 22);
          if (context.mounted) _showMessage(context, 'Sum: $total');
        }),
        ShowcaseButton('GET /search', () async {
          final data = await getSearchApi(q: 'dartvel', tags: ['ui', 'api']);
          if (context.mounted) _showMessage(context, 'Search: $data');
        }),
        ShowcaseButton('HEAD /ping', () async {
          final data = await headPingApi();
          if (context.mounted) _showMessage(context, 'Ping: $data');
        }),
      ]),
    ]),
    ShowcaseSection('CRUD, Files & CSRF', [
      DVBox.wrap([
        ShowcaseButton('Create Todo', () async {
          final data = await postDbTodosApi(title: 'Ship Dartvel demo');
          if (context.mounted) _showMessage(context, 'Created: $data');
        }),
        ShowcaseButton('List Todos', () async {
          final data = await getDbTodosData();
          if (context.mounted) _showMessage(context, 'Todos: $data');
        }),
        ShowcaseButton('Update Todo', () async {
          final data = await putDbTodosByIdApi(id: '1', title: 'Updated todo');
          if (context.mounted) _showMessage(context, 'Updated: $data');
        }),
        ShowcaseButton('Delete Todo', () async {
          final data = await deleteDbTodosByIdApi(id: '1');
          if (context.mounted) _showMessage(context, 'Deleted: $data');
        }),
        ShowcaseButton('Catch-all File Route', () async {
          final data = await getFilesByPathApi(path: ['docs', 'readme.md']);
          if (context.mounted) _showMessage(context, 'File route: $data');
        }),
        ShowcaseButton('CSRF Token', () {
          final token = const DVCSRF().token();
          _showMessage(context, 'CSRF token length: ${token.length}');
        }),
      ]),
    ]),
    ShowcaseSection('Unified Local Services', [
      DVBox.wrap([
        ShowcaseButton('Cache', () async {
          await DV.Cache.set('last_run', DateTime.now().toIso8601String());
          final value = await DV.Cache.get<String>('last_run');
          if (context.mounted) _showMessage(context, 'Cache value: $value');
        }),
        ShowcaseButton('Storage', () async {
          await DV.FileStorage.put('doc.txt', [104, 101, 108, 108, 111]);
          final bytes = await DV.FileStorage.get('doc.txt');
          if (context.mounted) {
            _showMessage(context, 'Storage bytes: ${bytes.length}');
          }
        }),
        ShowcaseButton('Database', () async {
          final result = await DV.Database.query('select 1');
          if (context.mounted) _showMessage(context, 'DB Query: $result');
        }),
        ShowcaseButton('Queue Signal', () async {
          final events = <String>[];
          DV.Queues.register<String>(events.add);
          await DV.Jobs.dispatch<String>('hello signal', queue: 'signals');
          await DV.Queues.work(queue: 'signals');
          if (context.mounted) _showMessage(context, 'Queue signal: $events');
        }),
        ShowcaseButton('Theme Dark/Light', () {
          final next = DV.Theme.mode == ThemeMode.dark
              ? ThemeMode.light
              : ThemeMode.dark;
          DV.Theme.setMode(next);
          _showMessage(context, 'Theme: ${DV.Theme.mode.name}');
        }),
        ShowcaseButton('Typed Shell', () async {
          final result = await const DVShell().runCommand(
            const DVShellCommand('dart').arg('--version').env('CI', 'true'),
          );
          if (context.mounted) {
            _showMessage(context, 'Shell exit code: ${result.exitCode}');
          }
        }),
      ]),
    ]),
    ShowcaseSection('Native APIs via Generated Bindings', [
      const DVText(
        'Browser demo bindings below are generated native-style handlers for exercising the Dartvel API surface in web preview.',
      ).modifier(_supportingTextStyle),
      DVBox.wrap([
        ShowcaseButton('Camera', () async {
          final bytes = await DV.Platform.camera.takePhoto();
          if (context.mounted) _showMessage(context, 'Photo bytes: $bytes');
        }),
        ShowcaseButton('Location', () async {
          final data = await DV.Platform.location.getCoordinates();
          if (context.mounted) _showMessage(context, 'Location: $data');
        }),
        ShowcaseButton('Media Picker', () async {
          final data = await DV.Platform.media.pick(multiple: true);
          if (context.mounted) _showMessage(context, 'Media: $data');
        }),
        ShowcaseButton('Permissions', () async {
          final granted = await DV.Platform.permissions.request('camera');
          if (context.mounted) {
            _showMessage(context, 'Camera permission: $granted');
          }
        }),
        ShowcaseButton('Clipboard', () async {
          await DV.Platform.clipboard.copy('Copied from Dartvel');
          final text = await DV.Platform.clipboard.paste();
          if (context.mounted) _showMessage(context, 'Clipboard: $text');
        }),
        ShowcaseButton('Share', () async {
          await DV.Platform.share.shareText('Dartvel showcase');
          if (context.mounted) _showMessage(context, 'Share requested');
        }),
        ShowcaseButton('Notify', () async {
          await DV.Platform.notifications
              .sendLocalNotification('Dartvel', 'Local notification');
          if (context.mounted) _showMessage(context, 'Notification sent');
        }),
        ShowcaseButton('Bluetooth', () async {
          final enabled = await DV.Platform.bluetooth.isEnabled();
          if (context.mounted) _showMessage(context, 'Bluetooth: $enabled');
        }),
        ShowcaseButton('NFC', () async {
          final tag = await DV.Platform.nfc.readTag();
          if (context.mounted) _showMessage(context, 'NFC: $tag');
        }),
        ShowcaseButton('Sensors', () async {
          final value = await DV.Platform.sensors.accelerometer.first;
          if (context.mounted) _showMessage(context, 'Accelerometer: $value');
        }),
        ShowcaseButton('Biometrics', () async {
          final ok = await DV.Platform.biometrics.authenticate();
          if (context.mounted) _showMessage(context, 'Biometrics: $ok');
        }),
        ShowcaseButton('Haptics', () async {
          await DV.Platform.haptics.impact();
          if (context.mounted) _showMessage(context, 'Haptic impact requested');
        }),
        ShowcaseButton('Contacts', () async {
          final contacts = await DV.Platform.contacts.getContacts();
          if (context.mounted) _showMessage(context, 'Contacts: $contacts');
        }),
        ShowcaseButton('Deep Link', () async {
          final link = await DV.Platform.deepLinks.getInitialLink();
          if (context.mounted) _showMessage(context, 'Initial link: $link');
        }),
      ]),
    ]),
    ShowcaseSection('Collection Layouts', [
      DVBox.grid([
        FeatureCard('Vertical', 'Default list layout'),
        FeatureCard('Row', 'Inline collection mode'),
        FeatureCard('Wrap', 'Chip and tag layouts'),
        FeatureCard('Grid', 'Responsive cards'),
      ], columns: 2),
      DVBox.row([
        const DVBox(DVText('Row A')).modifier(_rowDemoStyle),
        const DVBox(DVText('Row B')).modifier(_rowDemoStyle),
      ]),
      DVBox.stack([
        const DVBox(DVText('Stack background')).modifier(
          const DVModifier()
              .height(80)
              .backgroundColor(const Color(0xFFEDE7F6))
              .rounded(8),
        ),
        const DVBox(DVText('Stack foreground')).modifier(
          const DVModifier().padding(12).backgroundColor(Colors.white),
        ),
      ]),
      DVBox.builder<String>(
        ['Flutter', 'Dart', 'Rust', 'FFI', 'JNI', 'Shorebird'],
        (tag) => DVText(tag).modifier(_pillStyle),
      ).wrap(),
      DVBox.builder<String>(
        ['Story 1', 'Story 2', 'Story 3'],
        (story) => DVBox(DVText(story)).modifier(_storyStyle),
      ).horizontalScrollable().modifier(const DVModifier().height(120)),
      DVBox.masonry([
        FeatureCard('Masonry A', 'Short'),
        FeatureCard('Masonry B', 'Taller generated-card style content'),
        FeatureCard('Masonry C', 'Medium content'),
      ], columns: 2),
    ]),
    ShowcaseSection('AI, Observability & Logging', [
      DVBox.wrap([
        ShowcaseButton('Query AI', () async {
          final answer = await DV.AI.chat('What is Dartvel?');
          if (context.mounted) _showMessage(context, 'AI: $answer');
        }),
        ShowcaseButton('Embedding', () async {
          final vector = await DV.AI.embed('dartvel');
          if (context.mounted) {
            _showMessage(context, 'Embedding dims: ${vector.length}');
          }
        }),
        ShowcaseButton('Log Event', () {
          unawaited(DV.log('Showcase event logged'));
          _showMessage(context, 'Event logged successfully');
        }),
        ShowcaseButton('Metric', () async {
          await DV.ObservabilityAndLogging.metric('showcase_metric', 1);
          if (context.mounted) _showMessage(context, 'Metric emitted');
        }),
        ShowcaseButton('Trace', () async {
          final value = await DV.ObservabilityAndLogging.trace<int>(
            'showcase_trace',
            () => 42,
          );
          if (context.mounted) _showMessage(context, 'Trace result: $value');
        }),
        ShowcaseButton('Diagnostic', () async {
          await DV.ObservabilityAndLogging.diagnostic(
            'showcase',
            <String, Object>{'healthy': true},
          );
          if (context.mounted) _showMessage(context, 'Diagnostic emitted');
        }),
      ]),
    ]),
  ]).scrollable().modifier(_pageStyle);
}

void _registerDemoNativeBindings() {
  if (_demoNativeBindingsRegistered) return;
  _demoNativeBindingsRegistered = true;

  DVNativeBridge.register('window.setTitle', (_) => true);
  DVNativeBridge.register('window.maximize', (_) => true);
  DVNativeBridge.register('window.minimize', (_) => true);
  DVNativeBridge.register('display.enterFullscreen', (_) => true);
  DVNativeBridge.register('display.exitFullscreen', (_) => true);
  DVNativeBridge.register('display.enableKiosk', (_) => true);
  DVNativeBridge.register('display.disableKiosk', (_) => true);
  DVNativeBridge.register('camera.takePhoto', (_) => <int>[1, 2, 3, 4]);
  DVNativeBridge.register(
    'location.current',
    (_) => <String, double>{'latitude': 6.5244, 'longitude': 3.3792},
  );
  DVNativeBridge.register(
    'media.pick',
    (_) => <Map<String, Object?>>[
      <String, Object?>{'path': 'showcase.png', 'type': 'image'},
    ],
  );
  DVNativeBridge.register('permissions.request', (_) => true);
  DVNativeBridge.register('permissions.isGranted', (_) => true);
  DVNativeBridge.register('share.text', (_) => true);
  DVNativeBridge.register('notifications.sendLocal', (_) => true);
  DVNativeBridge.register('bluetooth.isEnabled', (_) => true);
  DVNativeBridge.register('bluetooth.scanDevices', (_) => <String>['Beacon A']);
  DVNativeBridge.register('nfc.isAvailable', (_) => true);
  DVNativeBridge.register('nfc.readTag', (_) => 'tag-123');
  DVNativeBridge.register(
    'sensors.accelerometer',
    (_) => <String, double>{'x': 0.1, 'y': 0.0, 'z': 9.8},
  );
  DVNativeBridge.register(
    'sensors.gyroscope',
    (_) => <String, double>{'x': 0.0, 'y': 0.2, 'z': 0.0},
  );
  DVNativeBridge.register('biometrics.canAuthenticate', (_) => true);
  DVNativeBridge.register('biometrics.authenticate', (_) => true);
  DVNativeBridge.register('deepLinks.initial', (_) => 'dartvel://showcase');
  DVNativeBridge.register('haptics.vibrate', (_) => true);
  DVNativeBridge.register('haptics.lightVibrate', (_) => true);
  DVNativeBridge.register('haptics.impact', (_) => true);
  DVNativeBridge.register(
    'contacts.getContacts',
    (_) => <Map<String, String>>[
      <String, String>{'name': 'Ada Lovelace', 'email': 'ada@example.com'},
    ],
  );
}

final _pageStyle =
    const DVModifier().padding(18).backgroundColor(const Color(0xFFFFFBFE));

final _quickActionsStyle = const DVModifier()
    .padding(16)
    .rounded(24)
    .backgroundColor(const Color(0xFFFFD8E4));

final _supportingTextStyle = const DVModifier()
    .color(const Color(0xFF49454F))
    .fontSize(14)
    .fontWeight(FontWeight.w600)
    .padding(8);

final _pillStyle = const DVModifier()
    .padding(8)
    .rounded(999)
    .backgroundColor(const Color(0xFFCCE5FF))
    .color(const Color(0xFF001D36))
    .fontWeight(FontWeight.w700);

final _rowDemoStyle = const DVModifier()
    .width(140)
    .padding(12)
    .rounded(8)
    .backgroundColor(const Color(0xFFFFD8E4))
    .color(const Color(0xFF31111D))
    .fontWeight(FontWeight.w700);

final _storyStyle = const DVModifier()
    .width(160)
    .height(88)
    .padding(12)
    .rounded(8)
    .backgroundColor(const Color(0xFFD0BCFF))
    .color(const Color(0xFF21005D))
    .fontWeight(FontWeight.w800);

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: DVText(message)),
  );
}
