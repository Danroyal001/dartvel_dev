/// A browser build has no process environment, and it must not: a secret
/// compiled into a web bundle is readable by every visitor. Secrets resolve
/// only from [DVSecrets.configure] here, which a host can populate from a
/// value it fetched at runtime through an authenticated call.
String? readEnvironment(String key) => null;

/// No `.env` on the web either, and this is deliberately not a stub waiting to
/// be filled in. Fetching that file over HTTP would put the whole backend
/// environment behind a URL any visitor can request -- the exact leak the
/// PUBLIC_ prefix exists to prevent, reintroduced through the back door.
void useEnvFile(String path) {}

void resetEnvFile() {}

String missingSecretReason(String key) =>
    'secrets are not read from the environment on the web, because anything '
    'compiled into the bundle ships to every visitor. Fetch "$key" through a '
    'backend function, or register it with DVSecrets.configure(...) after '
    'resolving it at runtime.';
