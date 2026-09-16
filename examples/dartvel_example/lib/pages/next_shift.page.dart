// The page that shows the class-shaped home widget.
//
// NextShiftWidget is a @DVHomeWidget written as a class rather than a
// function, and a class is already a widget, so nothing is generated from it
// and nothing in the application named it. That made the file evidence for a
// section while being callable by nothing -- which the evidence check refuses,
// correctly: a file no code reaches is a file no build exercises beyond the
// scan that found the annotation.
//
// A page renders it now, so the class is constructed, laid out and covered by
// the same page tests every other route gets.
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

import '../components/shop_ui.dart';
import '../theme/palette.dart';
import '../widgets/next_shift.dart';

@DVPage(title: 'Next shift', showAppBar: true)
@pragma('vm:entry-point')
Widget _nextShiftPage(BuildContext context) => ShopScroll(children: <Widget>[
      const PageHeading(
        'Home screen widget',
        subtitle: 'The roasters see their next shift on their home screen. '
            'The same widget, drawn in the app:',
      ),
      const DVBox(NextShiftWidget())
          .modifier(cardStyle(Palette.of(context), padding: 20).maxWidth(320)),
    ]);
