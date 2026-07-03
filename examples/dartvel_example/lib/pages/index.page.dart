import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_example/dartvel_client/functions.g.dart';
import 'package:dartvel_example/models/user.dart';
import 'package:flutter/widget_previews.dart';
import 'package:go_router/go_router.dart';

/// The main dashboard page for showcasing the Dartvel platform.
class IndexPage extends DartvelPage {
  /// Preview constructor
  @Preview()
  const IndexPage({super.key});

  @override
  SeoProps buildWebSeo(Map<String, String> params, Map<String, String> query) =>
      const SeoProps(
          title: 'Home • Dartvel Demo',
          description: 'Welcome to the Dartvel demo!');

  static StreamSubscription<String>? _subscription;

  @override
  Widget build(BuildContext context) {
    // 1. Signals & State Management
    final counter = context.signal(0);
    final isStreaming = context.signal(false);
    final ticks = context.signal(<String>[]);

    // 2. Styling Modifier primitives
    final titleStyle = const DVStyleModifier()
        .color(const Color(0xFF6200EE))
        .padding(8);
        
    final cardStyle = const DVStyleModifier()
        .card()
        .margin(8)
        .backgroundColor(const Color(0xFFF5F5F5));

    final currentLangScope = DvI18nScope.of(context).localeTag;
    final currentLang = currentLangScope.isEmpty ? 'system' : currentLangScope;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dartvel Platform Showcase'),
        actions: [
          IconButton(
            icon: const Icon(Icons.palette),
            onPressed: () {
              // Showcase Theme switching
              final themeMode = DV.Theme.mode;
              DV.Theme.setMode(themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Theme mode set to ${DV.Theme.mode}')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with Primitives
            DVBox(
              modifier: titleStyle,
              child: const DVText(
                'Welcome to Dartvel full-stack app platform!',
              ),
            ),
            const SizedBox(height: 16),

            // Card 1: State Management (Signals)
            DVBox(
              modifier: cardStyle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('1. Signals State Management', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Local counter signal value: ${counter.value}'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => counter.value = counter.value + 1,
                    child: const Text('Increment Counter Signal'),
                  ),
                ],
              ),
            ),

            // Card 2: Platform Detection & APIs
            DVBox(
              modifier: cardStyle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('2. Platform Info & Expo-style APIs', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Is Web: ${DV.Platform.isWeb}'),
                  Text('Is Android: ${DV.Platform.isAndroid}'),
                  Text('Is iOS: ${DV.Platform.isIOS}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          final coords = await DV.Platform.location.getCoordinates();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Location coords: $coords')),
                            );
                          }
                        },
                        child: const Text('Get Coordinates'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          await DV.Platform.notifications.sendLocalNotification(
                            'Dartvel Alert',
                            'This is a local device notification!',
                          );
                        },
                        child: const Text('Send Notification'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Card 3: Auth & Tenants
            DVBox(
              modifier: cardStyle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('3. Authentication & Multi-Tenancy', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Current Tenant: ${DV.currentTenant}'),
                  Text('User status: ${DV.Auth.currentUser ?? "Not Logged In"}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          await DV.Auth.signIn();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Signed in successfully')),
                            );
                          }
                        },
                        child: const Text('Sign In'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          await DV.Auth.signOut();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Signed out successfully')),
                            );
                          }
                        },
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Card 4: Model Forms
            DVBox(
              modifier: cardStyle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('4. Model Form (DVForm<User>)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DVForm<User>(
                    initialValue: const User(name: 'John Doe', email: 'john@example.com'),
                    builder: (context, user) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Editing model: User(${user.name}, ${user.email})'),
                          const SizedBox(height: 8),
                          TextFormField(
                            initialValue: user.name,
                            decoration: const InputDecoration(labelText: 'Name'),
                          ),
                          TextFormField(
                            initialValue: user.email,
                            decoration: const InputDecoration(labelText: 'Email'),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            // Card 5: Streaming Functions (SSE client stream)
            DVBox(
              modifier: cardStyle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('5. SSE Backend Stream (ticks.get.dart)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (isStreaming.value) {
                        _subscription?.cancel();
                        isStreaming.value = false;
                      } else {
                        ticks.value = [];
                        isStreaming.value = true;
                        _subscription = getTicks().listen(
                          (tick) {
                            ticks.value = [...ticks.value, tick];
                          },
                          onDone: () {
                            isStreaming.value = false;
                          },
                        );
                      }
                    },
                    child: Text(isStreaming.value ? 'Stop SSE Stream' : 'Start SSE Stream'),
                  ),
                  if (ticks.value.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      height: 100,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ListView.builder(
                        itemCount: ticks.value.length,
                        itemBuilder: (context, idx) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: Text(ticks.value[idx]),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Card 6: Multi-language (i18n) & Router Actions
            DVBox(
              modifier: cardStyle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('6. i18n & Router Actions', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Current Language Locale: $currentLang'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: () => DvI18n.updateLang(context, 'lang', 'en-US'),
                        child: const Text('Set Locale: EN-US'),
                      ),
                      ElevatedButton(
                        onPressed: () => DvI18n.updateLang(context, 'lang', 'fr-FR'),
                        child: const Text('Set Locale: FR-FR'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => context.push('/blog/101'),
                    child: const Text('Navigate to Dynamic Route (/blog/101)'),
                  ),
                ],
              ),
            ),

            // Card 7: Direct API actions
            DVBox(
              modifier: cardStyle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('7. Direct Typed API Call Actions', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          final data = await getHelloApi(name: 'Tester');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('API: $data')),
                            );
                          }
                        },
                        child: const Text('GET /hello?name=Tester'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          final data = await postEchoApi(msg: 'System OK');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Echo: $data')),
                            );
                          }
                        },
                        child: const Text('POST /echo'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
