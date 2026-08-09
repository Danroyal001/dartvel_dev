// The outbox and the policy/sync explorer, against real registries.
//
// Both exist to distinguish two states that look identical from calling code:
// a message nobody sent from one a provider accepted, and a policy that denied
// from one that was never registered.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Invoice {
  const Invoice();
}

void main() {
  group('outbox', () {
    testWidgets('mail that was sent is listed with its recipient',
        (WidgetTester tester) async {
      final mail = DVMemoryMailProvider();
      await mail.send(const DVMailMessage(
        from: const DVMailAddress('noreply@example.com'),
        to: <DVMailAddress>[DVMailAddress('a@example.com')],
        subject: 'Your invoice',
        text: 'body',
      ));

      await tester.pumpWidget(MaterialApp(
        home: Material(child: DVOutboxAdmin(mail: mail)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Mail (1)'), findsOneWidget);
      expect(find.text('Your invoice'), findsOneWidget);
      expect(find.text('to a@example.com'), findsOneWidget);
    });

    testWidgets('an empty outbox says nothing was sent',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Material(child: DVOutboxAdmin(mail: DVMemoryMailProvider())),
      ));
      await tester.pumpAndSettle();

      // "Nothing sent" and "never called" are the same to the caller; this is
      // the only place they are told apart.
      expect(find.text('No mail sent.'), findsOneWidget);
      expect(find.text('Mail (0)'), findsOneWidget);
    });

    testWidgets('no in-memory provider is explained, not shown as empty',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Material(child: DVOutboxAdmin()),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('No in-memory provider configured'),
          findsOneWidget);
      expect(find.text('No mail sent.'), findsNothing);
    });

    testWidgets('notifications are listed alongside mail',
        (WidgetTester tester) async {
      final notifications = DVMemoryNotificationProvider();
      await notifications.send(
        'device-1',
        const DVNotificationMessage(title: 'Shipped', body: 'On its way'),
      );

      await tester.pumpWidget(MaterialApp(
        home: Material(child: DVOutboxAdmin(notifications: notifications)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Notifications (1)'), findsOneWidget);
      expect(find.text('Shipped'), findsOneWidget);
      expect(find.text('to device-1'), findsOneWidget);
    });
  });

  group('policy and sync explorer', () {
    tearDown(() {
      const DVTestHarness().resetPolicies();
    });

    testWidgets('registered policies are listed by action and resource',
        (WidgetTester tester) async {
      const DVAuthAuthorization()
          .register<String, Invoice>('view', (String user, Invoice _) => true);

      await tester.pumpWidget(const MaterialApp(
        home: Material(child: DVPolicyAdmin()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Policies (1)'), findsOneWidget);
      expect(find.text('view:Invoice'), findsOneWidget);
    });

    testWidgets('an empty policy registry explains why everything denies',
        (WidgetTester tester) async {
      const DVTestHarness().resetPolicies();

      await tester.pumpWidget(const MaterialApp(
        home: Material(child: DVPolicyAdmin()),
      ));
      await tester.pumpAndSettle();

      // `can` returns false for an unregistered policy, which reads as a
      // deny rather than as a missing registration.
      expect(find.text('No policies registered — every check denies.'),
          findsOneWidget);
    });

    testWidgets('a model with no codec is reported, since its envelopes drop',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Material(child: DVPolicyAdmin()),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('No codec registered — incoming envelopes are dropped.'),
        findsOneWidget,
      );
    });

    testWidgets('a registered codec appears as a decodable wire name',
        (WidgetTester tester) async {
      DVModelSync.registerCodec<Invoice>(
        name: 'Invoice',
        encode: (Invoice model) => <String, Object?>{},
        decode: (Map<String, Object?> json) => const Invoice(),
      );

      await tester.pumpWidget(const MaterialApp(
        home: Material(child: DVPolicyAdmin()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Invoice'), findsOneWidget);
      expect(find.textContaining('Decodable wire names (1)'), findsOneWidget);
    });
  });
}
