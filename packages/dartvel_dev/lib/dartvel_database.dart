/// Database: the `DV.Database` facade and its adapters, and `DV.Cache` with
/// the cache adapters `DV.Cache.withAdapter` switches to.
library dartvel_database;

export 'package:dartvel_flutter/dartvel_flutter.dart'
    show
        DV,
        DVDatabase,
        DVDatabaseAdapter,
        MemoryDVDatabaseAdapter,
        SqliteDVDatabaseAdapter,
        DVCache,
        DVCacheView,
        DVCacheAdapter,
        DVMemoryCacheAdapter,
        DVDatabaseCacheAdapter,
        DVRedisCacheAdapter,
        DVMemcachedCacheAdapter,
        DVDistributedCacheAdapter;
