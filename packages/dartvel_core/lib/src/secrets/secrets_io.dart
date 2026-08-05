import 'dart:io';

String? readEnvironment(String key) => Platform.environment[key];

String missingSecretReason(String key) =>
    'no environment variable "$key" is set for this process, and nothing was '
    'registered with DVSecrets.configure(...).';
