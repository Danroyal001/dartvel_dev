import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart' show DV;
import 'user_agent.dart' if (dart.library.js_interop) 'user_agent_web.dart';

/// What kind of screen the app is on, read from its real logical size.
///
/// [DVBreakpoint] answers "how wide is the layout"; this answers "what is this
/// device", which decides how big the whole interface should be drawn. A
/// television and a desktop monitor can both be 1920 wide, and a watch face is
/// narrower than any phone a layout is designed for.
enum DVScreenClass { watch, phone, tablet, desktop, tv, billboard }

/// How Dartvel sizes the whole interface for the screen.
///
/// [DVDisplayScaling.auto] (the default) leaves phones, tablets and desktops
/// alone, lays a television or a 4K signage panel out as a 1280 x 720 screen
/// drawn larger, and lays a watch out as a 320-wide screen drawn smaller.
/// [DVDisplayScaling.off] draws everything at 1; [DVDisplayScaling.fixed]
/// draws at one factor everywhere.
///
/// Set it in `pubspec.yaml` (`dartvel: display: scaling: auto | off | 1.5`)
/// or in code with `DV.Platform.screen.scaling = ...`.
@immutable
class DVDisplayScaling {
  const DVDisplayScaling.auto() : factor = null, enabled = true;
  const DVDisplayScaling.off() : factor = null, enabled = false;
  const DVDisplayScaling.fixed(double this.factor) : enabled = true;

  /// The one factor of a fixed scaling; null for auto and off.
  final double? factor;
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is DVDisplayScaling && other.factor == factor && other.enabled == enabled;

  @override
  int get hashCode => Object.hash(factor, enabled);

  @override
  String toString() =>
      !enabled ? 'DVDisplayScaling.off()' : factor == null ? 'DVDisplayScaling.auto()' : 'DVDisplayScaling.fixed($factor)';
}

/// The screen a television is laid out as: big enough to read from a sofa.
const Size _tenFootScreen = Size(1280, 720);

/// The width a watch face is laid out as, so phone-sized content fits.
const double _watchLayoutWidth = 320;

/// True for the browsers smart TVs, set-top boxes and casting sticks ship.
bool dvIsTelevisionUserAgent(String agent) => RegExp(
      r'SMART-?TV|SmartTV|Tizen|Web0S|webOS\.TV|NetCast|HbbTV|BRAVIA|'
      r'\bAFT[A-Z]|CrKey|Google ?TV|Android ?TV|AppleTV|tvOS|Roku|Viera|AQUOS',
      caseSensitive: false,
    ).hasMatch(agent);

/// The class of a screen of logical [size].
DVScreenClass dvScreenClassFor(Size size, {bool television = false, bool watch = false}) {
  final double shortest = size.shortestSide;
  if (watch || (shortest < 300 && size.longestSide < 400)) return DVScreenClass.watch;
  if (television) return DVScreenClass.tv;
  // No desktop runs a 2160-tall layout at 1x; a 4K panel at 1x is signage.
  if (shortest >= 1800) return DVScreenClass.billboard;
  if (size.width >= 1200) return DVScreenClass.desktop;
  if (shortest >= 600) return DVScreenClass.tablet;
  return DVScreenClass.phone;
}

/// The factor the whole interface is drawn at on a screen of logical [size].
double dvDisplayScaleFor(
  Size size, {
  DVDisplayScaling scaling = const DVDisplayScaling.auto(),
  DVScreenClass? declared,
  bool television = false,
  bool watch = false,
}) {
  if (!scaling.enabled) return 1;
  if (scaling.factor != null) return scaling.factor!;
  if (size.isEmpty) return 1;
  switch (declared ?? dvScreenClassFor(size, television: television, watch: watch)) {
    case DVScreenClass.watch:
      return (size.shortestSide / _watchLayoutWidth).clamp(0.6, 1.0).toDouble();
    case DVScreenClass.tv:
    case DVScreenClass.billboard:
      final Size base = size.height > size.width ? _tenFootScreen.flipped : _tenFootScreen;
      return math.max(1, math.min(size.width / base.width, size.height / base.height)).toDouble();
    case DVScreenClass.phone:
    case DVScreenClass.tablet:
    case DVScreenClass.desktop:
      return 1;
  }
}

/// `dartvel: display: scaling:` from pubspec, as the build passes it.
DVDisplayScaling dvDisplayScalingFromDefine(String value) {
  final String text = value.trim().toLowerCase();
  if (text == 'off' || text == 'false' || text == 'none') return const DVDisplayScaling.off();
  final double? number = double.tryParse(text);
  if (number != null && number > 0) return DVDisplayScaling.fixed(number);
  return const DVDisplayScaling.auto();
}

/// `dartvel: display: screen:` from pubspec: a screen class the app declares.
DVScreenClass? dvScreenClassFromDefine(String value) {
  final String text = value.trim().toLowerCase();
  for (final DVScreenClass screenClass in DVScreenClass.values) {
    if (screenClass.name == text) return screenClass;
  }
  return null;
}

final ValueNotifier<DVDisplayScaling> _scaling = ValueNotifier<DVDisplayScaling>(
  dvDisplayScalingFromDefine(const String.fromEnvironment('DARTVEL_DISPLAY_SCALING')),
);
final DVScreenClass? _declaredClass =
    dvScreenClassFromDefine(const String.fromEnvironment('DARTVEL_SCREEN_CLASS'));
double _currentScale = 1;
DVScreenClass _currentClass = DVScreenClass.desktop;

/// The scaling in force; read and written through `DV.Platform.screen.scaling`.
DVDisplayScaling get dvDisplayScaling => _scaling.value;
set dvDisplayScaling(DVDisplayScaling value) => _scaling.value = value;

/// The factor the interface is drawn at now (`DV.Platform.screen.uiScale`).
double get dvCurrentUiScale => _currentScale;

/// The class of the screen the app is on now (`DV.Platform.screen.screenClass`).
DVScreenClass get dvCurrentScreenClass => _currentClass;

bool _televisionHost() => DV.Platform.isTV || dvIsTelevisionUserAgent(dvUserAgent());

/// Draws [child] at the scale that suits the screen.
///
/// The child is laid out against the screen's size divided by the scale and
/// painted that many times larger, so a page designed for a laptop fills a
/// 4K panel at a readable size and still fits a watch. Taps, focus and the
/// semantics tree follow the same transform. At a scale of 1 -- every phone,
/// tablet and desktop under the default -- the child is returned as it is.
///
/// `DV.run` puts this above the application; nothing has to add it.
class DVDisplayScale extends StatelessWidget {
  const DVDisplayScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DVDisplayScaling>(
      valueListenable: _scaling,
      child: child,
      builder: (BuildContext context, DVDisplayScaling scaling, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        final bool television = _televisionHost();
        final bool watch = DV.Platform.isWatch;
        _currentClass = _declaredClass ?? dvScreenClassFor(media.size, television: television, watch: watch);
        final double scale = dvDisplayScaleFor(
          media.size,
          scaling: scaling,
          declared: _declaredClass,
          television: television,
          watch: watch,
        );
        _currentScale = scale;
        if (scale == 1) return child!;
        final Size laidOut = media.size / scale;
        EdgeInsets shrink(EdgeInsets insets) => insets / scale;
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: laidOut.width,
              height: laidOut.height,
              child: MediaQuery(
                data: media.copyWith(
                  size: laidOut,
                  devicePixelRatio: media.devicePixelRatio * scale,
                  padding: shrink(media.padding),
                  viewPadding: shrink(media.viewPadding),
                  viewInsets: shrink(media.viewInsets),
                  systemGestureInsets: shrink(media.systemGestureInsets),
                ),
                child: child!,
              ),
            ),
          ),
        );
      },
    );
  }
}
