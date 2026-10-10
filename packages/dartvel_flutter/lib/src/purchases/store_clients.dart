/// The platform's store client for `DV.Purchases`, behind a conditional
/// import so a web build never sees `dart:ffi` or JNI.
library dartvel_flutter.purchases.store_clients;

export 'store_clients_unsupported.dart'
    if (dart.library.ffi) 'store_clients_io.dart';
