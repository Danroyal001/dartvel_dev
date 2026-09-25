// Prose that can name a command.
//
// A sentence that says "run dartvel db migrate" in the same face as the words
// around it reads as "run dartvel, db migrate" to anyone who does not already
// know the CLI, and nothing marks where the command ends. So copy puts a
// command between backticks, the way every README does, and this draws the
// backticked part as code: monospaced, on a tint, with the backticks gone.
//
// Text with no backticks is a plain DVText with the same modifier, so a
// paragraph that names no command renders exactly as it did before.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import 'site.dart';

/// [text] styled by [style], with each `backticked` run drawn as code.
///
/// The screen reader, the crawler-visible block and the browser's find all
/// read the semantics tree, and a rich text's label is its spans joined, so
/// they get the words without the backticks.
@DVFunctionalWidget()
Widget _prose(
  BuildContext context,
  String text,
  DVModifier style, {
  bool onDark = false,
}) {
  if (!text.contains('`')) return DVText(text).modifier(style);
  final Palette palette = Palette.of(context);
  final TextStyle base = TextStyle(
    color: style.textColor,
    fontSize: style.fontSizeValue,
    fontWeight: style.fontWeightValue,
    letterSpacing: style.letterSpacingValue,
    fontFamily: style.fontFamilyValue,
    height: style.lineHeightValue,
  );
  final TextStyle code = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontFamilyFallback: const <String>['Menlo', 'Consolas', 'monospace'],
    // A monospaced face sets larger than the sans beside it at the same size,
    // so code takes the step below on the type scale.
    fontSize: kTypeScale.lastWhere(
      (double step) => step < (style.fontSizeValue ?? 17),
      orElse: () => kTypeScale.first,
    ),
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    color: onDark ? Palette.deepInk : palette.ink,
    backgroundColor: (onDark ? Palette.deepAccent : palette.accent)
        .withValues(alpha: onDark ? 0.18 : 0.10),
  );
  final List<String> parts = text.split('`');
  return DVBox(
    Text.rich(
      TextSpan(children: <InlineSpan>[
        for (int i = 0; i < parts.length; i++)
          if (parts[i].isNotEmpty)
            // Odd parts are inside a pair of backticks. An unpaired one
            // leaves the rest as code, which a test on the copy prevents.
            TextSpan(text: parts[i], style: i.isOdd ? code : null),
      ]),
      style: base,
      maxLines: style.maxLinesValue,
      overflow: style.maxLinesValue == null
          ? style.overflowValue
          : style.overflowValue ?? TextOverflow.ellipsis,
    ),
  ).modifier(style);
}
