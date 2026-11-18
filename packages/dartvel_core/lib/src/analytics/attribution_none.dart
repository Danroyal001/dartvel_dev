import 'attribution.dart';

/// Outside a browser there is no landing address, and the touches live as
/// long as the process.
DVAttributionStorage dvAttributionStorage() => _MemoryStorage();

Uri? dvLandingAddress() => null;

String? dvLandingReferrer() => null;

final class _MemoryStorage implements DVAttributionStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  void write(String key, String value) => _values[key] = value;
}
