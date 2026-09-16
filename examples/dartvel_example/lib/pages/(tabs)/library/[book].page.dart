import 'package:flutter/widgets.dart';

import '../../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Book', showAppBar: true)
@pragma('vm:entry-point')
Widget _libraryBookPage(BuildContext context) => DVBox.list([
      DVText('Reading ${context.dvParams['book']}')
          .modifier(const DVModifier().fontSize(24.0).semanticHeading(1)),
      const DVText('Pushed over the library, inside the Library tab.'),
    ], spacing: 12)
        .modifier(const DVModifier().padding(24));
