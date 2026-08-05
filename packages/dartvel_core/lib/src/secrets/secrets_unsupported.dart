/// A browser build has no process environment, and it must not: a secret
/// compiled into a web bundle is readable by every visitor. Secrets resolve
/// only from [DVSecrets.configure] here, which a host can populate from a
/// value it fetched at runtime through an authenticated call.
String? readEnvironment(String key) => null;

String missingSecretReason(String key) =>
    'secrets are not read from the environment on the web, because anything '
    'compiled into the bundle ships to every visitor. Fetch "$key" through a '
    'backend function, or register it with DVSecrets.configure(...) after '
    'resolving it at runtime.';
