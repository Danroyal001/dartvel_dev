import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';

// docs:start ui-text
const Widget greeting = DVText('Welcome back');
// docs:end

Widget styledText() =>
    // docs:start ui-text-style
    DVText('Pricing').fontSize(28).fontWeight(.w700).color(const Color(0xFF0B1020)).semanticHeading(1);
// docs:end

// docs:start ui-box
Widget card() => DVBox(DVText('One child, with padding and a border'))
    .padding(16)
    .backgroundColor(const Color(0xFFF4F6FB))
    .border(const Border.fromBorderSide(BorderSide(color: Color(0xFFE3E7EF))))
    .rounded(12);
// docs:end

// docs:start ui-layouts
Widget layouts() => DVBox.list(<Widget>[
      // A column. Children are 8 apart unless you set spacing.
      const DVBox.row(<Widget>[
        DVText('Left'),
        DVText('Right'),
      ], align: .spaceBetween),
      // A line of children that wraps onto the next line when full.
      const DVBox.wrapLine(<Widget>[
        DVText('Dart'),
        DVText('Flutter'),
        DVText('Web'),
      ], spacing: 12),
      // Up to three columns, fewer on narrow screens.
      DVBox.grid(<Widget>[
        for (int i = 1; i <= 6; i++) DVText('Item $i'),
      ], columns: 3),
    ], spacing: 24);
// docs:end

// docs:start ui-shared-style
// A style used in more than one place, kept once.
final DVModifier pill = const DVModifier().paddingSymmetric(horizontal: 16, vertical: 8).rounded(20);

Widget tags() => DVBox.row(<Widget>[
      DVText('Dart').modifier(pill).backgroundColor(const Color(0xFFE8F0FE)),
      DVText('Flutter').modifier(pill).backgroundColor(const Color(0xFFE6F4EA)),
    ]);
// docs:end

// docs:start ui-interaction
Widget saveButton(VoidCallback onSave) => DVText('Save')
    .paddingSymmetric(horizontal: 20, vertical: 12)
    .backgroundColor(const Color(0xFF2F6BFF))
    .color(const Color(0xFFFFFFFF))
    .rounded(8)
    .animate(const Duration(milliseconds: 150))
    .hover(const DVModifier().opacity(0.9))
    .semanticButton()
    .onTap(onSave);
// docs:end

// docs:start ui-responsive
Widget productGrid(BuildContext context, List<Widget> products) => DVBox.grid(
      products,
      columns: context.screen.value<int>(mobile: 1, tablet: 2, desktop: 4),
      spacing: context.screen.isMobile ? 12 : 24,
    );
// docs:end

// docs:start ui-functional-widget
// lib/components/price_tag.dart
@DVFunctionalWidget()
Widget _priceTag(BuildContext context, int cents, {String currency = 'USD'}) =>
    DVText('$currency ${(cents / 100).toStringAsFixed(2)}').fontWeight(.w600);

// Used anywhere as a widget: PriceTag(2499, currency: 'EUR')
// docs:end

// docs:start ui-theme
void useDarkMode() => DV.Theme.setMode(.dark);
// docs:end

enum ReadingSize { standard, large, larger }

// docs:start ui-choice
Widget readingSize(ReadingSize size, ValueChanged<ReadingSize> choose) => DVChoice<ReadingSize>(
      options: ReadingSize.values,
      selected: size,
      name: (ReadingSize size) => switch (size) {
        .standard => 'Default',
        .large => 'Large',
        .larger => 'Larger',
      },
      label: 'Text size',
      onChanged: choose,
    ).paddingOnly(top: 8);

// A longer list reads better as a menu.
Widget country(String chosen, ValueChanged<String> choose) => DVChoice<String>(
      options: const <String>['Ghana', 'Kenya', 'Nigeria', 'South Africa', 'Uganda'],
      selected: chosen,
      name: (String country) => country,
      label: 'Country',
      style: .menu,
      onChanged: choose,
    );
// docs:end

// docs:start ui-switch
Widget highContrast(bool on, ValueChanged<bool> turn) => DVSwitch(
      label: 'High contrast',
      explanation: 'Pure black and white with strong outlines.',
      value: on,
      onChanged: turn,
    );
// docs:end
