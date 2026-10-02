// A form somebody can drive without a mouse.
//
// Every form Dartvel renders is a row of inputs and a way to submit it, and
// both halves were drawn for a finger: Enter did nothing from a field, the
// submit control was a picture of a button that no keyboard reached and no
// screen reader named as one, and a password field gave no way to check what
// had been typed.
//
// These drive the form the way a person does -- Tab, Enter, Space, a screen
// reader reading the tree -- rather than asserting on the modifiers that
// produce it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A model of the shape the generator emits, with a `@DVModel.sensitiveField()`
/// on [passwordHash], which is what makes the form draw a password input.
class Member {
  final String id;
  final String name;
  final String passwordHash;
  final int seats;

  const Member({
    required this.id,
    required this.name,
    required this.passwordHash,
    required this.seats,
  });

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'seats': seats,
        // Last, the way a password field is drawn at the bottom of a form
        // rather than between a person's name and their seat count.
        'passwordHash': passwordHash,
      };

  static Member fromJson(Map<String, Object?> json) => Member(
        id: json['id']! as String,
        name: json['name']! as String,
        passwordHash: json['passwordHash']! as String,
        seats: json['seats'] is num
            ? (json['seats']! as num).toInt()
            : num.parse('${json['seats']}').toInt(),
      );
}

/// Everything the generator registers for a model with one sensitive field:
/// the readable fields on forms, the sensitive one write-only.
void registerMember() {
  registerDVModelFactory<Member>(
      () => const Member(id: '', name: '', passwordHash: '', seats: 0));
  registerDVModelSerializer<Member>((Member model) => model.toJson());
  registerDVModelDeserializer<Member>(Member.fromJson);
  registerDVModelFormFields<Member>(const <String>{'id', 'name', 'seats'});
  registerDVModelWriteOnlyFields<Member>(const <String>{'passwordHash'});
}

/// What has the keyboard focus, named the way the framework names it.
///
/// A field's node is named for its label and a pressable's for the name it
/// announces, so "where is the focus" is answerable without a second guess at
/// the widget tree. The eye is the one control with no name of its own, so it
/// is recognised by what it is drawn as.
String focusedLabel() {
  final FocusNode? node = FocusManager.instance.primaryFocus;
  if (node == null) return 'nothing';
  final String? name = node.debugLabel;
  if (name != null) return name;
  if (node.context?.findAncestorWidgetOfExactType<IconButton>() != null) {
    return 'toggle';
  }
  return 'other';
}

void main() {
  setUp(() {
    dvModelFactories.clear();
    dvModelSerializers.clear();
    dvModelDeserializers.clear();
    dvModelReadCarriers.clear();
    dvModelFormFields.clear();
    dvModelWriteOnlyFields.clear();
  });
  tearDown(() {
    dvModelFactories.clear();
    dvModelSerializers.clear();
    dvModelDeserializers.clear();
    dvModelReadCarriers.clear();
    dvModelFormFields.clear();
    dvModelWriteOnlyFields.clear();
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    void Function(Member)? onSubmit,
    Member model = const Member(
        id: 'm1', name: 'Ada', passwordHash: r'$pbkdf2$secret', seats: 3),
  }) async {
    registerMember();
    await tester.pumpWidget(MaterialApp(
      home: Material(child: DVForm<Member>(model, onSubmit)),
    ));
    await tester.pumpAndSettle();
  }

  EditableText input(WidgetTester tester, int index) =>
      tester.widget<EditableText>(find.byType(EditableText).at(index));

  group('Enter', () {
    testWidgets('in the last field submits the form', (tester) async {
      Member? submitted;
      await pumpForm(tester, onSubmit: (Member value) => submitted = value);
      // Both edited on the way, and both read back: the last field is the
      // write-only password input here, which is where a person ends up.
      await tester.enterText(find.byType(EditableText).at(2), '5');
      await tester.enterText(find.byType(EditableText).last, 'new-secret');

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(submitted?.seats, 5);
      expect(submitted?.passwordHash, 'new-secret');
    });

    testWidgets('in a field that is not the last moves to the next field and '
        'submits nothing', (tester) async {
      Member? submitted;
      await pumpForm(tester, onSubmit: (Member value) => submitted = value);
      await tester.tap(find.byType(EditableText).at(0));

      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();

      expect(submitted, isNull);
      expect(focusedLabel(), 'NAME');
    });

    testWidgets('says which action each field offers: next, then done',
        (tester) async {
      await pumpForm(tester, onSubmit: (Member _) {});

      // Next on every field but the last, Done on the last: what the action
      // key on a phone keyboard means, and what it says it means.
      expect(input(tester, 0).textInputAction, TextInputAction.next);
      expect(input(tester, 1).textInputAction, TextInputAction.next);
      expect(input(tester, 2).textInputAction, TextInputAction.next);
      expect(input(tester, 3).textInputAction, TextInputAction.done);
    });

    testWidgets('in a multiline field is a newline, not a submit',
        (tester) async {
      bool submitted = false;
      registerMember();
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: DVFormScope(
            onSubmit: () => submitted = true,
            child: DVBox.list(<Widget>[
              const DVText('').modifier(
                const DVModifier().input(multiline: true, label: 'NOTES'),
              ),
              const DVText('Save').modifier(
                const DVModifier().semanticButton().onTap(() {}),
              ),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(input(tester, 0).textInputAction, TextInputAction.newline);
      await tester.testTextInput.receiveAction(TextInputAction.newline);
      await tester.pumpAndSettle();
      expect(submitted, isFalse);
    });
  });

  group('the submit control', () {
    testWidgets('is a button to a screen reader, named Save',
        (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpForm(tester, onSubmit: (Member _) {});

      // One node, not two. [Focus] brings a node of its own, and a control that
      // stacks a nameless button on the labelled one is announced twice and
      // found by nothing.
      final Finder button = find.bySemanticsLabel('Save');
      expect(button, findsOneWidget);
      final SemanticsNode node = tester.getSemantics(button);
      expect(node.flagsCollection.isButton, isTrue);
      // A button that cannot be pressed is a picture of one.
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

      handle.dispose();
    });

    testWidgets('takes the focus, and Enter and Space both press it',
        (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      Member? submitted;
      await pumpForm(tester, onSubmit: (Member value) => submitted = value);
      await tester.tap(find.byType(EditableText).at(0));
      await tester.pumpAndSettle();
      // Walk to the control the way a reader does, rather than jumping.
      for (int i = 0; i < 6 && focusedLabel() != 'control:Save'; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }
      expect(focusedLabel(), 'control:Save');
      // The focus is not only visible: the node the reader is on says so, and
      // offers the action that moves the focus there for someone who cannot
      // press Tab.
      final SemanticsData focused = tester
          .getSemantics(find.bySemanticsLabel('Save'))
          .getSemanticsData();
      expect(focused.flagsCollection.isFocused.toBoolOrNull(), isTrue);
      expect(focused.hasAction(SemanticsAction.focus), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(submitted, isNotNull);

      submitted = null;
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(submitted, isNotNull);

      handle.dispose();
    });

    testWidgets('has a focus ring drawn on it while it holds the focus',
        (tester) async {
      await pumpForm(tester, onSubmit: (Member _) {});
      // Read the ring off the control's own box rather than looking for a
      // marker widget: a ring a person cannot see is not a focus indicator,
      // and the decoration is what is actually painted.
      Border? ring() {
        final Object? decoration = tester
            .widget<Container>(
              find.byKey(const ValueKey<String>('dv-control:Save')),
            )
            .foregroundDecoration;
        return decoration is BoxDecoration
            ? (decoration.border as Border?)
            : null;
      }

      expect(ring(), isNull);

      await tester.tap(find.byType(EditableText).at(0));
      await tester.pumpAndSettle();
      for (int i = 0; i < 6 && focusedLabel() != 'control:Save'; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }

      expect(ring(), isNotNull);
    });
  });

  group('Tab order', () {
    testWidgets('walks the fields, the toggle and Save in the order drawn',
        (tester) async {
      await pumpForm(tester, onSubmit: (Member _) {});
      await tester.tap(find.byType(EditableText).at(0));
      await tester.pumpAndSettle();

      final List<String> walked = <String>[focusedLabel()];
      for (int i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        walked.add(focusedLabel());
      }

      expect(walked, <String>[
        'ID',
        'NAME',
        'SEATS',
        'PASSWORDHASH',
        'toggle',
        'control:Save',
      ]);
    });

    testWidgets('Shift+Tab walks it backwards', (tester) async {
      await pumpForm(tester, onSubmit: (Member _) {});
      await tester.tap(find.byType(EditableText).at(0));
      await tester.pumpAndSettle();

      final List<String> walked = <String>[];
      for (int i = 0; i < 5; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        walked.add(focusedLabel());
      }

      // Backwards from the first field is the end of the form, and round it
      // again: someone walking back up a form meets it in the order it was
      // drawn, not stopped at the top.
      expect(walked, <String>[
        'control:Reset',
        'control:Save',
        'toggle',
        'PASSWORDHASH',
        'SEATS',
      ]);
    });
  });

  group('a password field', () {
    testWidgets('carries an eye toggle by default', (tester) async {
      await pumpForm(tester, onSubmit: (Member _) {});

      final int index = _passwordIndex(tester);
      expect(input(tester, index).obscureText, isTrue);
      expect(_toggle(tester), findsOneWidget);
    });

    testWidgets('says what pressing it will do, and does it',
        (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpForm(tester, onSubmit: (Member _) {});
      // Which field it is, before it is revealed: after, nothing is obscured
      // and the same search would not find it.
      final int password = _passwordIndex(tester);

      final SemanticsNode show = tester.getSemantics(_toggle(tester));
      expect(show.label, 'Show password');

      await tester.tap(_toggle(tester));
      await tester.pumpAndSettle();

      expect(input(tester, password).obscureText, isFalse);
      expect(tester.getSemantics(_toggle(tester)).label, 'Hide password');

      handle.dispose();
    });

    testWidgets('the toggle is reachable from the keyboard', (tester) async {
      await pumpForm(tester, onSubmit: (Member _) {});
      final int password = _passwordIndex(tester);
      await tester.tap(find.byType(EditableText).at(0));
      await tester.pumpAndSettle();

      String label = focusedLabel();
      while (label != 'toggle') {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        label = focusedLabel();
      }
      expect(label, 'toggle');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(input(tester, password).obscureText, isFalse);
    });

    testWidgets('.none turns it off', (tester) async {
      registerMember();
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: DVFormScope(
            child: DVBox.list(<Widget>[
              const DVText('').modifier(const DVModifier().input(
                    label: 'PASSWORD',
                    obscureText: true,
                    visibilityToggle: .none,
                  )),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(_toggle(tester), findsNothing);
      expect(input(tester, 0).obscureText, isTrue);
    });

    testWidgets('.custom draws the application\'s own control, and it flips '
        'the field', (tester) async {
      registerMember();
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: DVFormScope(
            child: DVBox.list(<Widget>[
              const DVText('').modifier(const DVModifier().input(
                    label: 'PASSWORD',
                    obscureText: true,
                    visibilityToggle: .custom(
                      (BuildContext context, bool obscured, VoidCallback toggle) =>
                          TextButton(
                        onPressed: toggle,
                        child: Text(obscured ? 'Reveal it' : 'Hide it'),
                      ),
                    ),
                  )),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(_toggle(tester), findsNothing);
      expect(find.text('Reveal it'), findsOneWidget);

      await tester.tap(find.text('Reveal it'));
      await tester.pumpAndSettle();

      expect(find.text('Hide it'), findsOneWidget);
      expect(input(tester, 0).obscureText, isFalse);
    });

    testWidgets('a custom toggle is given the state and a way to change it',
        (tester) async {
      bool? seen;
      bool pressed = false;
      registerMember();
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: DVFormScope(
            child: const DVText('').modifier(const DVModifier().input(
                  label: 'PASSWORD',
                  obscureText: true,
                  visibilityToggle: .custom(
                    (BuildContext context, bool obscured, VoidCallback toggle) {
                      seen = obscured;
                      return TextButton(
                        onPressed: () {
                          pressed = true;
                          toggle();
                        },
                        child: const Text('toggle'),
                      );
                    },
                  ),
                )),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(seen, isTrue);
      await tester.tap(find.text('toggle'));
      await tester.pumpAndSettle();
      expect(pressed, isTrue);
      expect(seen, isFalse);
    });
  });

  group('a refused submit', () {
    testWidgets('is announced, and focus goes to the field at fault',
        (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpForm(tester,
          onSubmit: (Member _) => throw StateError('seats is not a number'));
      // The last field, because that is where Enter saves. Editing another one
      // moves on to the next field instead, which is the other half of it.
      await tester.enterText(find.byType(EditableText).last, 'Ada L.');

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final Finder error = find.bySemanticsLabel(RegExp('seats'));
      expect(error, findsWidgets);
      // Announced as it appears: nothing else on the page changed, so a live
      // region is the only thing that makes a screen reader say it.
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey<String>('dv-form-error')))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      expect(focusedLabel(), 'SEATS');

      handle.dispose();
    });

    testWidgets('a value the model cannot hold names the field and focuses '
        'it', (tester) async {
      await pumpForm(tester, onSubmit: (Member _) {});
      await tester.enterText(find.byType(EditableText).at(3), 'new-secret');

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      // Fine: a string is what that field holds.
      expect(find.textContaining('not a valid value'), findsNothing);

      // The seats field is the one the model cannot be built from.
      await tester.enterText(find.byType(EditableText).at(0), 'm1');
      await tester.enterText(find.byType(EditableText).at(1), 'Ada');
      await tester.enterText(find.byType(EditableText).at(2), 'many');
      await tester.tap(find.byType(EditableText).last);
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Named by what it says, so the message is where a reader hears it and
      // where they can find it again, and the field it names says it too.
      expect(find.bySemanticsLabel(RegExp('not a valid value')), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('dv-form-error')),
          matching: find.textContaining('not a valid value'),
        ),
        findsOneWidget,
      );
      expect(focusedLabel(), 'SEATS');
    });

    testWidgets('an accepted submit clears the announcement',
        (tester) async {
      Member? submitted;
      bool refuse = true;
      await pumpForm(tester, onSubmit: (Member value) {
        submitted = value;
        if (refuse) throw StateError('seats is not a number');
      });
      final Finder last = find.byType(EditableText).last;

      await tester.enterText(last, 'Ada L.');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('dv-form-error')),
          findsOneWidget);

      refuse = false;
      submitted = null;
      await tester.enterText(find.byType(EditableText).at(1), 'Ada Lovelace');
      await tester.enterText(last, 'new-secret');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(submitted?.name, 'Ada Lovelace');
      expect(find.byKey(const ValueKey<String>('dv-form-error')), findsNothing);
    });
  });
}

/// Where the write-only input sits among the readable ones: last, because the
/// generator writes it into the form after them.
int _passwordIndex(WidgetTester tester) =>
    tester.widgetList<EditableText>(find.byType(EditableText))
        .toList()
        .indexWhere((EditableText field) => field.obscureText);

Finder _toggle(WidgetTester tester) => find.byType(IconButton);
