# dartvel_flutter example

Two ways in. A Dartvel application is normally made by the `dartvel` CLI,
because pages, typed routes and data models come from its code generator.
The app in this folder is the other way: the parts of `dartvel_flutter` that
need no generated code, in a plain Flutter app.

## A generated project

```sh
dart pub global activate dartvel_dev
dartvel create --name shop
cd shop
```

Add a page at `lib/pages/about.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'About')
@pragma('vm:entry-point')
Widget _aboutPage(BuildContext context) => const DVBox.list(<Widget>[
      DVText('We roast on Tuesdays.'),
    ]);
```

Link to it from `lib/pages/index.dart`. The target is generated from the
file, so moving the page is a compile error here rather than a dead link:

```dart
DVNavLink(to: DVRoutes.about, child: const DVText('About the roastery'))
```

Then run it:

```sh
dartvel dev
```

`dartvel dev` and `dartvel build` generate `lib/dartvel_client/` before they
start: the router, `DVRoutes`, and the barrel every page imports.

## Without the generator

[`lib/main.dart`](lib/main.dart) is an order panel built from `DVBox`,
`DVText` and the `DVModifier` chain. The quantity and the terms checkbox are
signals made with `context.signal`, the total and "ready to order" are
signals derived with `*`, `>` and `&`, and the shop's name comes from
`DV.global`.

```sh
flutter pub get
flutter run
flutter test
```

The test taps the buttons and checks that the derived total and the order
state follow.
