/// A size in bytes, written the way `dartvel.memory` writes one.
library;

/// A byte count. Units are binary: `DVSize.mb(1)` is 1,048,576 bytes.
final class DVSize implements Comparable<DVSize> {
  const DVSize.bytes(this.bytes);
  const DVSize.kb(int kilobytes) : bytes = kilobytes * 1024;
  const DVSize.mb(int megabytes) : bytes = megabytes * 1024 * 1024;
  const DVSize.gb(int gigabytes) : bytes = gigabytes * 1024 * 1024 * 1024;

  final int bytes;

  static const Map<String, int> _units = <String, int>{
    'B': 1,
    'KB': 1024,
    'MB': 1024 * 1024,
    'GB': 1024 * 1024 * 1024,
    'TB': 1024 * 1024 * 1024 * 1024,
  };

  /// Reads `4GB`, `256MB`, `512 mb`, `1.5GB` or a bare byte count.
  ///
  /// Throws [FormatException] for anything else, including a negative size:
  /// a size that could not be read is never taken as zero, because an arena
  /// sized from a misread budget reserves nothing and says nothing.
  static DVSize parse(String text) {
    final RegExpMatch? m = RegExp(
      r'^\s*(\d+(?:\.\d+)?)\s*([a-zA-Z]*)\s*$',
    ).firstMatch(text);
    if (m == null) throw FormatException('not a size', text);
    final String unit = m.group(2)!.toUpperCase();
    final int? scale = unit.isEmpty ? 1 : _units[unit];
    if (scale == null) throw FormatException('unknown size unit', text);
    return DVSize.bytes((double.parse(m.group(1)!) * scale).round());
  }

  /// [parse] for a value read out of YAML, which may already be an int.
  static DVSize? tryRead(Object? value) {
    if (value is int && value >= 0) return DVSize.bytes(value);
    if (value is String) {
      try {
        return parse(value);
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  bool get isPowerOfTwo => bytes > 0 && (bytes & (bytes - 1)) == 0;

  bool operator <(DVSize other) => bytes < other.bytes;
  bool operator >(DVSize other) => bytes > other.bytes;

  @override
  int compareTo(DVSize other) => bytes.compareTo(other.bytes);

  @override
  bool operator ==(Object other) => other is DVSize && other.bytes == bytes;

  @override
  int get hashCode => bytes.hashCode;

  /// `4GB`, `1.5GB`, `384KB`: the largest unit the size reaches, to one
  /// decimal place, which is how the diagnostics print it.
  @override
  String toString() {
    for (final String unit in const <String>['TB', 'GB', 'MB', 'KB']) {
      final int scale = _units[unit]!;
      if (bytes >= scale) {
        final String n = (bytes / scale).toStringAsFixed(1);
        return '${n.endsWith('.0') ? n.substring(0, n.length - 2) : n}$unit';
      }
    }
    return '${bytes}B';
  }
}
