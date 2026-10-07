import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  setUp(() {
    DV.Auth.configure(DVLocalAuthProvider());
    DV.Test.fakeDatabase();
  });

  testWidgets('signup returns to the internal destination with its query', (tester) async {
    final router = GoRouter(initialLocation: '/join', routes: [
      GoRoute(path: '/join', builder: (_, __) => DV.Auth.SignUpPage(from: '/after?filter=mine')),
      GoRoute(path: '/after', builder: (_, __) => const Text('Returned')),
    ]);
    DVNavigation.attach(router);
    addTearDown(() { DVNavigation.detach(); router.dispose(); });
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.enterText(find.byKey(const ValueKey('dv-signup-email')), 'return@example.com');
    await tester.enterText(find.byKey(const ValueKey('dv-signup-password')), 'a long enough passphrase');
    await tester.testTextInput.receiveAction(.done);
    await tester.pumpAndSettle();
    expect(find.text('Returned'), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.queryParameters['filter'], 'mine');
  });

  testWidgets('sign-in pending disables the button and ignores a second Enter', (tester) async {
    final provider = _PendingAuth();
    DV.Auth.configure(provider);
    await tester.pumpWidget(MaterialApp(home: DV.Auth.SignInWithEmailAndPasswordPage()));
    await tester.enterText(find.byKey(const ValueKey('dv-auth-email')), 'ada@example.com');
    await tester.enterText(find.byKey(const ValueKey('dv-auth-password')), 'correct horse');
    await tester.testTextInput.receiveAction(.done);
    await tester.pump();
    final button = find.descendant(of: find.byKey(const ValueKey('dv-auth-submit')),
      matching: find.byType(FilledButton));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.testTextInput.receiveAction(.done);
    expect(provider.calls, 1);
    provider.result.completeError(StateError('private auth service detail'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(find.textContaining('private auth service detail'), findsNothing);
  });

  testWidgets('sign in announces a refused password inline', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(home: DV.Auth.SignInWithEmailAndPasswordPage()),
    );
    await tester.enterText(
      find.byKey(const ValueKey('dv-auth-email')),
      'ada@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('dv-auth-password')),
      'wrong',
    );
    await tester.testTextInput.receiveAction(.done);
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('dv-auth-error')))
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('dv-auth-password')))
          .decoration
          ?.errorText,
      isNotNull,
    );
    handle.dispose();
  });

  testWidgets('sign in offers account creation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DV.Auth.SignInWithEmailAndPasswordPage()),
    );
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dv-signup-email')), findsOneWidget);
    expect(find.text('Already have an account? Sign in'), findsOneWidget);
  });

  testWidgets(
    'wide sign in has a brand panel; watch scrolls without overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: DV.Auth.SignInWithEmailAndPasswordPage()),
      );
      expect(find.byKey(const ValueKey('dv-auth-brand-panel')), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(200, 200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('dv-auth-brand-panel')), findsNothing);
    },
  );

  testWidgets('form awaits save, blocks repeats and retains edits on failure', (
    tester,
  ) async {
    registerDVModelFactory<_Draft>(() => const _Draft(''));
    registerDVModelSerializer<_Draft>((value) => {'title': value.title});
    registerDVModelDeserializer<_Draft>(
      (json) => _Draft(json['title']! as String),
    );
    addTearDown(() {
      dvModelFactories.remove(_Draft);
      dvModelSerializers.remove(_Draft);
      dvModelDeserializers.remove(_Draft);
    });
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: DVForm<_Draft>(const _Draft(''), (_) async {
            calls++;
            await pending.future;
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Keep this edit');
    await tester.testTextInput.receiveAction(.done);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.testTextInput.receiveAction(.done);
    expect(calls, 1);
    pending.completeError(StateError('private backend detail'));
    await tester.pumpAndSettle();
    expect(find.text('Keep this edit'), findsOneWidget);
    expect(find.textContaining('private backend detail'), findsNothing);
    expect(find.byKey(const ValueKey('dv-form-error')), findsOneWidget);
  });
}

class const _Draft(final String title);

class _PendingAuth extends DVLocalAuthProvider {
  final result = Completer<DVAuthUser>();
  int calls = 0;
  @override
  Future<DVAuthUser> signInWithEmailAndPassword({required String email, required String password}) {
    calls++;
    return result.future;
  }
}
