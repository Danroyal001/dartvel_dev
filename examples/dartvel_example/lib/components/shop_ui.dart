// The pieces every screen of the shop is built from.
//
// Styled with DVBox, DVText and DVModifier, and coloured from the palette so
// light and dark come out of the same code.
import 'dart:async';

import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import '../shop/catalog.dart';
import '../shop/orders.dart';
import '../theme/palette.dart';

export '../shop/catalog.dart' show formatPrice;

/// Content narrower than this reads as a column rather than a line.
const double contentMaxWidth = 1080;

/// The width a single column of rows is capped at.
const double readingMaxWidth = 720;

/// Where the phone layout ends.
const double wideLayoutFrom = 600;

/// A screen's scrolling body: centred, capped, and padded for the device.
///
/// The scroll view is the full width of the screen and the content is capped
/// inside it, so a wheel or a trackpad scrolls from anywhere on a desktop.
class const ShopScroll({
  super.key,
  required final List<Widget> children,
  final double spacing = 28,

  /// A single column of rows reads badly at full width: an account, an
  /// order and a bag cap narrower than a grid does.
  final double maxWidth = contentMaxWidth,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final double side = width < 600 ? 16 : 32;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(side, width < 600 ? 12 : 32, side, 40),
      child: Center(
        child: DVBox.list(
          children,
          spacing: spacing,
        ).modifier(const DVModifier().maxWidth(maxWidth)),
      ),
    );
  }
}

/// The page's name, as its level-1 heading, with an optional line under it.
class const PageHeading(
  final String title, {
  super.key,
  final String? subtitle,
  final String? overline,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    return DVBox.list([
      if (overline != null)
        DVText(overline!.toUpperCase()).modifier(p.overline),
      DVText(title).modifier(p.display.semanticHeading(1)),
      if (subtitle != null)
        DVText(subtitle!).modifier(p.muted.fontSize(16).maxWidth(620)),
    ], spacing: 8);
  }
}

/// A section's name, with an action on the right.
class const SectionHeading(
  final String title, {
  super.key,
  final Widget? action,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    return DVBox.row([
      Expanded(child: DVText(title).modifier(p.title.semanticHeading(2))),
      if (action != null) action!,
    ]);
  }
}

/// The colour of a coffee's bag. Each origin has one, the way a roaster's
/// shelf does.
Color bagColorFor(String slug, Brightness brightness) {
  const Map<String, Color> colors = <String, Color>{
    'huila': Color(0xFFC98B4E),
    'yirgacheffe': Color(0xFFD7B35A),
    'nyeri': Color(0xFFB0564A),
    'harbour-blend': Color(0xFF5C6F7B),
    'huehuetenango': Color(0xFF7D8B5E),
    'night-shift-decaf': Color(0xFF6E6A86),
  };
  const List<Color> others = <Color>[
    Color(0xFF8C6A4F),
    Color(0xFF6F8577),
    Color(0xFFA7775C),
  ];
  final Color base =
      colors[slug] ??
      others[slug.codeUnits.fold(0, (int a, int b) => a + b) % others.length];
  return brightness == Brightness.dark
      ? Color.lerp(base, const Color(0xFF000000), 0.28)!
      : base;
}

int roastLevel(String roast) => switch (roast) {
  'light' => 1,
  'medium' => 2,
  'dark' => 3,
  _ => 2,
};

/// Three dots, filled to the roast.
class const RoastDots(final String roast, {super.key, final Color? color})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Color ink = color ?? Palette.of(context).ink;
    final int level = roastLevel(roast);
    return Semantics(
      label: '$roast roast',
      excludeSemantics: true,
      child: DVBox.row([
        for (int i = 1; i <= 3; i++)
          const DVBox(null).modifier(
            const DVModifier()
                .width(7)
                .height(7)
                .rounded(4)
                .backgroundColor(
                  i <= level ? ink : ink.withValues(alpha: 0.28),
                ),
          ),
      ], spacing: 4),
    );
  }
}

/// A coffee drawn as its bag: the origin, the name, the roast.
class const BagArt(
  final Product coffee, {
  super.key,
  final double height = 150,
  final bool large = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    const Color label = Color(0xFFFFFBF6);
    return ExcludeSemantics(
      child:
          DVBox.stack([
            // The label on the bag.
            Positioned(
              left: large ? 28 : 16,
              right: large ? 28 : 16,
              bottom: large ? 28 : 16,
              child: DVBox.list([
                DVText(
                  coffee.origin.split(',').last.trim().toUpperCase(),
                ).modifier(
                  const DVModifier()
                      .fontSize(large ? 12 : 10)
                      .fontWeight(FontWeight.w700)
                      .letterSpacing(1.4)
                      .color(label.withValues(alpha: 0.82)),
                ),
                DVText(coffee.name).modifier(
                  const DVModifier()
                      .fontSize(large ? 34 : 19)
                      .fontWeight(FontWeight.w700)
                      .letterSpacing(-0.4)
                      .lineHeight(1.1)
                      .maxLines(2)
                      .color(label),
                ),
                RoastDots(coffee.roast, color: label),
              ], spacing: large ? 10 : 6),
            ),
            // The fold at the top of the bag.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: const DVBox(null).modifier(
                const DVModifier()
                    .height(large ? 22 : 14)
                    .backgroundColor(const Color(0x1F000000)),
              ),
            ),
          ]).modifier(
            const DVModifier()
                .height(height)
                .rounded(large ? 20 : 14)
                .backgroundColor(bagColorFor(coffee.slug, brightness)),
          ),
    );
  }
}

/// A surface with a hairline border, the one card style the shop uses.
DVModifier cardStyle(Palette p, {double padding = 16}) => const DVModifier()
    .padding(padding)
    .rounded(18)
    .backgroundColor(p.surface)
    .border(Border.all(color: p.line));

/// A coffee in the grid.
class const CoffeeCard(
  final Product coffee, {
  super.key,
  required final VoidCallback onOpen,
  required final VoidCallback onAdd,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: Key('coffee-${coffee.slug}'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: DVBox.list([
          BagArt(coffee),
          DVBox.list([
            DVText(coffee.name).modifier(p.headline.maxLines(1)),
            DVText(coffee.notes).modifier(p.muted.fontSize(13).maxLines(1)),
          ], spacing: 2).modifier(
            const DVModifier().paddingSymmetric(horizontal: 4),
          ),
          DVBox.row([
            Expanded(
              child: DVText(
                formatPrice(coffee.priceCents),
              ).modifier(p.headline.fontSize(15)),
            ),
            IconButton.filledTonal(
              key: Key('add-${coffee.slug}'),
              tooltip: 'Add ${coffee.name} to bag',
              onPressed: onAdd,
              style: IconButton.styleFrom(
                backgroundColor: p.accentSoft,
                foregroundColor: p.accent,
              ),
              icon: const Icon(Icons.add, size: 20),
            ),
          ]).modifier(const DVModifier().paddingOnly(left: 4)),
        ], spacing: 10).modifier(cardStyle(p, padding: 10)),
      ),
    );
  }
}

/// [children] in as many columns as fit, each at least [minTileWidth].
class const ResponsiveGrid({
  super.key,
  required final List<Widget> children,
  final double minTileWidth = 170,
  final int maxColumns = 4,
  final double spacing = 16,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final double width = constraints.maxWidth;
      final int columns = ((width + spacing) / (minTileWidth + spacing))
          .floor()
          .clamp(1, maxColumns);
      final double tile = (width - spacing * (columns - 1)) / columns;
      return DVBox.wrapLine([
        for (final Widget child in children)
          SizedBox(width: tile.floorToDouble(), child: child),
      ], spacing: spacing);
    },
  );
}

/// Something is on its way: the shape of the content, without the content.
class const LoadingTiles({super.key, final int count = 4})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    return Semantics(
      label: 'Loading',
      child: ResponsiveGrid(
        children: [
          for (int i = 0; i < count; i++)
            DVBox.list([
              const DVBox(null).modifier(
                const DVModifier()
                    .height(150)
                    .rounded(14)
                    .backgroundColor(p.sunken),
              ),
              const DVBox(null).modifier(
                const DVModifier()
                    .height(14)
                    .maxWidth(120)
                    .rounded(7)
                    .backgroundColor(p.sunken),
              ),
              const DVBox(null).modifier(
                const DVModifier()
                    .height(12)
                    .maxWidth(80)
                    .rounded(6)
                    .backgroundColor(p.sunken),
              ),
            ], spacing: 10).modifier(cardStyle(p, padding: 10)),
        ],
      ),
    );
  }
}

/// Nothing here yet, said plainly, with the thing to do about it.
class const EmptyState({
  super.key,
  required final IconData icon,
  required final String title,
  required final String message,
  final Widget? action,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    return DVBox.list(
      [
        DVBox(Icon(icon, size: 28, color: p.accent)).modifier(
          const DVModifier()
              .width(64)
              .height(64)
              .rounded(32)
              .backgroundColor(p.accentSoft)
              .align(Alignment.center),
        ),
        DVText(title).modifier(p.title.semanticHeading(2)),
        DVText(message).modifier(p.muted.maxWidth(360)),
        if (action != null) action!,
      ],
      spacing: 12,
      crossAlign: DVCrossAlign.center,
    ).modifier(cardStyle(p, padding: 36));
  }
}

/// Minus, the number, plus.
class const QuantityStepper({
  super.key,
  required final int value,
  required final ValueChanged<int> onChanged,
  final int min = 1,
  final String label = 'Quantity',
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    return DVBox.row(
      [
        IconButton(
          key: const Key('quantity-decrease'),
          tooltip: 'Fewer',
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove, size: 18),
        ),
        Semantics(
          label: '$label $value',
          excludeSemantics: true,
          child: DVText('$value').modifier(p.headline.minWidth(24)),
        ),
        IconButton(
          key: const Key('quantity-increase'),
          tooltip: 'More',
          onPressed: () => onChanged(value + 1),
          icon: const Icon(Icons.add, size: 18),
        ),
      ],
      spacing: 2,
      crossAlign: DVCrossAlign.center,
    ).modifier(const DVModifier().rounded(12).backgroundColor(p.sunken));
  }
}

/// Where an order is, as a row of steps with the current one marked.
class const StatusTracker(final String status, {super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    final int at = orderStages.indexOf(status);
    return DVBox.list([
      for (int i = 0; i < orderStages.length; i++)
        DVBox.row(
          [
            DVBox(
              i < at || (i == at && i == orderStages.length - 1)
                  ? Icon(Icons.check, size: 14, color: p.onAccent)
                  : null,
            ).modifier(
              const DVModifier()
                  .width(22)
                  .height(22)
                  .rounded(11)
                  .align(Alignment.center)
                  .backgroundColor(i <= at ? p.accent : p.sunken)
                  .border(
                    Border.all(
                      color: i == at ? p.accent : p.line,
                      width: i == at ? 5 : 1,
                    ),
                  )
                  .animate(const Duration(milliseconds: 400)),
            ),
            Expanded(
              child: DVText(stageLabels[orderStages[i]]!).modifier(
                i == at ? p.headline : (i < at ? p.body : p.muted.fontSize(15)),
              ),
            ),
            if (i == at && i < orderStages.length - 1)
              const DVText('Now').modifier(
                p.overline
                    .color(p.accent)
                    .paddingSymmetric(horizontal: 8, vertical: 3)
                    .rounded(8)
                    .backgroundColor(p.accentSoft),
              ),
          ],
          spacing: 14,
          crossAlign: DVCrossAlign.center,
        ),
    ], spacing: 18);
  }
}

String statusLabel(String status) => stageLabels[status] ?? status;

/// "12 Sep", from milliseconds since the epoch.
String shortDate(int millis) {
  const List<String> months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final DateTime d = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${d.day} ${months[d.month - 1]}';
}

/// A row in a settings-style list.
class const ListRow({
  super.key,
  required final IconData icon,
  required final String title,
  final String? subtitle,
  final VoidCallback? onTap,
  final Widget? trailing,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child:
            DVBox.row(
              [
                DVBox(Icon(icon, size: 20, color: p.inkMuted)).modifier(
                  const DVModifier()
                      .width(38)
                      .height(38)
                      .rounded(10)
                      .align(Alignment.center)
                      .backgroundColor(p.sunken),
                ),
                Expanded(
                  child: DVBox.list([
                    DVText(title).modifier(p.headline.fontSize(15)),
                    if (subtitle != null)
                      DVText(
                        subtitle!,
                      ).modifier(p.muted.fontSize(13).maxLines(2)),
                  ], spacing: 2),
                ),
                trailing ??
                    (onTap == null
                        ? const SizedBox.shrink()
                        : Icon(Icons.chevron_right, color: p.inkFaint)),
              ],
              spacing: 14,
              crossAlign: DVCrossAlign.center,
            ).modifier(
              const DVModifier().paddingSymmetric(horizontal: 8, vertical: 10),
            ),
      ),
    );
  }
}

/// Rebuilds with every stored record of a model, now and after each change.
///
/// [watch] is the generated `Model.watch`, so this hears a save wherever it
/// happened: the roastery moving an order along, or the Manage screen
/// editing a coffee. Null until the first read arrives, which is the loading
/// state.
class const WatchModels<T>({
  super.key,
  required final Future<DVModelWatch> Function(void Function(List<T>)) watch,
  required final Widget Function(BuildContext context, List<T>? records)
  builder,
}) extends StatefulWidget {
  @override
  State<WatchModels<T>> createState() => _WatchModelsState<T>();
}

class _WatchModelsState<T> extends State<WatchModels<T>> {
  List<T>? _records;
  DVModelWatch? _watch;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    await openShopStore();
    final DVModelWatch watch = await widget.watch((List<T> records) {
      if (!_disposed) setState(() => _records = records);
    });
    if (_disposed) {
      await watch.cancel();
    } else {
      _watch = watch;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_watch?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _records);
}

/// The shop's name, set as a mark: a bean and the word.
class const Wordmark({super.key, final bool compact = false})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    final Widget mark =
        DVBox(
          Icon(Icons.coffee_outlined, size: 18, color: p.onAccent),
        ).modifier(
          const DVModifier()
              .width(34)
              .height(34)
              .rounded(10)
              .align(Alignment.center)
              .backgroundColor(p.accent),
        );
    if (compact) return Semantics(label: 'Oakline Coffee', child: mark);
    return DVBox.row([
      mark,
      const DVText('Oakline').modifier(
        const DVModifier()
            .fontSize(19)
            .fontWeight(FontWeight.w700)
            .letterSpacing(-0.3)
            .color(p.ink),
      ),
    ], spacing: 10);
  }
}

/// The strip over the shop: the name, how this was built, and the bag.
class const ShopTopBar({
  super.key,
  required final int bagCount,

  /// The page heading: under the bar on a phone, beside the actions on a
  /// wide screen, where the rail already carries the name.
  required final Widget heading,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    final bool wide = MediaQuery.sizeOf(context).width >= wideLayoutFrom;
    final Widget actions = DVBox.row(
      [
        DVNavLink(
          key: const Key('link-about'),
          to: DVRoutes.about,
          semanticLabel: 'Under the hood',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          // A phone has room for the icon; the name is still what a screen
          // reader announces.
          child: MediaQuery.sizeOf(context).width < 520
              ? Icon(Icons.code, size: 22, color: p.inkMuted)
              : DVBox.row([
                  Icon(Icons.code, size: 18, color: p.inkMuted),
                  const DVText(
                    'Under the hood',
                  ).modifier(p.muted.fontWeight(FontWeight.w600)),
                ], spacing: 6),
        ),
        IconButton(
          key: const Key('open-bag'),
          tooltip: 'Bag',
          onPressed: () => DV.Navigation.navigate(DVRoutes.cart),
          icon: Badge(
            isLabelVisible: bagCount > 0,
            label: Text('$bagCount'),
            backgroundColor: p.accent,
            textColor: p.onAccent,
            child: Icon(Icons.shopping_bag_outlined, color: p.ink),
          ),
        ),
      ],
      spacing: 4,
      crossAlign: DVCrossAlign.center,
    );
    if (wide) {
      return DVBox.row(
        [Expanded(child: heading), actions],
        spacing: 24,
        crossAlign: DVCrossAlign.start,
      );
    }
    return DVBox.list([
      DVBox.row([
        const Expanded(child: Wordmark()),
        actions,
      ], crossAlign: DVCrossAlign.center),
      heading,
    ], spacing: 20);
  }
}

/// The subscription, in one line and a link.
class const CoffeeClubBanner({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    return DVNavLink(
      key: const Key('link-pricing'),
      to: DVRoutes.pricing,
      semanticLabel: 'Coffee Club: see plans',
      padding: EdgeInsets.zero,
      child:
          DVBox.row(
            [
              DVBox(
                Icon(Icons.local_shipping_outlined, color: p.accent, size: 22),
              ).modifier(
                const DVModifier()
                    .width(44)
                    .height(44)
                    .rounded(12)
                    .align(Alignment.center)
                    .backgroundColor(p.surface),
              ),
              Expanded(
                child: DVBox.list([
                  const DVText('Coffee Club').modifier(p.headline),
                  DVText(
                    'A fresh bag every two weeks, from ${Product.nativePrice == null ? '' : formatPrice(Product.nativePrice!.amount)} a month.',
                  ).modifier(p.muted.fontSize(14)),
                ], spacing: 2),
              ),
              if (MediaQuery.sizeOf(context).width >= wideLayoutFrom)
                const DVText(
                  'See plans',
                ).modifier(p.headline.fontSize(14).color(p.accent)),
              Icon(Icons.arrow_forward, size: 18, color: p.accent),
            ],
            spacing: 14,
            crossAlign: DVCrossAlign.center,
          ).modifier(
            const DVModifier()
                .padding(14)
                .rounded(18)
                .backgroundColor(p.accentSoft),
          ),
    );
  }
}

/// A labelled fact about a coffee.
class const CoffeeFact(final String label, final String value, {super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    return DVBox.list(
      [
        DVText(label.toUpperCase()).modifier(p.overline),
        DVText(value).modifier(p.headline.fontSize(15)),
      ],
      spacing: 4,
      crossAlign: DVCrossAlign.start,
    ).modifier(
      const DVModifier()
          .paddingSymmetric(horizontal: 14, vertical: 10)
          .rounded(12)
          .minWidth(96)
          .backgroundColor(p.sunken),
    );
  }
}

/// A label and an amount on one line, as a receipt has them.
class const SummaryLine(
  final String label,
  final String value, {
  super.key,
  final String? note,
  final bool strong = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    final DVModifier style = strong
        ? p.headline.fontSize(18)
        : p.body.color(p.inkMuted);
    return DVBox.list([
      DVBox.row([
        Expanded(child: DVText(label).modifier(style)),
        DVText(value).modifier(strong ? style : p.body),
      ]),
      if (note != null) DVText(note!).modifier(p.muted.fontSize(13)),
    ], spacing: 2);
  }
}

/// An order's status, small, coloured by how far along it is.
class const StatusPill(final String status, {super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    final bool done = status == 'delivered';
    return DVBox.row([
      DVText(statusLabel(status)).modifier(
        const DVModifier()
            .fontSize(12)
            .fontWeight(FontWeight.w600)
            .color(done ? p.success : p.accent)
            .paddingSymmetric(horizontal: 10, vertical: 4)
            .rounded(999)
            .backgroundColor(
              done ? p.success.withValues(alpha: 0.12) : p.accentSoft,
            ),
      ),
    ]);
  }
}

/// A small pulsing dot and the word Live.
class const LiveDot({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    return DVBox.row(
      [
        const DVBox(null).modifier(
          const DVModifier()
              .width(8)
              .height(8)
              .rounded(4)
              .backgroundColor(p.success),
        ),
        const DVText('Live').modifier(p.overline.color(p.success)),
      ],
      spacing: 6,
      crossAlign: DVCrossAlign.center,
    );
  }
}

/// The way back to the shop from a page outside the tabs.
class const BackToShop({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Palette p = Palette.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: DVNavLink(
        key: const Key('back-to-shop'),
        to: DVRoutes.index,
        semanticLabel: 'Back to the shop',
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: DVBox.row(
          [Icon(Icons.arrow_back, size: 20, color: p.ink), const Wordmark()],
          spacing: 12,
          crossAlign: DVCrossAlign.center,
        ),
      ),
    );
  }
}

/// A coffee's colour and the first letter of its name, for a list row.
class const BagThumb(final Product coffee, {super.key, final double size = 56})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child:
        DVBox(
          DVText(coffee.name.characters.first).modifier(
            const DVModifier()
                .fontSize(22)
                .fontWeight(FontWeight.w700)
                .color(const Color(0xFFFFFBF6)),
          ),
        ).modifier(
          const DVModifier()
              .width(size)
              .height(size)
              .rounded(14)
              .align(Alignment.center)
              .backgroundColor(
                bagColorFor(coffee.slug, Theme.of(context).brightness),
              ),
        ),
  );
}
