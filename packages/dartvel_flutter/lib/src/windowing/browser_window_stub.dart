/// Off the web there is no browser to ask, so nothing is attempted.
///
/// [DVBrowserWindowOutcome.notWeb] rather than a refusal: a refusal would be
/// the caller's answer, and on a desktop the answer is the native binding's.
library dartvel_flutter.windowing.browser_window.stub;

import 'browser_window_types.dart';

/// Nothing to open: this target opens windows through `window.open`.
DVBrowserWindowResult dvOpenBrowserWindow(
  String url, {
  String? title,
  double? width,
  double? height,
}) =>
    const DVBrowserWindowResult(DVBrowserWindowOutcome.notWeb);

/// Nothing to close.
bool dvCloseBrowserWindow(String? id) => false;
