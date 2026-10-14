// Every password field in every Dartvel app can be read back before it is
// sent, by the same control, named the same way, on every screen.
//
// The eye existed on a form's password field and on the account pages, and
// nowhere in Studio: Studio's sign-in, its first-run setup and its record
// editor drew bare obscured fields, so the one person who most needs to check
// a long printed password -- the owner setting Studio up -- could not. And the
// eye that did exist changed its name with its state ("Show password", then
// "Hide password"), which is the pattern ARIA warns against: a toggle keeps
// one name and says whether it is pressed.
//
// These drive the field the way a person does: by tapping, by Tab and Space,
// and by what a screen reader is told.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/widgets/password_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Member {
  final String id;
  final String name;
  final String passwordHash;

  const _Member({
    required this.id,
    required this.name,
    required this.passwordHash,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'passwordHash': passwordHash,
  };

  static _Member fromJson(Map<String, Object?> json) => _Member(
    id: json['id']! as String,
    name: json['name']! as String,
    passwordHash: json['passwordHash']! as String,
  );
}

void _registerMember() {
  registerDVModelFactory<_Member>(
    () => const _Member(id: '', name: '', passwordHash: ''),
  );
  registerDVModelSerializer<_Member>((_Member model) => model.toJson());
  registerDVModelDeserializer<_Member>(_Member.fromJson);
  registerDVModelFormFields<_Member>(const <String>{'id', 'name'});
  registerDVModelWriteOnlyFields<_Member>(const <String>{'passwordHash'});
}

/// A Studio server that answers nothing but the sign-in pages' first reads.
Future<DVStudioReply> _studioServer(
  String method,
  String path, {
  Object? body,
}) async => const DVStudioReply(404, <String, Object?>{});

/// Every place a password is typed in Dartvel, each pumped on its own.
final Map<String, Future<void> Function(WidgetTester)> _hosts =
    <String, Future<void> Function(WidgetTester)>{
      'a data model form': (WidgetTester tester) async {
        _registerMember();
        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: DVForm<_Member>(
                const _Member(id: 'm1', name: 'Ada', passwordHash: 'x'),
                (_Member _) {},
              ),
            ),
          ),
        );
      },
      'the sign-in page': (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(home: DV.Auth.SignInWithEmailAndPasswordPage()),
        );
      },
      'Studio sign-in': (WidgetTester tester) async {
        await tester.pumpWidget(
          DVStudioApp(
            client: DVStudioClient(_studioServer),
            title: 'Studio · shop',
            location: Uri.parse('https://shop.example/__studio/login'),
            open: (_) {},
          ),
        );
      },
      'Studio first-run setup': (WidgetTester tester) async {
        await tester.pumpWidget(
          DVStudioApp(
            client: DVStudioClient(_studioServer),
            title: 'Studio · shop',
            location: Uri.parse('https://shop.example/__studio/setup'),
            open: (_) {},
          ),
        );
      },
      'a Studio write-only field': (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Material(child: DVStudioTextInput(obscureText: true)),
          ),
        );
      },
    };

Future<void> _pump(WidgetTester tester, String host) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await _hosts[host]!(tester);
  await tester.pumpAndSettle();
}

List<EditableText> _obscurable(WidgetTester tester) => tester
    .widgetList<EditableText>(find.byType(EditableText))
    .where((EditableText field) => field.obscureText)
    .toList();

void main() {
  setUp(() {
    DV.Auth.configure(DVLocalAuthProvider());
    DV.Test.fakeDatabase();
    dvModelFactories.clear();
    dvModelSerializers.clear();
    dvModelDeserializers.clear();
    dvModelFormFields.clear();
    dvModelWriteOnlyFields.clear();
    dvServerField = (String _) => null;
  });

  for (final String host in _hosts.keys) {
    group('on $host', () {
      testWidgets('every hidden field has the eye', (
        WidgetTester tester,
      ) async {
        await _pump(tester, host);
        final int hidden = _obscurable(tester).length;
        expect(hidden, greaterThan(0));
        expect(find.byType(DVPasswordReveal), findsNWidgets(hidden));
      });

      testWidgets('it is one button with one name, shown as its tooltip, and says '
          'whether it is pressed', (WidgetTester tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await _pump(tester, host);
        final Finder eye = find.byType(DVPasswordReveal).first;

        expect(
          tester.getSemantics(eye),
          matchesSemantics(
            label: 'Show password',
            tooltip: '',
            isButton: true,
            hasTapAction: true,
            hasToggledState: true,
            isToggled: false,
            isFocusable: true,
            hasFocusAction: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );

        // Its name is shown as a tooltip too, which is not read a second
        // time: "Show password Show password" is what a browser's screen
        // reader got when both were in the semantics.
        final Tooltip tooltip = tester.widget<Tooltip>(find.descendant(
            of: eye, matching: find.byType(Tooltip)));
        expect(tooltip.message, 'Show password');
        expect(tooltip.excludeFromSemantics, isTrue);
        // The capture recognises it by its identifier, one per eye.
        expect(tester.getSemantics(eye).getSemanticsData().identifier,
            startsWith('dartvel:reveal|'));

        await tester.tap(eye);
        await tester.pumpAndSettle();

        // The same name, pressed: a toggle that renamed itself would be read
        // as "Hide password, pressed", which means the opposite of what it is.
        expect(
          tester.getSemantics(find.byType(DVPasswordReveal).first),
          matchesSemantics(
            label: 'Show password',
            tooltip: '',
            isButton: true,
            hasTapAction: true,
            hasToggledState: true,
            isToggled: true,
            isFocusable: true,
            hasFocusAction: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );
        handle.dispose();
      });

      testWidgets('pressing it shows what was typed, and again hides it', (
        WidgetTester tester,
      ) async {
        await _pump(tester, host);
        final int before = _obscurable(tester).length;

        await tester.tap(find.byType(DVPasswordReveal).first);
        await tester.pumpAndSettle();
        expect(_obscurable(tester).length, before - 1);

        await tester.tap(find.byType(DVPasswordReveal).first);
        await tester.pumpAndSettle();
        expect(_obscurable(tester).length, before);
      });

      testWidgets('the keyboard reaches it and Space presses it', (
        WidgetTester tester,
      ) async {
        await _pump(tester, host);
        final int before = _obscurable(tester).length;
        final FocusNode? eye = Focus.maybeOf(
          tester.element(
            find.descendant(
              of: find.byType(DVPasswordReveal).first,
              matching: find.byType(IconButton),
            ),
          ),
        );

        // Walk with Tab until the eye has focus, the way a person would.
        bool reached = false;
        for (int step = 0; step < 30 && !reached; step++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          reached =
              eye != null && eye.hasFocus ||
              FocusManager.instance.primaryFocus?.context
                      ?.findAncestorWidgetOfExactType<DVPasswordReveal>() !=
                  null;
        }
        expect(reached, isTrue, reason: 'Tab never reached the eye');

        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(_obscurable(tester).length, before - 1);
      });
    });
  }

  group('taking over from the server-rendered page', () {
    testWidgets('a password typed and revealed before Flutter painted is kept, '
        'and stays revealed', (WidgetTester tester) async {
      dvServerField = (String label) => label == 'Password'
          ? const DVServerFieldState(value: 'typed early', revealed: true)
          : null;
      await _pump(tester, 'Studio sign-in');

      final EditableText password = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('dv-studio-sign-in-password')),
          matching: find.byType(EditableText),
        ),
      );
      expect(password.controller.text, 'typed early');
      expect(password.obscureText, isFalse);
    });

    testWidgets('the address typed beside it is kept too',
        (WidgetTester tester) async {
      dvServerField = (String label) => label == 'Email'
          ? const DVServerFieldState(value: 'early@example.com', revealed: false)
          : null;
      await _pump(tester, 'Studio sign-in');
      final EditableText email = tester.widget<EditableText>(find.descendant(
          of: find.byKey(const ValueKey<String>('dv-studio-sign-in-email')),
          matching: find.byType(EditableText)));
      expect(email.controller.text, 'early@example.com');
    });

    testWidgets('a field the server did not render starts empty and hidden', (
      WidgetTester tester,
    ) async {
      await _pump(tester, 'Studio sign-in');
      final EditableText password = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('dv-studio-sign-in-password')),
          matching: find.byType(EditableText),
        ),
      );
      expect(password.controller.text, isEmpty);
      expect(password.obscureText, isTrue);
    });

    testWidgets('a data model form takes over its password field too', (
      WidgetTester tester,
    ) async {
      dvServerField = (String label) =>
          const DVServerFieldState(value: 'early', revealed: true);
      await _pump(tester, 'a data model form');
      final List<EditableText> all = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .toList();
      // Readable fields keep the record's own values: only a password field
      // is something a person could have been typing into before the app ran.
      expect(
        all.where((EditableText f) => f.controller.text == 'early'),
        hasLength(1),
      );
      expect(_obscurable(tester), isEmpty);
    });
  });
}
