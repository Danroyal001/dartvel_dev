// GENERATED CODE - DO NOT MODIFY BY HAND

/// Centrally generated Dartvel configuration matching your pubspec.yaml.
class DartvelConfig {
  /// The database provider (e.g. sqlite, postgres, mysql).
  static const databaseProvider = 'sqlite';
  
  /// The path to database file (if sqlite).
  static const databasePath = 'dartvel.db';
  
  /// The storage provider (e.g. local, s3, r2).
  static const storageProvider = 'local';
  
  /// The list of active authentication providers.
  static const authProviders = <String>[];
  
  /// The primary AI model provider.
  static const aiProvider = 'gemini';
  
  /// Whether multi-tenancy is active.
  static const multiTenancyEnabled = false;
  
  /// Whether PWA manifest & worker are enabled.
  static const pwaEnabled = true;
  
  /// List of platform permissions requested.
  static const permissions = <String>[];
}

/// Named kiosk policies, from dartvel.kiosk.policies in pubspec.yaml.
class DVKioskPolicies {
  DVKioskPolicies._();

  static const List<String> names = <String>[];
}

