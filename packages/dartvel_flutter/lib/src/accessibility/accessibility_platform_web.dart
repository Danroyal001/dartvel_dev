/// A browser: the settings in `localStorage`, where the SSR-first head reads
/// them before the first paint, and the operating system's wishes read from
/// the `prefers-contrast` and `prefers-reduced-motion` media queries.
library;

import 'dart:js_interop';

import 'package:dartvel_core/dartvel.dart' show dvAccessibilityStorageKey;
import 'package:web/web.dart' as web;

import 'accessibility_store.dart';

DVAccessibilityStore dvPlatformAccessibilityStore(String app) => _LocalStorage();

bool _matches(String query) {
  try {
    return web.window.matchMedia(query).matches;
  } on Object {
    return false;
  }
}

bool dvSystemPrefersContrast() => _matches('(prefers-contrast: more)');

bool dvSystemPrefersReducedMotion() => _matches('(prefers-reduced-motion: reduce)');

void dvWatchSystemPreferences(void Function() changed) {
  for (final String query in <String>['(prefers-contrast: more)', '(prefers-reduced-motion: reduce)']) {
    try {
      web.window.matchMedia(query).addEventListener('change', ((web.Event _) => changed()).toJS);
    } on Object {
      // An old browser without the query: the setting simply never changes.
    }
  }
}

final class _LocalStorage implements DVAccessibilityStore {
  @override
  String? read() {
    try {
      return web.window.localStorage.getItem(dvAccessibilityStorageKey);
    } on Object {
      return null;
    }
  }

  @override
  void write(String value) {
    try {
      web.window.localStorage.setItem(dvAccessibilityStorageKey, value);
    } on Object {
      // Storage refused (a private window, a full quota): the settings hold
      // for this visit.
    }
  }
}
