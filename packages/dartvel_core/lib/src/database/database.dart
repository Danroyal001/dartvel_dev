import 'dart:async';
import 'package:drift/drift.dart';

/// Database manager wrapper around Drift
abstract class DatabaseManager {
  /// Get the underlying Drift database
  GeneratedDatabase get db;

  /// Initialize the database connection
  Future<void> connect();

  /// Close the database connection
  Future<void> close();

  /// Run a transaction
  Future<T> transaction<T>(Future<T> Function() action);
}

/// Database configuration
class DatabaseConfig {
  final String name;
  final bool useInMemory;
  final bool logStatements;
  final int version;

  const DatabaseConfig({
    this.name = 'dartvel_app',
    this.useInMemory = false,
    this.logStatements = false,
    this.version = 1,
  });
}

/// Base class for app database
abstract class DartvelDatabase extends GeneratedDatabase {
  DartvelDatabase(super.executor);
}
