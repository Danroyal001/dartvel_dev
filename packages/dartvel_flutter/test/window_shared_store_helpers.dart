// Shared between the store tests and the persistence tests.
import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';

/// A backend that notifies, standing in for a preference store on a
/// cross-engine target.
class NotifyingBackend extends DVSharedStoreBackend {
  final Map<String, String> values = <String, String>{};
  final StreamController<String> _changes =
      StreamController<String>.broadcast();

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<List<String>> keys() async => values.keys.toList(growable: false);

  @override
  Stream<String> get changed => _changes.stream;

  /// Another window wrote this key.
  void externalWrite(String key, String raw) {
    values[key] = raw;
    _changes.add(key);
  }
}
