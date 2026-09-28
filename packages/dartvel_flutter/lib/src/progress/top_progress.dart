/// The thin bar across the top of the screen while something loads.
///
/// A web page shows one in its HTML until Flutter's first frame; this is the
/// same bar after that, and on every other platform from the start. A page
/// arriving and a page's data loading show it through `DvDefaultLoading`,
/// and an application shows it for its own work through [DVTopProgress].
library;

import 'package:flutter/material.dart';

/// The loads an application is waiting on, for the bar at the top of the
/// page. Reached as `DV.progress`.
class DVTopProgress extends ChangeNotifier {
  DVTopProgress._();

  /// The one an application reaches as `DV.progress`.
  static final DVTopProgress instance = DVTopProgress._();

  int _active = 0;
  bool _enabled = true;
  Color? _color;

  /// Whether a tracked load shows the bar. On by default.
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    notifyListeners();
  }

  /// The bar's colour; the theme's primary colour when null.
  Color? get color => _color;
  set color(Color? value) {
    if (value == _color) return;
    _color = value;
    notifyListeners();
  }

  /// Whether the bar is showing for something the application tracks.
  bool get active => _enabled && _active > 0;

  /// Shows the bar until [future] completes, however it completes.
  Future<T> track<T>(Future<T> future) {
    final VoidCallback end = start();
    return future.whenComplete(end);
  }

  /// Shows the bar until the returned callback is called. Calling it again
  /// does nothing, so one load ending twice cannot end another.
  VoidCallback start() {
    _active++;
    if (_active == 1) notifyListeners();
    bool ended = false;
    return () {
      if (ended) return;
      ended = true;
      _active--;
      if (_active == 0) notifyListeners();
    };
  }
}

/// The bar itself: three points high, the theme's primary colour unless
/// [DVTopProgress.color] says otherwise, and still when the platform asks for
/// reduced motion.
class DVTopProgressBar extends StatelessWidget {
  const DVTopProgressBar({super.key, this.height = 3});

  final double height;

  @override
  Widget build(BuildContext context) {
    final Color color =
        DVTopProgress.instance.color ?? Theme.of(context).colorScheme.primary;
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: still
          // The indeterminate indicator slides for as long as the load
          // lasts, which is the motion reduced motion asks to be spared.
          ? Semantics(
              container: true,
              label: 'Loading',
              child: ColoredBox(color: color.withValues(alpha: 0.6)),
            )
          : LinearProgressIndicator(
              minHeight: height,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
              semanticsLabel: 'Loading',
            ),
    );
  }
}

/// The bar over a page while [DVTopProgress] tracks something.
class DVTrackedProgress extends StatelessWidget {
  const DVTrackedProgress({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: DVTopProgress.instance,
        builder: (BuildContext context, Widget? _) =>
            DVTopProgress.instance.active
                ? const DVTopProgressBar()
                : const SizedBox.shrink(),
      );
}
