/// The hook the build's semantics read moves a running app between routes
/// with, so it boots the app once per browser tab instead of once per route.
library dartvel_flutter.routing.capture_hook.web;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/painting.dart';
import 'package:go_router/go_router.dart';

/// The page global the build reads.
const String _global = '__dartvelCapture';

/// Installs `globalThis.__dartvelCapture` for [router] in a browser under
/// automation (`navigator.webdriver`, or [automated] when given):
///
/// * `go(path)` forgets the images the app has decoded and the slots
///   DVImageView recorded, then goes to [path] as a link does. Forgetting is
///   what makes the next route ask for its own images, so the capture records
///   the same requests a fresh load of it makes.
/// * `location()` is where the router is now: a route that redirected
///   elsewhere is read with a fresh load instead.
///
/// A browser a person is using never has it.
void dvInstallCaptureHook(GoRouter router, {bool? automated}) {
  final bool underAutomation = automated ??
      (globalContext
              .getProperty<JSObject?>('navigator'.toJS)
              ?.getProperty<JSBoolean?>('webdriver'.toJS)
              ?.toDart ??
          false);
  if (!underAutomation) return;
  final JSObject hook = JSObject();
  hook.setProperty(
    'go'.toJS,
    ((JSString path) {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      globalContext.delete('__dartvelImages'.toJS);
      router.go(path.toDart);
    }).toJS,
  );
  hook.setProperty(
    'location'.toJS,
    (() => router.routerDelegate.currentConfiguration.uri.path.toJS).toJS,
  );
  globalContext.setProperty(_global.toJS, hook);
}
