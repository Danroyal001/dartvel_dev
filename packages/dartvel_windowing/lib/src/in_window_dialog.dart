/// Dialogs that open inside the window that asked for them.
library dartvel_windowing.dialogs;

import 'package:flutter/material.dart';

/// [showDialog], kept inside the calling window.
///
/// With windowing enabled, Flutter's `showDialog` opens every dialog as an
/// OS window of its own, sized to its content -- which an `AlertDialog`
/// whose content asks for a width does not survive: it opened a couple of
/// hundred pixels wide with its content cut off. An application that opens a
/// projector window still wants its forms and confirmations in front of the
/// operator, where they are on every other target.
Future<T?> showInWindowDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) =>
    Navigator.of(context, rootNavigator: useRootNavigator).push<T>(DialogRoute<T>(
      context: context,
      builder: builder,
      barrierDismissible: barrierDismissible,
      themes: InheritedTheme.capture(from: context, to: Navigator.of(context, rootNavigator: useRootNavigator).context),
    ));
