import 'target.dart';

/// dart2js represents every number as a JavaScript double, so `0` and `0.0`
/// are the same object there and nowhere else.
DVMemoryTarget dvDetectMemoryTarget() =>
    identical(0, 0.0) ? DVMemoryTarget.webJs : DVMemoryTarget.webWasm;
