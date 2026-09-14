/// Crash hooks on a target with neither dart:io nor a browser.
library;

import 'package:dartvel_core/dartvel.dart';

import 'crash_directory.dart';
import 'crash_hook.dart';

void Function() dvInstallPlatformCrashHooks(DVCrashTextReceiver receive) =>
    () {};

DVCrashStore? dvDefaultCrashStore(String appId) => null;

/// Nowhere to keep it, so an id for this run only.
String dvInstallId(String appId) =>
    dvInstallIdFrom(read: () => null, write: (String _) {});

bool dvHostedByTestRunner() => false;
