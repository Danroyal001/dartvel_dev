/// The column a tenant-scoped model's rows carry.
///
/// One definition, because the two things that use it are in different files
/// and neither would notice the other changing: the generator writes it into
/// the schema and into every predicate, and the migration adds it to a table
/// that predates the annotation. Two spellings is a migration that adds one
/// column and queries that read another, on a database that reports as
/// migrated.
library;

const String dvTenantColumn = 'dv_tenant';
