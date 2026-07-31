/// Dartvel database adapters: the contract, the in-memory development
/// adapter, and the SQLite adapter behind the zero-config local database.
library dartvel_core.database.adapters;

export 'adapter.dart';
export 'sqlite_adapter_unsupported.dart'
    if (dart.library.ffi) 'sqlite_adapter_ffi.dart';
