// SSR-first: what a visitor typed into the server-rendered page's fields
// before Flutter took over is carried into the app's own fields at the
// handover, with focus and caret, and nothing typed is lost.
//
// sigmadev.digital's keyword density checker on a phone (Dartvel 3.47.9):
// the document's fields could not be typed in at all before the handover,
// and once they could, the handover would have thrown away whatever was in
// them. dvCarrySsrFields matches each document field to the app's field of
// the same name (its semantics label, as the build wrote it into the
// document), or, where the names say nothing and both pages have the same
// fields, by order.
import 'package:dartvel_flutter/src/seo/ssr_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Form extends StatelessWidget {
  const _Form({
    required this.content,
    required this.phrase,
    required this.contentFocus,
    required this.typed,
  });

  final TextEditingController content;
  final TextEditingController phrase;
  final FocusNode contentFocus;
  final List<String> typed;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: <Widget>[
          // As sigmadev's tools draw a field: the name is a Semantics label
          // round the field, the hint is the decoration's.
          Semantics(
            label: 'Your content',
            child: TextField(
              controller: content,
              focusNode: contentFocus,
              maxLines: null,
              decoration: const InputDecoration(hintText: 'Paste your page'),
              onChanged: (String value) => typed.add('content:$value'),
            ),
          ),
          TextField(
            controller: phrase,
            decoration: const InputDecoration(labelText: 'Phrase length (words)'),
            onChanged: (String value) => typed.add('phrase:$value'),
          ),
        ],
      ),
    ),
  );
}

void main() {
  late TextEditingController content;
  late TextEditingController phrase;
  late FocusNode contentFocus;
  late List<String> typed;

  setUp(() {
    content = TextEditingController();
    phrase = TextEditingController(text: '1');
    contentFocus = FocusNode();
    typed = <String>[];
  });

  Future<void> pumpForm(WidgetTester tester) => tester.pumpWidget(
    _Form(content: content, phrase: phrase, contentFocus: contentFocus, typed: typed),
  );

  testWidgets('what was typed reaches the field of the same name, with its caret and focus',
      (WidgetTester tester) async {
    await pumpForm(tester);
    final DVSsrFieldCarry carry = dvCarrySsrFields(const <DVSsrField>[
      DVSsrField(name: 'Your content', value: 'hello wor', edited: true, focused: true, selectionStart: 9, selectionEnd: 9),
      DVSsrField(name: 'Phrase length (words)', value: '2', edited: true),
    ]);
    await tester.pump();
    expect(content.text, 'hello wor');
    expect(content.selection, const TextSelection.collapsed(offset: 9));
    expect(phrase.text, '2');
    expect(contentFocus.hasFocus, isTrue, reason: 'focus stays where the visitor was typing');
    expect(typed, containsAll(<String>['content:hello wor', 'phrase:2']),
        reason: "the app hears it as typing: a tool recomputes from its field's onChanged");
    expect(carry.matched, 2);
  });

  testWidgets('typing that lands in the document field after the carry follows it, mid-word',
      (WidgetTester tester) async {
    await pumpForm(tester);
    final DVSsrFieldCarry carry = dvCarrySsrFields(const <DVSsrField>[
      DVSsrField(name: 'Your content', value: 'hello wor', edited: true, focused: true, selectionStart: 9, selectionEnd: 9),
    ]);
    await tester.pump();
    carry.follow(0, 'hello world', selectionStart: 11, selectionEnd: 11);
    await tester.pump();
    expect(content.text, 'hello world');
    expect(content.selection, const TextSelection.collapsed(offset: 11));
    expect(typed.last, 'content:hello world');
  });

  // sigmadev's keyword density checker in Chrome: three keys typed in the
  // moment between the document field letting go and the app's field having
  // the keyboard (the page itself had focus) were lost ("and mo" became
  // "andre"). Those keys are typed into the app's field.
  testWidgets('keys typed while neither field has the keyboard go into the app field',
      (WidgetTester tester) async {
    await pumpForm(tester);
    final DVSsrFieldCarry carry = dvCarrySsrFields(const <DVSsrField>[
      DVSsrField(name: 'Your content', value: 'and', edited: true, focused: true, selectionStart: 3, selectionEnd: 3),
    ]);
    await tester.pump();
    carry
      ..typeText(0, ' ')
      ..typeText(0, 'm')
      ..typeText(0, 'x')
      ..deleteBackward(0)
      ..typeText(0, 'o');
    await tester.pump();
    expect(content.text, 'and mo');
    expect(content.selection, const TextSelection.collapsed(offset: 6));
    expect(typed.last, 'content:and mo');
  });

  testWidgets('a selected range stays selected', (WidgetTester tester) async {
    await pumpForm(tester);
    dvCarrySsrFields(const <DVSsrField>[
      DVSsrField(name: 'Your content', value: 'pick these words', edited: true, focused: true, selectionStart: 5, selectionEnd: 10),
    ]);
    await tester.pump();
    expect(content.selection, const TextSelection(baseOffset: 5, extentOffset: 10));
  });

  testWidgets("a field the visitor never touched keeps the app's own value", (WidgetTester tester) async {
    phrase.text = '3';
    await pumpForm(tester);
    dvCarrySsrFields(const <DVSsrField>[
      DVSsrField(name: 'Phrase length (words)', value: '1'),
    ]);
    await tester.pump();
    expect(phrase.text, '3');
    expect(typed, isEmpty);
  });

  testWidgets('names that do not match, on pages with the same fields, match by order',
      (WidgetTester tester) async {
    await pumpForm(tester);
    final DVSsrFieldCarry carry = dvCarrySsrFields(const <DVSsrField>[
      DVSsrField(name: 'Text', value: 'first', edited: true),
      DVSsrField(name: 'Number', value: '4', edited: true),
    ]);
    await tester.pump();
    expect(content.text, 'first');
    expect(phrase.text, '4');
    expect(carry.matched, 2);
  });

  testWidgets('a name that does not match is never guessed when the fields differ',
      (WidgetTester tester) async {
    await pumpForm(tester);
    final DVSsrFieldCarry carry = dvCarrySsrFields(const <DVSsrField>[
      DVSsrField(name: 'Somewhere else', value: 'lost?', edited: true),
    ]);
    await tester.pump();
    expect(content.text, '');
    expect(phrase.text, '1');
    expect(carry.matched, 0);
  });

  testWidgets('a hint after the name is still the name', (WidgetTester tester) async {
    await pumpForm(tester);
    final DVSsrFieldCarry carry = dvCarrySsrFields(const <DVSsrField>[
      // Flutter names a field by its label and its hint on the web.
      DVSsrField(name: 'Your content\nPaste your page', value: 'typed', edited: true),
    ]);
    await tester.pump();
    expect(content.text, 'typed');
    expect(carry.matched, 1);
  });
}
