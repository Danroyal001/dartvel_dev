import 'package:web/web.dart' as web;

import 'preference_store.dart';

DVPreferenceStore dvPlatformPreferenceStore() => const _LocalStorage();

/// `localStorage`. Every call can throw (a private window, storage blocked,
/// a full quota); a value that cannot be kept still applies to this visit.
final class _LocalStorage implements DVPreferenceStore {
  const _LocalStorage();

  @override
  String? read(String key) {
    try {
      return web.window.localStorage.getItem(key);
    } on Object {
      return null;
    }
  }

  @override
  void write(String key, String value) {
    try {
      web.window.localStorage.setItem(key, value);
    } on Object {
      // Kept for this visit only.
    }
  }

  @override
  void remove(String key) {
    try {
      web.window.localStorage.removeItem(key);
    } on Object {
      // Nothing to forget.
    }
  }
}
