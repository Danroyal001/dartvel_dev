# dartvel_flutter

The Flutter runtime of [Dartvel](https://dartvel.dev): everything a Dartvel
application runs on the device, in the browser and on the desktop.

- `DVBox` and `DVText`, styled through Dartvel's own `DVModifier` chain.
- Signals: `context.signal(...)`, signals derived with operators, reactive data
  models and `DV.global`.
- The runtime behind file-based pages and typed routes: the page shell,
  `DVNavLink`, `DV.Navigation`, layouts, loading and error pages.
- The widgets generated data models use: forms, tables and model pages.
- `DV.Platform`, the device API surface, reached through `dart:ffi`, jnigen
  and `dart:js_interop` rather than platform channels.
- On the web: head tags and structured data per page, path URLs, and the
  install prompt of the generated PWA.
- Dartvel Studio's page builder and admin sections, which a web-server build
  serves.

Dartvel is alpha. Each part of it is labelled in
[`docs/spec-status.json`](https://github.com/Danroyal001/dartvel_dev/blob/main/docs/spec-status.json)
as `Shipped`, `Partial` or `Designed`, and a check in the repository fails when a
section claims evidence that does not exist. This page shows `Shipped`
surfaces as ready to use and says so where one is `Partial`.

## How it is used

Most of this package is meant to be reached through code that Dartvel
generates. A Dartvel project is made with `dartvel create`. You write pages,
data models and backend functions as private annotated declarations, and the
CLI writes `lib/dartvel_client/` from them: the router, one typed target per
page on `DVRoutes`, the public model classes and their forms, and the client
for each backend function. Application code imports that one barrel, which
re-exports this package:

```dart
import '../dartvel_client/dartvel_client.dart';
```

Generation runs by itself before `dartvel dev` and `dartvel build`, so you
rarely call it by name. The generated directory is not committed; a fresh
clone generates it on its first build.

Part of the package needs no generated code, and works in any Flutter app:

| Works on its own | Needs the generator |
|---|---|
| `DVBox`, `DVText`, `DVModifier` | Pages (`@DVPage`) and the router |
| `context.signal`, `signal(context, v)`, derived signals | `DVRoutes`, and so `DVNavLink` and `DV.Navigation` |
| `DV.global`, `context.global` | Data models: `User`, `User.Form()`, `User.Table(...)`, `User.Page` |
| | Native bindings, which the generated app registers at startup |
| | SEO, sitemap and PWA files, written by `dartvel build web` |

Routing is on the right on purpose. A route written as a string drifts the
moment its page moves, and the generated targets turn that into a compile
error. Without the generator there are no targets to use.

## Install

For a Dartvel application, install the CLI and let it write the project:

```sh
dart pub global activate dartvel_cli
dartvel create --name shop
cd shop && dartvel dev
```

The project it writes already depends on `dartvel_flutter`, `dartvel_core`
and `dartvel_shelf`. To use only the parts that need no generator in an
existing Flutter app:

```sh
flutter pub add dartvel_flutter
```

```dart
import 'package:dartvel_flutter/dartvel_flutter.dart';
```

Every Dartvel package declares the same floor: Dart 3.12 and Flutter 3.44.
`dartvel init` adds Dartvel to an existing Flutter project instead of making
a new one, and `dartvel init --dry-run` shows what it would change first.

## A small app

This is a generated project with two pages. `lib/main.dart` is what
`dartvel create` writes:

```dart
import 'package:flutter/material.dart';
import 'dartvel_client/dartvel_client.dart';

void main(List<String> arguments) async {
  await negotiateDartvelLaunch(arguments);
  runApp(createDartvelApp(arguments: arguments));
}

Widget createDartvelApp({List<String> arguments = const <String>[]}) {
  return MaterialApp.router(
    title: 'Shop',
    routerConfig: createDartvelRouter(arguments: arguments),
  );
}
```

`lib/pages/index.dart` is served at `/`:

```dart
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Shop', description: 'House espresso, roasted this week.')
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) {
  final DVSignal<int> quantity = context.signal(1);
  final DVSignal<int> unitPrice = context.signal(1450);
  final total = unitPrice * quantity;

  return DVBox.list(<Widget>[
    const DVText('House espresso').modifier(
      DVModifier().fontSize(28).fontWeight(FontWeight.w700).semanticHeading(1),
    ),
    DVText('${quantity.value} bags, EUR ${(total.value / 100).toStringAsFixed(2)}'),
    const DVText('Add one').modifier(
      DVModifier()
          .paddingSymmetric(horizontal: 16, vertical: 10)
          .rounded(8)
          .semanticButton()
          .onTap(() => quantity.value = quantity.value + 1),
    ),
    DVNavLink(to: DVRoutes.about, child: const DVText('About the roastery')),
  ]).modifier(const DVModifier().padding(24));
}
```

`lib/pages/about.dart` is served at `/about`, and generating it is what puts
`DVRoutes.about` on the index page:

```dart
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'About')
@pragma('vm:entry-point')
Widget _aboutPage(BuildContext context) => const DVBox.list(<Widget>[
      DVText('We roast on Tuesdays.'),
    ]);
```

Two rules the generator enforces. The annotated function is private
(`_aboutPage`, not `aboutPage`), because Dartvel generates the public API from
it and a public annotated input is an error. And a page does not build its own
`Scaffold`: `@DVPage` owns the page shell, so `title`, `showAppBar` and the
rest go on the annotation.

`example/` in this package is a runnable app that uses only the parts that
need no generator.

## UI: DVBox, DVText and the modifier chain

`DVBox` is the one layout primitive and `DVText` the one text primitive. Both
take a `DVModifier`, an immutable chain of styling, layout, interaction and
semantics. The chain is Dartvel's own, rendered with Flutter widgets; it is
not built on `mix`.

```dart
Widget card() => DVBox(
      const DVText('One child, with padding and a border'),
      const DVModifier()
          .padding(16)
          .backgroundColor(Color(0xFFF4F6FB))
          .border(Border.fromBorderSide(BorderSide(color: Color(0xFFE3E7EF))))
          .rounded(12),
    );
```

`DVBox(child)` is for one child. A collection uses a named constructor, so the
layout is said once, where the children are:

```dart
Widget layouts(BuildContext context) => DVBox.list(<Widget>[
      const DVBox.row(<Widget>[
        DVText('Left'),
        DVText('Right'),
      ], align: DVAlign.spaceBetween),
      const DVBox.wrapLine(<Widget>[
        DVText('Dart'),
        DVText('Flutter'),
        DVText('Web'),
      ], spacing: 12),
      // Up to four columns, fewer on narrow screens.
      DVBox.grid(<Widget>[
        for (int i = 1; i <= 8; i++) DVText('Item $i'),
      ], columns: context.screen.value<int>(mobile: 1, tablet: 2, desktop: 4)),
    ], spacing: 24);
```

The others are `DVBox.scrollableList`, `DVBox.horizontalScrollable`,
`DVBox.stack`, `DVBox.masonry` and `DVBox.twoPane`, which splits across a
foldable's hinge and stacks on a phone. `DVBox.image`, `DVBox.video` and
`DVBox.audio` are boxes whose content is media.

Interaction and semantics are on the same chain, so a tappable label is a
`DVText` rather than a button widget wrapped round one:

```dart
Widget saveButton(VoidCallback onSave) => DVText('Save').modifier(
      const DVModifier()
          .paddingSymmetric(horizontal: 20, vertical: 12)
          .backgroundColor(Color(0xFF2F6BFF))
          .color(Color(0xFFFFFFFF))
          .rounded(8)
          .animate(Duration(milliseconds: 150))
          .hover(DVModifier().opacity(0.9))
          .minimumTapTarget()
          .semanticButton()
          .onTap(onSave),
    );
```

The Styling section is `Partial`: the chain covers padding, borders, radius,
colour, gradients, type, shadows, opacity, blur, rotation, hover and
animation, and the named design tokens the spec describes are not built yet.

## Signals

A signal is a value a widget reads; reading `.value` in `build` redraws that
widget when the value changes. `context.signal(initial)` creates one for the
widget, and `signal(context, initial)` is the same call as a function.
Signals are matched by call order in `build`, like hooks, so create them
unconditionally.

```dart
final DVSignal<int> quantity = context.signal(1);

quantity.value = 3;                  // set
quantity.update((int n) => n + 1);   // set from the current value
final int now = quantity.read();     // read without subscribing
```

An operator on a signal returns a signal that tracks its sources. There is no
separate computed type:

```dart
final DVSignal<int> price = context.signal(1200);
final DVSignal<int> quantity = context.signal(2);
final DVSignal<bool> agreed = context.signal(false);
final DVSignal<bool> paid = context.signal(false);

final subtotal = price * quantity;   // + - * / ~/ % on numbers
final expensive = subtotal >= 10000; // < <= > >= give a bool signal
final canShip = agreed & paid;       // & | ^ on bools
```

Read `.value` of a derived signal in `build` to redraw with it. `==` and `!`
are not overloaded, so compare `.value` instead.

One object shared across the app is registered with `DV.global`. There is no
separate service container:

```dart
DV.global<Cart>(Cart());                 // register, at startup
final Cart cart = DV.global<Cart>();     // read anywhere; throws if unregistered
final Cart same = context.global<Cart>(); // read, and redraw when it is replaced
```

A generated data model is reactive too: `article.signal(context)` gives a
signal of that record, and `Article.Page.signal(...)` redraws the model's page
from it.

## Pages and routing

A file in `lib/pages/` is a page. `lib/pages/blog/[id].dart` is served at
`/blog/:id`, and its parameters and query are on the context:

```dart
@DVPage(title: 'Blog post')
Widget _blogPostPage(BuildContext context) => DVBox.list(<Widget>[
      DVText('Post ${context.dvParams['id']}'),
      DVText('Sorted by ${context.dvQuery['sort'] ?? 'date'}'),
    ]);
```

Every page is a typed target on the generated `DVRoutes`, and navigation takes
only targets:

```dart
DVNavLink(to: DVRoutes.about, child: const DVText('About us'))

DVText('Open post 7').modifier(
  DVModifier().onTap(DV.Navigation.to(DVRoutes.blog(id: '7'))),
)

// A query is still a typed route: both halves are generated targets.
DV.Navigation.to(
  DVRoutes.signin.withQuery(<String, String>{'from': DVRoutes.account.path}),
)
```

`DV.Navigation.to` returns a callback rather than navigating, so it goes where
a handler is expected. Written as `onTap: () => DV.Navigation.to(target)` it
builds the callback and throws it away; the analyzer flags that through
`@useResult`. `DV.Navigation.navigate`, `push` and `back` act immediately.

`DVNavLink` is a link, not a tap handler. It navigates with its padding as
part of the hit area, is announced to a screen reader as a link carrying its
destination, takes keyboard focus and answers Enter, opens beside the page on
a middle or modifier click, preloads the route's deferred code when it
becomes visible, and shows a preview of the destination on a resting pointer
or a long press. `DVNavLink.external(url, child: ...)` is the same for an
address outside the app.

Beside the pages:

- `_layout.dart` in a folder wraps every page under it, as a class extending
  `DartvelLayout`.
- `about.loading.dart` and `about.error.dart` are shown while `about.dart`'s
  data loads and when it fails.
- `_guard.dart` runs before every page in its folder, and
  `@DVPage(policy: ...)` puts a page behind an authorization policy.

Every page can be reached by keyboard, a TV remote's D-pad and switch control
with nothing added: the page shell carries keyboard scrolling, D-pad focus
and switch scanning, and they stay inert until used. The reader's own choices
live on `DV.Accessibility.switchControl`:

```dart
DV.Accessibility.switchControl.enabled = true;
```

## Data models and forms

A data model is declared once, as a private class, and the generator writes
the public class with its schema, CRUD, validation and serialization. The
annotation comes from `dartvel_core`; the widgets the model gets are built on
this package:

```dart
// lib/models/article.dart
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Article {
  final String slug;
  final String title;
  final bool published;

  const _Article({
    required this.slug,
    required this.title,
    required this.published,
  });
}
```

```dart
Widget newArticleForm() => Article.Form();              // creates a record
Widget editArticleForm(Article a) => a.Form();          // edits this record
Widget articleTable(List<Article> all) => Article.Table(all);
Widget articlePage(Article a) => Article.Page.sync(a);
```

A form takes no save callback. Saving is what the form does, and whether the
reader may create or edit is answered by the model's policy, the same one the
page and the backend function ask.

## Device APIs

`DV.Platform` is one surface on every target. A feature the platform does not
have reports that it is unavailable, and calling a name nothing has bound
throws and names it, rather than returning a plausible default.

```dart
Future<void> shareReceipt(String orderId) async {
  await DV.Haptics.lightVibrate();
  await DV.Share.shareText('Order $orderId is on its way.');
}
```

Connectivity is a signal, so an offline banner is a widget that rebuilds:

```dart
final DVNetworkStatus status = DV.Platform.network.watch(context);
// online, metered, offline or unknown
```

The bindings reach native code through `dart:ffi` (X11, GTK and GDBus on
Linux, the Win32 API, the Objective-C runtime on Apple platforms),
`dart:js_interop` on the web and jnigen on Android. There are no platform
channels. Coverage differs by platform, by design and by progress: a browser
tab has no system tray, and on Android biometrics and NFC need an `Activity`
rather than a `Context`. The Platform section is `Partial`, and its entry in
`docs/spec-status.json` lists what each target binds and why the rest is
absent. The generated app registers the bindings for its target at startup.

## The web: SEO and PWA

A page's `title` and `description` on `@DVPage` become its title, meta
description, Open Graph tags and structured data. `dartvel build web` writes
one prerendered HTML page per route, with those head tags and text a crawler
can read, plus `sitemap.xml` and `robots.txt`. Routes behind a guard are left
out of the sitemap. A page can tune its own entry:

```dart
@DVPage(
  title: 'Pricing',
  sitemap: DVPageSitemap(
    priority: 0.8,
    changeFrequency: DVSitemapChangeFrequency.weekly,
  ),
)
Widget _pricingPage(BuildContext context) => const DVText('Plans');
```

The same build writes the PWA: manifest, icons, service worker and an offline
page. A same-origin request other than a GET that cannot be sent while
offline is queued by the worker and sent in order when the network returns. The install prompt is on `DV.Platform`:

```dart
if (DV.Platform.install.canPrompt) {
  final DVInstallOutcome outcome = await DV.Platform.install.prompt();
}
```

`canPrompt` is false until the browser says the app is installable, and
`prompt()` must run inside a user gesture, because browsers refuse it
otherwise.

URLs are paths rather than Flutter's default `#/` fragments, so a deep link
reaches the page it names.

## Studio

Dartvel Studio is a visual page builder and data editor. It lives in this
package and is served by a web-server build at `/__studio`, to accounts that
have been granted access; it is never compiled into an app:

```yaml
dartvel:
  admin:
    enabled: true
```

```sh
dartvel build web-server
dartvel admin grant <user-id> --database dartvel_data/data.db
```

In a web app served by its own server, a page published from Studio takes
over its route on the next load without a rebuild, and reverting it gives the
route back to the compiled page. A page exported from Studio is ordinary
Dartvel source.

## Platform notes

- **Web.** dartvel.dev is built with this package, and runs as a static
  build.
- **Desktop** (multi-window is `Partial`). `DV.Platform.Window.open(route)`
  never fails: where a real window cannot be created it navigates to the
  route instead and reports why.
  Real OS windows need the separate `dartvel_windowing` package, which is not
  published, because it depends on Flutter's internal windowing API.
- **Terminal** (`Partial`). `dartvel build linux-cli` renders the same app in
  a terminal. It is opt-in at build time, so no other build links terminal
  code.
- **Embedded and TV targets** (Tizen, webOS, Sony eLinux, tvOS) are built
  through each vendor's embedder. Status and evidence per target are in
  [`docs/build-targets.md`](https://github.com/Danroyal001/dartvel_dev/blob/main/docs/build-targets.md);
  some targets have been built and not run, and Fuchsia does not build.

## Links

- [API reference](https://pub.dev/documentation/dartvel_flutter/latest/)
- [Repository](https://github.com/Danroyal001/dartvel_dev)
- [Getting started](https://github.com/Danroyal001/dartvel_dev/blob/main/docs/getting-started.md)
- [NEW_SPEC.md](https://github.com/Danroyal001/dartvel_dev/blob/main/NEW_SPEC.md),
  the design specification. It describes where Dartvel is going; where it and
  the code disagree, the code wins.
- [Implementation status per spec section](https://github.com/Danroyal001/dartvel_dev/blob/main/docs/spec-status.json)
- [dartvel.dev](https://dartvel.dev)

## The name

The framework is Dartvel and the command is `dartvel`. The pub.dev package for
the CLI is `dartvel_dev` because `dartvel` was taken on 2026-08-06 by an
unrelated package.
