/// The column a tenant-scoped model's rows carry.
///
/// Defined in dartvel_core, beside the migration a web-server binary runs
/// when it starts, and re-exported here for the generators: one definition,
/// because the generator writes it into the schema and every predicate and
/// the migration adds it to a table that predates the annotation.
library;

export 'package:dartvel_core/dartvel.dart' show dvTenantColumn;
