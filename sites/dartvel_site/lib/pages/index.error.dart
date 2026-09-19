import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';

/// What the home page shows when its data does not load.
@DVFunctionalWidget()
Widget _indexPageError(BuildContext context) => DVBox.list(<Widget>[
      const DVText('Something went wrong').modifier(
        const DVModifier().fontSize(24).fontWeight(FontWeight.w800),
      ),
      const DVText('The page could not load its data.'),
      const DVText('Go back').modifier(
        const DVModifier()
            .padding(12)
            .rounded(8)
            .backgroundColor(Colors.black)
            .color(Colors.white)
            .onPressed(() => Navigator.of(context).pop()),
      ),
    ]).modifier(
      const DVModifier().align(Alignment.center),
    );
