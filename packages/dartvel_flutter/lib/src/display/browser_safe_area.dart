import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'browser_safe_area_stub.dart'
    if (dart.library.js_interop) 'browser_safe_area_web.dart';

/// Hands the browser's safe-area insets to the app on the web.
///
/// Flutter's web engine reports no padding at all, while every Dartvel page
/// document asks for `viewport-fit=cover` so the app can draw edge to edge:
/// on a notched iPhone, in landscape, or as an installed PWA, the page then
/// ran under the notch and the home indicator with nothing telling it so.
/// The browser knows the insets as `env(safe-area-inset-*)`; this reads them
/// and puts them in [MediaQuery] as padding, so every page's safe area, every
/// sheet and every dialog keeps clear of them exactly as it does on a phone.
///
/// Each side takes the larger of what the engine reports and what the
/// browser does, so an engine that one day reports them is not padded twice.
/// Off the web the browser never reports anything and this adds nothing.
///
/// `DV.run` puts this above the application; nothing has to add it.
class DVBrowserSafeArea extends StatefulWidget {
  const DVBrowserSafeArea({super.key, required this.child});

  final Widget child;

  /// The browser's insets now, in logical pixels; zero off the web. Tests set
  /// it to stand in for a notched phone.
  static final ValueNotifier<EdgeInsets> insets =
      ValueNotifier<EdgeInsets>(EdgeInsets.zero);

  @override
  State<DVBrowserSafeArea> createState() => _DVBrowserSafeAreaState();
}

class _DVBrowserSafeAreaState extends State<DVBrowserSafeArea> {
  @override
  void initState() {
    super.initState();
    dvWatchBrowserSafeArea((EdgeInsets read) {
      if (read != DVBrowserSafeArea.insets.value) {
        DVBrowserSafeArea.insets.value = read;
      }
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<EdgeInsets>(
        valueListenable: DVBrowserSafeArea.insets,
        child: widget.child,
        builder: (BuildContext context, EdgeInsets browser, Widget? child) {
          final MediaQueryData? media = MediaQuery.maybeOf(context);
          if (media == null || browser == EdgeInsets.zero) return child!;
          return MediaQuery(
            data: media.copyWith(
              padding: dvLargerInsets(media.padding, browser),
              viewPadding: dvLargerInsets(media.viewPadding, browser),
            ),
            child: child!,
          );
        },
      );
}

/// Each side's larger inset.
EdgeInsets dvLargerInsets(EdgeInsets first, EdgeInsets second) => EdgeInsets.fromLTRB(
      math.max(first.left, second.left),
      math.max(first.top, second.top),
      math.max(first.right, second.right),
      math.max(first.bottom, second.bottom),
    );
