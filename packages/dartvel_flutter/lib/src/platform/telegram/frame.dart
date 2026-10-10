import 'dart:async';

import 'package:flutter/material.dart';

import 'telegram.dart';

/// Framework page wrapper: live host theme and insets without app wiring.
class const DVTelegramFrame({super.key, required final Widget child})
    extends StatefulWidget {
  @override
  State<DVTelegramFrame> createState() => _FrameState();
}

class _FrameState extends State<DVTelegramFrame> {
  final List<StreamSubscription<Object?>> _subscriptions = [];
  @override
  void initState() {
    super.initState();
    final telegram = dvTelegramHere();
    if (telegram == null) return;
    for (final changes in [telegram.theme.changes, telegram.viewport.changes]) {
      _subscriptions.add(
        changes.listen((_) {
          if (mounted) setState(() {});
        }),
      );
    }
    unawaited(telegram.ready());
    unawaited(telegram.expand());
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final telegram = dvTelegramHere();
    if (telegram == null) return widget.child;
    final theme = telegram.theme.value;
    final viewport = telegram.viewport.value;
    // Telegram measures the content safe area from the safe area's edges
    // (its header controls sit inside the device safe area), so the usable
    // inset is the sum of the two.
    final inset = viewport.safeArea + viewport.contentSafeArea;
    final media = MediaQuery.of(context);
    final height = viewport.height.isFinite && viewport.height > 0
        ? viewport.height.clamp(0.0, media.size.height)
        : media.size.height;
    final themed = dvTelegramTheme(Theme.of(context), theme);
    return Theme(
      data: themed,
      // The host background fills the insets and whatever lies below the
      // host viewport, rather than the document behind the canvas.
      child: ColoredBox(
        color: themed.scaffoldBackgroundColor,
        child: Align(
          alignment: .topCenter,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: inset,
              child: MediaQuery(
                data: media.copyWith(
                  size: Size(
                    (media.size.width - inset.horizontal).clamp(
                      0.0,
                      double.infinity,
                    ),
                    (height - inset.vertical).clamp(0.0, double.infinity),
                  ),
                  padding: .zero,
                  viewPadding: .zero,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
