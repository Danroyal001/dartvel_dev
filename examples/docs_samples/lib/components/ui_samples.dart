import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';

// docs:start ui-text
const Widget greeting = DVText('Welcome back');
// docs:end

Widget styledText() =>
    // docs:start ui-text-style
    const DVText('Pricing').modifier(
      DVModifier()
          .fontSize(28)
          .fontWeight(FontWeight.w700)
          .color(Color(0xFF0B1020))
          .semanticHeading(1),
    );
// docs:end

// docs:start ui-box
Widget card() => DVBox(
      DVText('One child, with padding and a border'),
      DVModifier()
          .padding(16)
          .backgroundColor(Color(0xFFF4F6FB))
          .border(Border.fromBorderSide(BorderSide(color: Color(0xFFE3E7EF))))
          .rounded(12),
    );
// docs:end

// docs:start ui-layouts
Widget layouts() => DVBox.list(<Widget>[
      // A column. Children are 8 apart unless you set spacing.
      const DVBox.row(<Widget>[
        DVText('Left'),
        DVText('Right'),
      ], align: DVAlign.spaceBetween),
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

// docs:start ui-interaction
Widget saveButton(VoidCallback onSave) => DVText('Save').modifier(
      DVModifier()
          .paddingSymmetric(horizontal: 20, vertical: 12)
          .backgroundColor(const Color(0xFF2F6BFF))
          .color(const Color(0xFFFFFFFF))
          .rounded(8)
          .animate(const Duration(milliseconds: 150))
          .hover(const DVModifier().opacity(0.9))
          .semanticButton()
          .onTap(onSave),
    );
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
    DVText('$currency ${(cents / 100).toStringAsFixed(2)}').modifier(
      const DVModifier().fontWeight(FontWeight.w600),
    );

// Used anywhere as a widget: PriceTag(2499, currency: 'EUR')
// docs:end

// docs:start ui-theme
void useDarkMode() => DV.Theme.setMode(ThemeMode.dark);
// docs:end
