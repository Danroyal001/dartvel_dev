// Code blocks that are a terminal session are coloured as one.
//
// Every block went through the Dart scanner, so on the built site the home
// page's terminal output read like code: "on" and "with" in "Scan with the
// camera on a device" took the keyword colour, "in one file" the same, and
// everything after the "//" of "http://0.0.0.0:3000" or "dartvel-dev://pair"
// turned into a grey comment.
import 'package:dartvel_site/components/highlight.dart';
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The colour [word] is painted in, the first time a span contains it.
Color? colourOf(List<TextSpan> spans, String word) {
  for (final TextSpan span in spans) {
    if (span.text != null &&
        RegExp('(^|[^A-Za-z])${RegExp.escape(word)}(\$|[^A-Za-z])')
            .hasMatch(span.text!)) {
      return span.style?.color;
    }
  }
  return null;
}

void main() {
  copyButtonTests();

  final Color keyword =
      colourOf(Code.spans('final int a = 1;'), 'final')!;
  final Color comment = colourOf(Code.spans('a; // note'), 'note')!;

  test('the Dart scanner still colours Dart', () {
    expect(keyword, isNot(colourOf(Code.spans('final int a = 1;'), 'a')));
  });

  test('a terminal session is not coloured as Dart', () {
    const String session = r'''
$ dartvel dev
[dartvel] Scan with the camera on a device running a development build:
dartvel backend listening on http://0.0.0.0:3000/api
# the QR code prints here''';
    final List<TextSpan> spans = Code.spans(session);
    expect(colourOf(spans, 'with'), isNot(keyword));
    expect(colourOf(spans, 'on'), isNot(keyword));
    expect(colourOf(spans, 'api'), isNot(comment),
        reason: 'the // of a URL is not a comment in a terminal');
    // Its own comments and prompts are still told apart from output.
    expect(colourOf(spans, 'QR'), comment);
    expect(colourOf(spans, 'dev'), isNot(colourOf(spans, 'backend')));
  });

  test('commands with no prompt are a session too', () {
    const String commands = '''
brew install Danroyal001/dartvel_dev/dartvel_dev
dartvel create shop
cd shop && dartvel dev''';
    final List<TextSpan> spans = Code.spans(commands);
    expect(colourOf(spans, 'Danroyal001'),
        isNot(colourOf(Code.spans('Post post;'), 'Post')));
  });
}

// The Copy button sat over the first line of every code block on a phone:
// the block stacks the button on the text, and a line long enough to reach
// the right edge ran underneath it ("true)" in the model sample, "--profile"
// and "await" in others). The text and the button must not share pixels at
// any width.
void copyButtonTests() {
  for (final double width in <double>[390, 1440]) {
    testWidgets('the Copy button covers no code at $width pixels',
        (WidgetTester tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 22),
              child: CodeBlock(<String>[
                '@DVModel(generatePublicPages: true) and a line long enough '
                    'to reach the right edge of any block on any screen',
                'class _Post {}',
              ]),
            ),
          ),
        ),
      ));
      await tester.pump();
      final Rect text = tester.getRect(find.byType(SelectableText));
      final Rect button = tester.getRect(find.byType(CopyButton));
      expect(text.overlaps(button), isFalse,
          reason: 'text $text, button $button');
    });
  }
}
