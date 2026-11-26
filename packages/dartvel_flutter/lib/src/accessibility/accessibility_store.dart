/// Where a visitor's accessibility settings are kept between visits.
library;

/// One small value, read once at start and written on every change.
abstract interface class DVAccessibilityStore {
  String? read();
  void write(String value);
}

/// Kept in memory: tests, and a platform with nowhere to keep it.
final class DVMemoryAccessibilityStore implements DVAccessibilityStore {
  String? value;

  @override
  String? read() => value;

  @override
  void write(String value) => this.value = value;
}
