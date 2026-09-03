/// Staged rollouts: which devices a release has reached yet.
///
/// A fleet is not updated all at once. A release goes to a slice of it,
/// somebody watches, and the slice grows. The decision of whether *this*
/// device is in the slice has to be made somewhere, and where it is made
/// matters more than it looks: a server that draws it at random answers
/// differently every time a device asks, so an update appears at nine
/// o'clock and is gone at ten, and nobody -- not the operator, not the
/// person holding the device -- can tell that apart from a broken server.
///
/// So it is not drawn. It is computed from the device and the version, and
/// the same two answer the same forever. The version is in the hash as well
/// as the device, which is what stops the same unlucky kiosks from being
/// last in the queue for every release they ever get -- and, more to the
/// point, stops the same devices from being the ones that find every bad
/// release.
class DVUpdateRollout {
  const DVUpdateRollout._();

  /// Whether the device is in the [percent] of the fleet this release has
  /// reached.
  ///
  /// [percent] is clamped: a server that says 140 means everyone and a
  /// server that says -10 means nobody, and neither is worth an exception
  /// on a device that is only trying to find out whether to update.
  ///
  /// An empty [deviceId] is included. A rollout that quietly excluded every
  /// device it could not name would sit at nought per cent while looking
  /// like it was working.
  static bool includes({
    required String deviceId,
    required String version,
    required int percent,
  }) {
    if (percent >= 100) return true;
    if (percent <= 0) return false;
    if (deviceId.isEmpty) return true;
    return bucketOf(deviceId: deviceId, version: version) < percent;
  }

  /// Where the device falls in the queue for [version], from 0 to 99.
  ///
  /// A rollout at n per cent has reached the buckets below n, so a device's
  /// bucket is also the percentage at which it starts being offered the
  /// release -- which is the number an operator wants when a device has not
  /// updated and they are trying to work out whether that is a fault or
  /// simply its turn not yet coming.
  static int bucketOf({required String deviceId, required String version}) {
    // FNV-1a. Small, stable, and defined here rather than borrowed from a
    // hash whose value may change between Dart versions: a device's place
    // in the queue must not move because the SDK moved under it.
    var hash = 0x811c9dc5;
    for (final int unit in '$deviceId@$version'.codeUnits) {
      hash ^= unit & 0xff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash % 100;
  }
}
