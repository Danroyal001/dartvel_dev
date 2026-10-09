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
    final safe = viewport.safeArea;
    final content = viewport.contentSafeArea;
    // The two coordinate systems are insets from the same viewport edge.
    final inset = EdgeInsets.fromLTRB(
      safe.left > content.left ? safe.left : content.left,
      safe.top > content.top ? safe.top : content.top,
      safe.right > content.right ? safe.right : content.right,
      safe.bottom > content.bottom ? safe.bottom : content.bottom,
    );
    final media = MediaQuery.of(context);
    final height = viewport.height.isFinite && viewport.height > 0
        ? viewport.height.clamp(0.0, media.size.height)
        : media.size.height;
    return Theme(
      data: dvTelegramTheme(Theme.of(context), theme),
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
    );
  }
}
