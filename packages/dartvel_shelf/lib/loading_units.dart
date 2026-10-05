/// Deferred code units a web-server binary carries inside itself, loaded
/// from where they lie the first time the program needs each.
library;

export 'src/loading_units.dart' show dvInstallLoadingUnits, dvLoadedUnitCount, dvLoadingUnitSection;
