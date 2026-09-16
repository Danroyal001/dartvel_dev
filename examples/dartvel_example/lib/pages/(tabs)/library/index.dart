import 'package:flutter/widgets.dart';

import '../../../dartvel_client/dartvel_client.dart';

const List<String> libraryBooks = <String>['dune', 'emma', 'ulysses'];

@DVPage(title: 'Library')
@pragma('vm:entry-point')
Widget _libraryPage(BuildContext context) => DVBox.list([
      const DVText('Library')
          .modifier(const DVModifier().fontSize(24.0).semanticHeading(1)),
      for (final String book in libraryBooks)
        DVNavLink(
          key: Key('link-book-$book'),
          to: DVRoutes.libraryBook(book: book),
          child: DVText('Book $book'),
        ),
    ], spacing: 12)
        .modifier(const DVModifier().padding(24));
