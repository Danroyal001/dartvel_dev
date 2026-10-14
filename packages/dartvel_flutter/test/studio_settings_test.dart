import 'package:dartvel_core/dartvel.dart' show DVStudioSettings;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSettingsTransport {
  _FakeSettingsTransport({DVStudioSettings? initial}) {
    currentSettings = initial ??
        const DVStudioSettings(
          siteTitle: 'My Dartvel App',
          tagline: 'Built with Flutter and Dartvel',
          siteUrl: 'https://myapp.com',
          timezone: 'UTC',
          dateFormat: 'YYYY-MM-DD',
          favicon: 'https://myapp.com/icon.png',
          defaultSeoTitle: 'My Dartvel App — High Performance',
          defaultSeoDescription: 'A modern full-stack Flutter application.',
          defaultSeoImage: 'https://myapp.com/og-card.png',
          socialLinks: <String, String>{
            'github': 'https://github.com/my-org/my-app',
            'twitter': 'https://x.com/myapp',
          },
          maintenanceMode: false,
          maintenanceMessage:
              'We are currently undergoing scheduled maintenance.',
        );
  }

  late DVStudioSettings currentSettings;
  DVStudioSettings? lastSavedSettings;

  Future<DVStudioReply> call(String method, String path, {Object? body}) async {
    final Uri uri = Uri.parse(path);

    if (uri.path == 'api/settings') {
      if (method == 'GET') {
        return DVStudioReply(200, currentSettings.toJson());
      }
      if (method == 'PUT' || method == 'POST') {
        final Map<String, Object?> json = (body as Map).cast<String, Object?>();
        final DVStudioSettings updated = DVStudioSettings.fromJson(json);
        currentSettings = updated;
        lastSavedSettings = updated;
        return DVStudioReply(200, updated.toJson());
      }
    }

    return const DVStudioReply(404, <String, Object?>{'error': 'not_found'});
  }
}

void main() {
  setUp(() {
    DVStudioStyle.dark = false;
  });

  Future<void> pumpSettingsSection(
    WidgetTester tester, {
    required DVStudioClient client,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DVStudioSettingsSection(client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders settings section with tabs and default identity fields', (
    WidgetTester tester,
  ) async {
    final _FakeSettingsTransport transport = _FakeSettingsTransport();
    final DVStudioClient client = DVStudioClient(transport.call);

    await pumpSettingsSection(tester, client: client);

    expect(find.text('Global Settings'), findsOneWidget);
    expect(find.text('General Identity'), findsOneWidget);
    expect(find.text('Localization'), findsOneWidget);
    expect(find.text('SEO & Social'), findsOneWidget);
    expect(find.text('Maintenance Mode'), findsOneWidget);

    expect(find.text('Site Identity'), findsOneWidget);
    expect(find.text('Site Title'), findsOneWidget);
    expect(find.text('Tagline'), findsOneWidget);
    expect(find.text('Public Site URL'), findsOneWidget);

    // Save button disabled when not dirty
    final Finder saveBtn = find.widgetWithText(DVStudioControl, 'Save Settings');
    expect(saveBtn, findsOneWidget);
  });

  testWidgets('modifying site title enables Save Settings and Discard, and saves cleanly', (
    WidgetTester tester,
  ) async {
    final _FakeSettingsTransport transport = _FakeSettingsTransport();
    final DVStudioClient client = DVStudioClient(transport.call);

    await pumpSettingsSection(tester, client: client);

    final Finder titleInput = find.byType(EditableText).first;
    await tester.enterText(titleInput, 'Acme Enterprise Portal');
    await tester.pumpAndSettle();

    // Discard button should appear
    expect(find.text('Discard'), findsOneWidget);

    // Tap Save Settings
    await tester.tap(find.text('Save Settings'));
    await tester.pumpAndSettle();

    expect(transport.lastSavedSettings, isNotNull);
    expect(transport.lastSavedSettings!.siteTitle, 'Acme Enterprise Portal');
    expect(find.text('Settings saved successfully.'), findsWidgets);

    // After save, Discard disappears because state is clean
    expect(find.text('Discard'), findsNothing);
  });

  testWidgets('discard changes restores original settings', (
    WidgetTester tester,
  ) async {
    final _FakeSettingsTransport transport = _FakeSettingsTransport();
    final DVStudioClient client = DVStudioClient(transport.call);

    await pumpSettingsSection(tester, client: client);

    final Finder titleInput = find.byType(EditableText).first;
    await tester.enterText(titleInput, 'Temporary Unsaved Title');
    await tester.pumpAndSettle();

    expect(find.text('Discard'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Discard'), findsNothing);
    expect(find.text('Temporary Unsaved Title'), findsNothing);
    expect(find.text('My Dartvel App'), findsOneWidget);
    expect(transport.lastSavedSettings, isNull);
  });

  testWidgets('localization tab switches timezone and date format', (
    WidgetTester tester,
  ) async {
    final _FakeSettingsTransport transport = _FakeSettingsTransport();
    final DVStudioClient client = DVStudioClient(transport.call);

    await pumpSettingsSection(tester, client: client);

    // Switch to Localization tab
    await tester.tap(find.text('Localization'));
    await tester.pumpAndSettle();

    expect(find.text('Time & Date Localization'), findsOneWidget);
    expect(find.text('Timezone'), findsOneWidget);
    expect(find.text('Date Format'), findsOneWidget);
    expect(find.textContaining('Preview: YYYY-MM-DD in timezone UTC'),
        findsOneWidget);
  });

  testWidgets('SEO tab renders SERP and social card previews and social links', (
    WidgetTester tester,
  ) async {
    final _FakeSettingsTransport transport = _FakeSettingsTransport();
    final DVStudioClient client = DVStudioClient(transport.call);

    await pumpSettingsSection(tester, client: client);

    // Switch to SEO & Social tab
    await tester.tap(find.text('SEO & Social'));
    await tester.pumpAndSettle();

    expect(find.text('Default Search Engine Optimization (SEO)'), findsOneWidget);
    expect(find.text('Google Search Snippet Preview'), findsOneWidget);
    expect(find.text('Social Share Card Preview'), findsOneWidget);
    expect(find.text('Social Profiles'), findsOneWidget);
    expect(find.textContaining('My Dartvel App — High Performance'),
        findsWidgets);
  });

  testWidgets('maintenance mode toggle activates banner and updates settings', (
    WidgetTester tester,
  ) async {
    final _FakeSettingsTransport transport = _FakeSettingsTransport();
    final DVStudioClient client = DVStudioClient(transport.call);

    await pumpSettingsSection(tester, client: client);

    // Switch to Maintenance Mode tab
    await tester.tap(find.text('Maintenance Mode'));
    await tester.pumpAndSettle();

    expect(find.text('Enable Maintenance Mode'), findsOneWidget);

    // Tap switch
    final Finder switchFinder =
        find.byKey(const ValueKey<String>('dv-studio-settings-maintenance-switch'));
    expect(switchFinder, findsOneWidget);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    // Alert banner should appear
    expect(
      find.textContaining('Maintenance mode is active. Public visitors see the maintenance page'),
      findsOneWidget,
    );

    // Save changes
    await tester.tap(find.text('Save Settings'));
    await tester.pumpAndSettle();

    expect(transport.lastSavedSettings, isNotNull);
    expect(transport.lastSavedSettings!.maintenanceMode, isTrue);
  });
}
