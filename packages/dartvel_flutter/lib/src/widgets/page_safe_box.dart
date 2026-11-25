import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Makes the page's safe box its screen.
///
/// A [SafeArea] takes the insets away from [MediaQuery] and leaves its size
/// alone, so inside a page the screen still read as the whole window while
/// there was no inset left to subtract from it. A page that sized itself from
/// the screen -- the Dev Launcher's letter index, 27 equal cells sharing the
/// screen's height -- was too big by exactly the insets and ran under the
/// navigation bar (owner, 18 Nov 2026: "'Z' is digging into the system nav
/// bar"). Here the screen's size loses what the page shell's own chrome took
/// from it -- the status bar, the notch, the navigation bar, an app bar --
/// with no padding left to subtract. The whole window is still
/// `DV.Platform.screen.size`.
///
/// What the chrome took is the shell's whole box ([DVPageOuterBox]) less the
/// box the page is given, taken from the screen's size rather than replacing
/// it, so a screen size the shell keeps through a zero-size frame stays the
/// one the page reads.
class DVPageSafeBox extends StatelessWidget {
  const DVPageSafeBox({super.key, this.keptBelow, required this.child});

  final Widget child;

  /// The room the safe area keeps under the page when the page does not
  /// shrink for the on-screen keyboard: the navigation bar's height, kept
  /// while the keyboard covers the bar. Given, the page reads the keyboard
  /// from its own bottom edge -- `viewInsets.bottom` is how far the keyboard
  /// reaches up the page -- and no navigation bar is left under it, so a list
  /// over a box of `viewInsets.bottom` ends exactly at the keyboard's top.
  /// Android measures the keyboard from the bottom of the screen, which put
  /// such a list the bar's height above the keyboard. Null for a page that
  /// shrinks for the keyboard, whose scaffold already leaves none of it over
  /// the page.
  final double? keptBelow;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final MediaQueryData? media = MediaQuery.maybeOf(context);
          final Size? outer = DVPageOuterBox.maybeOf(context);
          if (media == null) return child;
          Size size = media.size;
          if (outer != null &&
              !outer.isEmpty &&
              constraints.hasBoundedWidth &&
              constraints.hasBoundedHeight) {
            final double takenAcross = math.max(0, outer.width - constraints.maxWidth);
            final double takenDown = math.max(0, outer.height - constraints.maxHeight);
            size = Size(
              math.max(0, size.width - takenAcross),
              math.max(0, size.height - takenDown),
            );
          }
          // Always a MediaQuery, even when nothing was taken, so the page
          // below keeps its state when an inset comes or goes.
          final double? below = keptBelow;
          final MediaQueryData measured = below == null
              ? media.copyWith(size: size)
              : media.copyWith(
                  size: size,
                  viewInsets: media.viewInsets.copyWith(bottom: math.max(0, media.viewInsets.bottom - below)),
                  viewPadding: media.viewPadding.copyWith(bottom: math.max(0, media.viewPadding.bottom - below)),
                );
          return MediaQuery(data: measured, child: child);
        },
      );
}

/// The page shell's whole box, before its scaffold, bars and safe area take
/// their share. See [DVPageSafeBox].
class DVPageOuterBox extends InheritedWidget {
  const DVPageOuterBox({super.key, required this.size, required super.child});

  final Size size;

  static Size? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DVPageOuterBox>()?.size;

  @override
  bool updateShouldNotify(DVPageOuterBox oldWidget) => size != oldWidget.size;
}

/// Measures the shell's whole box for [DVPageSafeBox].
Widget dvMeasurePageOuterBox(Widget child) => LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) =>
          // Always the same widget, so the page keeps its state; an unbounded
          // box is reported as empty, which DVPageSafeBox ignores.
          DVPageOuterBox(
            size: constraints.hasBoundedWidth && constraints.hasBoundedHeight
                ? constraints.biggest
                : Size.zero,
            child: child,
          ),
    );
