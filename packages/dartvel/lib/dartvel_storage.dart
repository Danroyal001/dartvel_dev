/// File storage: the `DV.FileStorage` facade and its adapters.
library dartvel_storage;

export 'package:dartvel_flutter/dartvel_flutter.dart'
    show
        DV,
        DVStorage,
        DVFileStorageAdapter,
        DVMemoryFileStorageAdapter,
        S3FileStorageAdapter,
        DVFileStorageException,
        DVAwsCredentials,
        DVAwsSigV4;
