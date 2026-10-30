/// Whether this host can run a module's binding kind, for its generated
/// tests: off the VM there is no host to look at, so every kind that needs
/// one is refused with the reason.
library;

/// Why this host cannot run a [kind] binding, or null when it can.
String? dvModuleHostRefusal(
  String kind, {
  String? Function(String executable)? which,
  Map<String, String>? environment,
  String? os,
}) =>
    switch (kind) {
      'dartPackage' || 'ffi' => null,
      _ => '$kind modules are not run where there is no host process.',
    };
