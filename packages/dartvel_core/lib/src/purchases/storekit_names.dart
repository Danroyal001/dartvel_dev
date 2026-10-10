/// The names both halves of the StoreKit 2 bridge read.
///
/// `dartvel build` writes a Swift class by this name into the application,
/// and the Dart client finds it with `objc_getClass` and messages it with
/// these selectors. Spelled twice, the lookup answers nil for ever -- and nil
/// is also what an application built with plain `flutter build` answers, so
/// nothing could tell the two apart.
library dartvel.purchases.storekit_names;

/// The Objective-C name of the generated Swift class.
const String dvStoreKitClass = 'DartvelStoreKit';

/// `start(_ request: NSString) -> NSString`: begins an operation and answers
/// its request id.
const String dvStoreKitStartSelector = 'start:';

/// `poll(_ id: NSString) -> NSString?`: the operation's JSON answer once it
/// is done, else nil.
const String dvStoreKitPollSelector = 'poll:';

/// `drainUpdates() -> NSString`: the transactions `Transaction.updates`
/// delivered since the last call, as a JSON array.
const String dvStoreKitDrainSelector = 'drainUpdates';

/// `listen()`: starts the `Transaction.updates` listener. StoreKit delivers
/// purchases that completed while the application was closed only to a
/// listener, so the client starts it as soon as purchases are configured.
const String dvStoreKitListenSelector = 'listen';
