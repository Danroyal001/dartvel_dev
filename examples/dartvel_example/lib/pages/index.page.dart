import 'dart:async';

import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

StreamSubscription<String>? _subscription;

@DVPage()
@DVFunctionalWidget()
Widget indexPage(BuildContext context) {
  final counter = context.signal(0);
  final isStreaming = context.signal(false);
  final ticks = context.signal(<String>[]);

  final currentLangScope = DvI18nScope.of(context).localeTag;
  final currentLang = currentLangScope.isEmpty ? 'system' : currentLangScope;

  return DVBox.list([
    const DVText('Dartvel Platform Showcase'),
    ShowcaseButton('Toggle Theme', () {
      final next =
          DV.Theme.mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
      DV.Theme.setMode(next);
      _showMessage(context, 'Theme mode set to ${DV.Theme.mode}');
    }),
    const DVText('Welcome to Dartvel full-stack app platform!')
        .modifier(_titleStyle),
    ShowcaseSection('1. Signals State Management', [
      DVText('Local counter signal value: ${counter.value}'),
      ShowcaseButton('Increment Counter Signal', () {
        counter.value = counter.value + 1;
      }),
    ]),
    ShowcaseSection('2. Platform Info', [
      DVBox.grid([
        ShowcaseMetric('Platform', DV.Platform.currentPlatform),
        ShowcaseMetric('Device type', DV.Platform.deviceType),
        ShowcaseMetric('Breakpoint', DV.Platform.breakpoint),
        ShowcaseMetric('Orientation', DV.Platform.orientation.name),
      ], columns: 2),
    ]),
    ShowcaseSection('3. Authentication & Multi-Tenancy', [
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
    ShowcaseSection('4. Model Form', [
      const DVForm<User>(User(name: 'John Doe', email: 'john@example.com')),
    ]),
    ShowcaseSection('5. Streaming Functions', [
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
    ShowcaseSection('6. i18n & Typed Router Actions', [
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
    ShowcaseSection('7. Direct Typed API Calls', [
      DVBox.row([
        ShowcaseButton('GET /hello', () async {
          final data = await getHelloApi(name: 'Tester');
          if (context.mounted) _showMessage(context, 'API: $data');
        }),
        ShowcaseButton('POST /echo', () async {
          final data = await postEchoApi(msg: 'System OK');
          if (context.mounted) _showMessage(context, 'Echo: $data');
        }),
      ]),
    ]),
    ShowcaseSection('8. Unified Services', [
      DVBox.wrap([
        ShowcaseButton('Cache', () async {
          await DV.Cache.set('last_run', DateTime.now().toIso8601String());
          final value = await DV.Cache.get<String>('last_run');
          if (context.mounted) _showMessage(context, 'Cache value: $value');
        }),
        ShowcaseButton('Storage', () async {
          await DV.Storage.upload('doc.txt', [104, 101, 108, 108, 111]);
          final bytes = await DV.Storage.download('doc.txt');
          if (context.mounted) {
            _showMessage(context, 'Storage bytes: ${bytes.length}');
          }
        }),
        ShowcaseButton('Database', () async {
          final result = await DV.Database.query('select 1');
          if (context.mounted) _showMessage(context, 'DB Query: $result');
        }),
      ]),
    ]),
    ShowcaseSection('9. Collection Layouts', [
      DVBox.grid([
        FeatureCard('Vertical', 'Default list layout'),
        FeatureCard('Row', 'Inline collection mode'),
        FeatureCard('Wrap', 'Chip and tag layouts'),
        FeatureCard('Grid', 'Responsive cards'),
      ], columns: 2),
      DVBox.builder<String>(
        ['Flutter', 'Dart', 'Rust', 'FFI', 'JNI', 'Shorebird'],
        (tag) => DVText(tag).modifier(_pillStyle),
      ).wrap(),
      DVBox.horizontalScrollable([
        FeatureCard('Story 1', 'Static horizontal item'),
        FeatureCard('Story 2', 'Static horizontal item'),
        FeatureCard('Story 3', 'Static horizontal item'),
      ]).modifier(const DVModifier().height(120)),
      DVBox.masonry([
        FeatureCard('Masonry A', 'Short'),
        FeatureCard('Masonry B', 'Taller generated-card style content'),
        FeatureCard('Masonry C', 'Medium content'),
      ], columns: 2),
    ]),
    ShowcaseSection('10. AI & Observability', [
      DVBox.wrap([
        ShowcaseButton('Query AI', () async {
          final answer = await DV.AI.chat('What is Dartvel?');
          if (context.mounted) _showMessage(context, 'AI: $answer');
        }),
        ShowcaseButton('Log Event', () {
          unawaited(DV.log('Showcase event logged'));
          _showMessage(context, 'Event logged successfully');
        }),
      ]),
    ]),
  ]).scrollable().modifier(const DVModifier().padding(16));
}

final _titleStyle = const DVModifier()
    .color(const Color(0xFF6200EE))
    .padding(8)
    .backgroundColor(const Color(0xFFEDE7F6))
    .rounded(8);

final _pillStyle = const DVModifier()
    .padding(8)
    .rounded(999)
    .backgroundColor(const Color(0xFFE0F2FE))
    .color(const Color(0xFF075985));

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: DVText(message)),
  );
}
