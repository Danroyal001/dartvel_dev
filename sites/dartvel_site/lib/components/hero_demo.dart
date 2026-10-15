// The hero's demo: Dartvel code, and that same code running beside it.
//
// A hero that describes a framework is a screenshot with a caption. This one
// is three signals on the page itself -- a quantity, a total derived from it
// and a flag derived from the total -- so a visitor presses + and watches the
// derived values follow, with nothing else written to make them. The lines
// printed above the running card are checked against the body below by
// test/home_alive_test.dart, so the two cannot say different things.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import 'site.dart';

/// What the demo prints, line for line out of [_heroDemo].
const List<String> kHeroDemoSource = <String>[
  '// Math on a signal gives a signal.',
  'final quantity = context.signal(1);',
  'final total = quantity * 12;',
  'final free = total > 50;',
  '',
  r"DVText('\$${total.value}')",
  "if (free.value) const DVText('Free delivery')",
];

@DVFunctionalWidget()
Widget _heroDemo(BuildContext context) {
  final Palette palette = Palette.of(context);
  final quantity = context.signal(1);
  final total = quantity * 12;
  final free = total > 50;

  return DVBox(
    DVBox.list(<Widget>[
      const CodeSample(kHeroDemoSource),
      DVBox.list(<Widget>[
        DVBox.row(<Widget>[
          DVBox(
            const DVBox(),
            const DVModifier()
                .width(8)
                .height(8)
                .rounded(999)
                .backgroundColor(const Color(0xFF22C55E)),
          ),
          const DVText('RUNNING ON THIS PAGE').modifier(const DVModifier()
              .fontSize(12)
              .fontWeight(.w700)
              .letterSpacing(1.2)
              .color(palette.muted)),
        ], spacing: 8, align: .start),
        DVBox.wrapLine(<Widget>[
          DVBox.row(<Widget>[
            StepButton('−', 'Remove one',
                () => quantity.update((int n) => n > 1 ? n - 1 : n)),
            DVText('${quantity.value}').modifier(const DVModifier()
                .fontSize(20)
                .fontWeight(.w700)
                .color(palette.ink)),
            StepButton('+', 'Add one', () => quantity.update((int n) => n + 1)),
          ], spacing: 12, align: .start),
          const DVText('× \$12  =').modifier(
              const DVModifier().fontSize(17).color(palette.muted)),
          DVText('\$${total.value}').modifier(const DVModifier()
              .fontSize(30)
              .fontWeight(.w700)
              .color(palette.accent)),
          if (free.value) const DVText('Free delivery').modifier(const DVModifier()
                .fontSize(13)
                .fontWeight(.w700)
                .color(palette.ink)
                .paddingSymmetric(horizontal: 10, vertical: 4)
                .backgroundColor(const Color(0x5522C55E))
                .rounded(999)),
        ], spacing: 14, crossAlign: .center),
        const DVText('Press + past four: the total and the badge follow, and '
                'nothing else on this page was written to make them.')
            .modifier(const DVModifier()
                .fontSize(13)
                .color(palette.muted)
                .lineHeight(1.5)),
      ], spacing: 14),
    ], spacing: 14),
    const DVModifier()
        .padding(14)
        .backgroundColor(palette.page.withValues(alpha: 0.86))
        .border(Border.all(color: palette.rule))
        .rounded(14)
        .shadow(<BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: palette.dark ? 0.45 : 0.10),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ])
        .hoverGlow(
            color: palette.accent.withValues(alpha: palette.dark ? 0.18 : 0.12),
            radius: 320),
  );
}

/// A square step button with its name on hover, focus and long press.
@DVFunctionalWidget()
Widget _stepButton(
  BuildContext context,
  String glyph,
  String name,
  VoidCallback onPressed,
) {
  final Palette palette = Palette.of(context);
  return DVBox(
    DVText(glyph).modifier(const DVModifier()
        .fontSize(20)
        .fontWeight(.w700)
        .color(palette.ink)),
    const DVModifier()
        .width(40)
        .height(40)
        .align(Alignment.center)
        .backgroundColor(palette.surface)
        .border(Border.all(color: palette.rule))
        .rounded(10)
        .animate(const Duration(milliseconds: 140))
        .hover(const DVModifier().border(Border.all(color: palette.accent)))
        .tooltip(name)
        .semanticLabel(name)
        .minimumTapTarget()
        .onTap(onPressed),
  );
}
