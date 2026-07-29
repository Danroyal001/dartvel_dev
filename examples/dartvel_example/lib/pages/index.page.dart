import 'dart:async';

import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

StreamSubscription<String>? showcaseSubscription;

@DVPage()
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => (() {
      final counter = context.signal(0);
      final isStreaming = context.signal(false);
      final ticks = context.signal(<String>[]);

      final currentLangScope = DvI18nScope.of(context).localeTag;
      final currentLang =
          currentLangScope.isEmpty ? 'system' : currentLangScope;

      return DVBox.list([
        ShowcaseHero(
          DV.Platform.currentPlatform,
          DV.Platform.deviceType,
          DV.baseUrl,
        ),
        DVBox.wrapLine([
          ShowcaseButton('Toggle Theme', () {
            final next = DV.Theme.mode == ThemeMode.dark
                ? ThemeMode.light
                : ThemeMode.dark;
            DV.Theme.setMode(next);
            showShowcaseMessage(context, 'Theme mode set to ${DV.Theme.mode}');
          }),
          ShowcaseButton('Typed Blog Route', () {
            context.navigateToPage(DVRoutes.blog(id: '777'));
          }),
          ShowcaseButton('Start SSE Stream', () {
            ticks.value = [];
            isStreaming.value = true;
            showcaseSubscription = getTicks().listen(
              (tick) => ticks.value = [...ticks.value, tick],
              onDone: () => isStreaming.value = false,
            );
          }),
        ]).modifier(quickActionsStyle),
        ShowcaseSection('State & Signals', [
          DVText('Local counter signal value: ${counter.value}'),
          DVText('Global app signal value: ${DV.global<String>()}'),
          DVBox.wrapLine([
            ShowcaseButton('Increment Counter Signal', () {
              counter.value = counter.value + 1;
            }),
            ShowcaseButton('Update Global Signal', () {
              DV.global<String>('showcase-updated-${counter.value}');
              showShowcaseMessage(context, 'Global signal updated');
            }),
          ]),
        ]),
        ShowcaseSection('Runtime Platform', [
          DVBox.grid([
            ShowcaseMetric('Platform', DV.Platform.currentPlatform),
            ShowcaseMetric('Device type', DV.Platform.deviceType),
            ShowcaseMetric('Breakpoint', DV.Platform.breakpoint),
            ShowcaseMetric('Orientation', DV.Platform.orientation.name),
            ShowcaseMetric(
              'Chromium extension',
              DV.Platform.isChromiumExtension ? 'yes' : 'no',
            ),
            ShowcaseMetric(
              'Firefox extension',
              DV.Platform.isFirefoxExtension ? 'yes' : 'no',
            ),
          ], columns: 2),
          DVBox.wrapLine([
            ShowcaseButton(
              'Window Title',
              () => runShowcaseNativeAction(context, () async {
                await DV.Platform.Window.setTitle('Dartvel Showcase');
                if (context.mounted) {
                  showShowcaseMessage(context, 'Window title requested');
                }
              }),
            ),
            ShowcaseButton(
              'Fullscreen',
              () => runShowcaseNativeAction(context, () async {
                await DV.Platform.display.enterFullscreen(
                  const DVFullscreenOptions(lockOrientation: true),
                );
                if (context.mounted) {
                  showShowcaseMessage(context, 'Fullscreen requested');
                }
              }),
            ),
            ShowcaseButton(
              'Exit Fullscreen',
              () => runShowcaseNativeAction(context, () async {
                await DV.Platform.display.exitFullscreen();
                if (context.mounted) {
                  showShowcaseMessage(context, 'Fullscreen exited');
                }
              }),
            ),
            ShowcaseButton(
              'Kiosk Mode',
              () => runShowcaseNativeAction(context, () async {
                await DV.Platform.display.enableKiosk(
                  const DVKioskOptions(allowedExitKeys: <String>['Escape']),
                );
                if (context.mounted) {
                  showShowcaseMessage(context, 'Kiosk mode requested');
                }
              }),
            ),
            ShowcaseButton(
              'Exit Kiosk',
              () => runShowcaseNativeAction(context, () async {
                await DV.Platform.display.disableKiosk();
                if (context.mounted) {
                  showShowcaseMessage(context, 'Kiosk mode exited');
                }
              }),
            ),
          ]),
        ]),
        ShowcaseSection('Generated Config, Env, PWA & SEO', [
          DVBox.grid([
            ShowcaseMetric('Database', DartvelConfig.databaseProvider),
            ShowcaseMetric('Storage', DartvelConfig.storageProvider),
            ShowcaseMetric(
                'Auth providers', DartvelConfig.authProviders.join(',')),
            ShowcaseMetric('AI provider', DartvelConfig.aiProvider),
            ShowcaseMetric('PWA', DartvelConfig.pwaEnabled ? 'enabled' : 'off'),
            ShowcaseMetric('Public env', Env.PUBLIC_GREETING),
          ], columns: 2),
          DVText('Runtime backend: ${DV.baseUrl}'),
          const DVText(
            'SEO defaults are generated into the deferred router wrapper.',
          ),
        ]),
        ShowcaseSection('Authentication & Tenancy', [
          DVText('Current Tenant: ${DV.currentTenant}'),
          DVText('User status: ${DV.Auth.currentUser ?? "Not signed in"}'),
          DVBox.wrapLine([
            ShowcaseButton('Sign In', () async {
              await DV.Auth.signIn();
              if (context.mounted) {
                showShowcaseMessage(context, 'Signed in successfully');
              }
            }),
            ShowcaseButton('Sign Out', () async {
              await DV.Auth.signOut();
              if (context.mounted) {
                showShowcaseMessage(context, 'Signed out successfully');
              }
            }),
          ]),
        ]),
        ShowcaseSection('Models, Forms & Generated Model Helpers', [
          User.Form(
            const User(
              slug: 'john-doe',
              name: 'John Doe',
              email: 'john@example.com',
              published: true,
              recoveryToken: 'tok',
            ),
          ),
          User.List(const <User>[
            User(
              slug: 'ada-lovelace',
              name: 'Ada Lovelace',
              email: 'ada@example.com',
              published: true,
              recoveryToken: 't1',
            ),
            User(
              slug: 'grace-hopper',
              name: 'Grace Hopper',
              email: 'grace@example.com',
              published: true,
              recoveryToken: 't2',
            ),
          ]),
          User.Table(const <User>[
            User(
              slug: 'linus-torvalds',
              name: 'Linus Torvalds',
              email: 'linus@example.com',
              published: true,
              recoveryToken: 't3',
            ),
            User(
              slug: 'margaret-hamilton',
              name: 'Margaret Hamilton',
              email: 'margaret@example.com',
              published: false,
              recoveryToken: 't4',
            ),
          ], columns: 2),
          DVText(
            'Generated model SQL: ${const User(slug: 'ada', name: 'Ada', email: 'ada@example.com', published: true, recoveryToken: 'secret').createTableSql}',
          ),
          const DVText('Generated public page route: ${User.publicPageRoute}'),
          DVBox.wrapLine([
            ShowcaseButton('Public User Paths', () async {
              final paths = await seedAndResolveUserPublicPaths();
              if (context.mounted) {
                showShowcaseMessage(
                    context, 'Public paths: ${paths.join(', ')}');
              }
            }),
            ShowcaseButton('Monthly Report', () {
              final report = UserReport.monthly(const <User>[
                User(
                  slug: 'ada-lovelace',
                  name: 'Ada Lovelace',
                  email: 'ada@example.com',
                  published: true,
                  recoveryToken: 'tok-ada',
                ),
                User(
                  slug: 'grace-hopper',
                  name: 'Grace Hopper',
                  email: 'grace@example.com',
                  published: true,
                  recoveryToken: 'tok-grace',
                ),
              ]);
              showShowcaseMessage(
                context,
                'Report count: ${report.metrics['count']}',
              );
            }),
            ShowcaseButton('Schedule Report', () {
              final scheduled = UserReport.scheduleMonthly(
                cron: '0 8 1 * *',
                metadata: const <String, String>{'tenant': 'demo'},
              );
              showShowcaseMessage(
                context,
                'Scheduled ${scheduled.name}: ${scheduled.cron}',
              );
            }),
            ShowcaseButton('Dispatch Report Job', () async {
              final job = await UserReport.dispatchMonthly(
                queue: 'reports',
                metadata: const <String, String>{'source': 'showcase'},
              );
              if (context.mounted) {
                showShowcaseMessage(context, 'Report job queued: ${job.queue}');
              }
            }),
          ]),
        ]),
        ShowcaseSection('Streaming Functions', [
          ShowcaseButton(
            isStreaming.value ? 'Stop SSE Stream' : 'Start SSE Stream',
            () {
              if (isStreaming.value) {
                showcaseSubscription?.cancel();
                isStreaming.value = false;
              } else {
                ticks.value = [];
                isStreaming.value = true;
                showcaseSubscription = getTicks().listen(
                  (tick) => ticks.value = [...ticks.value, tick],
                  onDone: () => isStreaming.value = false,
                );
              }
            },
          ),
          if (ticks.value.isNotEmpty)
            DVBox.builder<String>(
              ticks.value,
              (tick) => DVText(tick).modifier(pillStyle),
            ).scrollable().modifier(const DVModifier().height(120)),
        ]),
        ShowcaseSection('i18n, Deferred Pages & Typed Router Actions', [
          DVText('Current Language Locale: $currentLang'),
          DVBox.wrapLine([
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
          DVBox.wrapLine([
            ShowcaseButton('GET /hello', () async {
              final data = await getHelloApi(name: 'Tester');
              if (context.mounted) showShowcaseMessage(context, 'API: $data');
            }),
            ShowcaseButton('POST /echo', () async {
              final data = await postEchoApi(msg: 'System OK');
              if (context.mounted) showShowcaseMessage(context, 'Echo: $data');
            }),
            ShowcaseButton('POST /sum', () async {
              final total = await postSumApi(a: 20, b: 22);
              if (context.mounted) showShowcaseMessage(context, 'Sum: $total');
            }),
            ShowcaseButton('GET /search', () async {
              final data =
                  await getSearchApi(q: 'dartvel', tags: ['ui', 'api']);
              if (context.mounted) {
                showShowcaseMessage(context, 'Search: $data');
              }
            }),
            ShowcaseButton('HEAD /ping', () async {
              final data = await headPingApi();
              if (context.mounted) showShowcaseMessage(context, 'Ping: $data');
            }),
          ]),
        ]),
        ShowcaseSection('CRUD, Files & CSRF', [
          DVBox.wrapLine([
            ShowcaseButton('Create Todo', () async {
              final data = await postDbTodosApi(title: 'Ship Dartvel demo');
              if (context.mounted) {
                showShowcaseMessage(context, 'Created: $data');
              }
            }),
            ShowcaseButton('List Todos', () async {
              final data = await getDbTodosData();
              if (context.mounted) showShowcaseMessage(context, 'Todos: $data');
            }),
            ShowcaseButton('Update Todo', () async {
              final data =
                  await putDbTodosByIdApi(id: '1', title: 'Updated todo');
              if (context.mounted) {
                showShowcaseMessage(context, 'Updated: $data');
              }
            }),
            ShowcaseButton('Delete Todo', () async {
              final data = await deleteDbTodosByIdApi(id: '1');
              if (context.mounted) {
                showShowcaseMessage(context, 'Deleted: $data');
              }
            }),
            ShowcaseButton('Catch-all File Route', () async {
              final data = await getFilesByPathApi(path: ['docs', 'readme.md']);
              if (context.mounted) {
                showShowcaseMessage(context, 'File route: $data');
              }
            }),
            ShowcaseButton('CSRF Token', () {
              final token = DV.CSRF.token();
              showShowcaseMessage(
                  context, 'CSRF token length: ${token.length}');
            }),
          ]),
        ]),
        ShowcaseSection('Storage, Cache, Database & Shell', [
          DVBox.wrapLine([
            ShowcaseButton('Cache', () async {
              await DV.Cache.set('last_run', DateTime.now().toIso8601String());
              final value = await DV.Cache.get<String>('last_run');
              if (context.mounted) {
                showShowcaseMessage(context, 'Cache value: $value');
              }
            }),
            ShowcaseButton('Storage', () async {
              await DV.FileStorage.put('doc.txt', [104, 101, 108, 108, 111]);
              final bytes = await DV.FileStorage.get('doc.txt');
              if (context.mounted) {
                showShowcaseMessage(context, 'Storage bytes: ${bytes.length}');
              }
            }),
            ShowcaseButton('Database', () async {
              final result = await DV.Database.query('select 1');
              if (context.mounted) {
                showShowcaseMessage(context, 'DB Query: $result');
              }
            }),
            ShowcaseButton('Theme Dark/Light', () {
              final next = DV.Theme.mode == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
              DV.Theme.setMode(next);
              showShowcaseMessage(context, 'Theme: ${DV.Theme.mode.name}');
            }),
            ShowcaseButton('DV Shell', () async {
              final result = await DV.$(
                'dart --version',
                environment: const <String, String>{'CI': 'true'},
              );
              if (context.mounted) {
                showShowcaseMessage(
                    context, 'Shell exit code: ${result.exitCode}');
              }
            }),
          ]),
        ]),
        ShowcaseSection('Queues, Jobs & Notifications', [
          const DVText(
            'Signals stay in context and models; durable work is dispatched through queues and jobs.',
          ).modifier(supportingTextStyle),
          DVBox.wrapLine([
            ShowcaseButton('Dispatch Queue Job', () async {
              final events = <String>[];
              DV.Queues.register<String>((value) {
                events.add('processed:$value');
              });
              await DV.Jobs.dispatch<String>('report-ready', queue: 'signals');
              final completed = await DV.Queues.work(queue: 'signals');
              if (context.mounted) {
                showShowcaseMessage(
                    context, 'Jobs completed: $completed, $events');
              }
            }),
            ShowcaseButton('Pending Jobs', () async {
              final pending = await DV.Queues.pending('signals');
              if (context.mounted) {
                showShowcaseMessage(context, 'Pending jobs: ${pending.length}');
              }
            }),
            ShowcaseButton('Send Notification', () async {
              await DV.Notifications.send(
                'demo-user',
                const DVNotificationMessage(
                  title: 'Dartvel',
                  body: 'Unified notification provider is configured.',
                  channels: <DVNotificationChannel>[
                    DVNotificationChannel.inApp,
                    DVNotificationChannel.push,
                    DVNotificationChannel.webPush,
                  ],
                ),
              );
              if (context.mounted) {
                showShowcaseMessage(context, 'Notification sent');
              }
            }),
            ShowcaseButton('Send Mail', () async {
              await DV.Notifications.mail.send(
                const DVMailMessage(
                  from: DVMailAddress('hello@dartvel.dev', name: 'Dartvel'),
                  to: <DVMailAddress>[
                    DVMailAddress('developer@example.com', name: 'Developer'),
                  ],
                  subject: 'Dartvel showcase mail',
                  text: 'Mail is sent through DV.Notifications.mail.',
                ),
              );
              if (context.mounted) showShowcaseMessage(context, 'Mail sent');
            }),
          ]),
        ]),
        ShowcaseSection('Native APIs via Generated Bindings', [
          const DVText(
            'These controls call generated FFI/ffigen or JNI/jnigen bindings. Web preview reports a missing binding instead of simulating device success.',
          ).modifier(supportingTextStyle),
          DVBox.wrapLine([
            ShowcaseButton(
              'Camera',
              () => runShowcaseNativeAction(context, () async {
                final bytes = await DV.Platform.camera.takePhoto();
                if (context.mounted) {
                  showShowcaseMessage(context, 'Photo bytes: $bytes');
                }
              }),
            ),
            ShowcaseButton(
              'Location',
              () => runShowcaseNativeAction(context, () async {
                final data = await DV.Platform.location.getCoordinates();
                if (context.mounted) {
                  showShowcaseMessage(context, 'Location: $data');
                }
              }),
            ),
            ShowcaseButton(
              'Media Picker',
              () => runShowcaseNativeAction(context, () async {
                final data = await DV.Platform.media.pick(multiple: true);
                if (context.mounted) {
                  showShowcaseMessage(context, 'Media: $data');
                }
              }),
            ),
            ShowcaseButton(
              'Permissions',
              () => runShowcaseNativeAction(context, () async {
                final granted = await DV.Platform.permissions.request('camera');
                if (context.mounted) {
                  showShowcaseMessage(context, 'Camera permission: $granted');
                }
              }),
            ),
            ShowcaseButton(
              'Clipboard',
              () => runShowcaseNativeAction(context, () async {
                await DV.Platform.clipboard.copy('Copied from Dartvel');
                final text = await DV.Platform.clipboard.paste();
                if (context.mounted) {
                  showShowcaseMessage(context, 'Clipboard: $text');
                }
              }),
            ),
            ShowcaseButton(
              'Share',
              () => runShowcaseNativeAction(context, () async {
                await DV.Platform.share.shareText('Dartvel showcase');
                if (context.mounted) {
                  showShowcaseMessage(context, 'Share requested');
                }
              }),
            ),
            ShowcaseButton(
              'Notify',
              () => runShowcaseNativeAction(context, () async {
                await DV.Platform.notifications.sendLocalNotification(
                  'Dartvel',
                  'Local notification',
                );
                if (context.mounted) {
                  showShowcaseMessage(context, 'Notification sent');
                }
              }),
            ),
            ShowcaseButton(
              'Bluetooth',
              () => runShowcaseNativeAction(context, () async {
                final enabled = await DV.Platform.bluetooth.isEnabled();
                if (context.mounted) {
                  showShowcaseMessage(context, 'Bluetooth: $enabled');
                }
              }),
            ),
            ShowcaseButton(
              'NFC',
              () => runShowcaseNativeAction(context, () async {
                final tag = await DV.Platform.nfc.readTag();
                if (context.mounted) showShowcaseMessage(context, 'NFC: $tag');
              }),
            ),
            ShowcaseButton(
              'Sensors',
              () => runShowcaseNativeAction(context, () async {
                final value = await DV.Platform.sensors.accelerometer.first;
                if (context.mounted) {
                  showShowcaseMessage(context, 'Accelerometer: $value');
                }
              }),
            ),
            ShowcaseButton(
              'Biometrics',
              () => runShowcaseNativeAction(context, () async {
                final ok = await DV.Platform.biometrics.authenticate();
                if (context.mounted) {
                  showShowcaseMessage(context, 'Biometrics: $ok');
                }
              }),
            ),
            ShowcaseButton(
              'Haptics',
              () => runShowcaseNativeAction(context, () async {
                await DV.Platform.haptics.impact();
                if (context.mounted) {
                  showShowcaseMessage(context, 'Haptic impact requested');
                }
              }),
            ),
            ShowcaseButton(
              'Contacts',
              () => runShowcaseNativeAction(context, () async {
                final contacts = await DV.Platform.contacts.getContacts();
                if (context.mounted) {
                  showShowcaseMessage(context, 'Contacts: $contacts');
                }
              }),
            ),
            ShowcaseButton(
              'Deep Link',
              () => runShowcaseNativeAction(context, () async {
                final link = await DV.Platform.deepLinks.getInitialLink();
                if (context.mounted) {
                  showShowcaseMessage(context, 'Initial link: $link');
                }
              }),
            ),
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
            const DVBox(DVText('Row A')).modifier(rowDemoStyle),
            const DVBox(DVText('Row B')).modifier(rowDemoStyle),
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
          DVBox.builder<String>([
            'Flutter',
            'Dart',
            'Rust',
            'FFI',
            'JNI',
            'Shorebird',
          ], (tag) => DVText(tag).modifier(pillStyle)).wrapLine(),
          DVBox.builder<String>(
            ['Story 1', 'Story 2', 'Story 3'],
            (story) => DVBox(DVText(story)).modifier(storyStyle),
          ).horizontalScrollable().modifier(const DVModifier().height(120)),
          DVBox.masonry([
            FeatureCard('Masonry A', 'Short'),
            FeatureCard('Masonry B', 'Taller generated-card style content'),
            FeatureCard('Masonry C', 'Medium content'),
          ], columns: 2),
        ]),
        ShowcaseSection('AI, Observability & Logging', [
          DVBox.wrapLine([
            ShowcaseButton('Query AI', () async {
              final answer = await DV.AI.chat('What is Dartvel?');
              if (context.mounted) showShowcaseMessage(context, 'AI: $answer');
            }),
            ShowcaseButton('Embedding', () async {
              final vector = await DV.AI.embed('dartvel');
              if (context.mounted) {
                showShowcaseMessage(
                    context, 'Embedding dims: ${vector.length}');
              }
            }),
            ShowcaseButton('Log Event', () {
              unawaited(DV.log('Showcase event logged'));
              showShowcaseMessage(context, 'Event logged successfully');
            }),
            ShowcaseButton('Metric', () async {
              await DV.ObservabilityAndLogging.metric('showcase_metric', 1);
              if (context.mounted) {
                showShowcaseMessage(context, 'Metric emitted');
              }
            }),
            ShowcaseButton('Trace', () async {
              final value = await DV.ObservabilityAndLogging.trace<int>(
                'showcase_trace',
                () => 42,
              );
              if (context.mounted) {
                showShowcaseMessage(context, 'Trace result: $value');
              }
            }),
            ShowcaseButton('Diagnostic', () async {
              await DV.ObservabilityAndLogging.diagnostic(
                'showcase',
                <String, Object>{'healthy': true},
              );
              if (context.mounted) {
                showShowcaseMessage(context, 'Diagnostic emitted');
              }
            }),
          ]),
        ]),
      ]).scrollable().modifier(pageStyle);
    })();

final pageStyle =
    const DVModifier().padding(18).backgroundColor(const Color(0xFFFFFBFE));

final quickActionsStyle = const DVModifier()
    .padding(16)
    .rounded(24)
    .backgroundColor(const Color(0xFFFFD8E4));

final supportingTextStyle = const DVModifier()
    .color(const Color(0xFF49454F))
    .fontSize(14)
    .fontWeight(FontWeight.w600)
    .padding(8);

final pillStyle = const DVModifier()
    .padding(8)
    .rounded(999)
    .backgroundColor(const Color(0xFFCCE5FF))
    .color(const Color(0xFF001D36))
    .fontWeight(FontWeight.w700);

final rowDemoStyle = const DVModifier()
    .width(140)
    .padding(12)
    .rounded(8)
    .backgroundColor(const Color(0xFFFFD8E4))
    .color(const Color(0xFF31111D))
    .fontWeight(FontWeight.w700);

final storyStyle = const DVModifier()
    .width(160)
    .height(88)
    .padding(12)
    .rounded(8)
    .backgroundColor(const Color(0xFFD0BCFF))
    .color(const Color(0xFF21005D))
    .fontWeight(FontWeight.w800);

void showShowcaseMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: DVText(message)));
}

Future<List<String>> seedAndResolveUserPublicPaths() async {
  await DV.Database.execute('delete from users');
  await DV.Database.execute(
    'insert into users (slug, name, email, published, recoveryToken) values (?, ?, ?, ?, ?)',
    <Object?>[
      'ada-lovelace',
      'Ada Lovelace',
      'ada@example.com',
      true,
      'hidden-ada',
    ],
  );
  await DV.Database.execute(
    'insert into users (slug, name, email, published, recoveryToken) values (?, ?, ?, ?, ?)',
    <Object?>[
      'private-draft',
      'Private Draft',
      'draft@example.com',
      false,
      'hidden-draft',
    ],
  );
  return User.publicStaticPaths();
}

Future<void> runShowcaseNativeAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } on StateError catch (error) {
    if (context.mounted) {
      showShowcaseMessage(context, error.toString());
    }
  } on Exception catch (error) {
    if (context.mounted) {
      showShowcaseMessage(context, 'Native action failed: $error');
    }
  }
}
