// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: prefer_const_constructors

import 'package:dartvel_core/dartvel.dart';

/// Every model that declares a subject path, a retention or a
/// sensitive field, as the privacy walk sees it, over [database].
///
/// Generated from each `@DVModel(subject: ..., retain: ...)`.
List<DVPrivacyModel> dartvelPrivacyModels(DVDatabaseAdapter database) =>
    <DVPrivacyModel>[
    ];

/// Configures `DV.Privacy` over [database] from `DARTVEL_PRIVACY_KEY` in
/// [environment], and returns whether it did.
///
/// Called by the generated server. With the key unset nothing is configured
/// and `DV.Privacy` throws naming it; with the key set and no database the
/// server does not start, because an erasure with nothing to walk would
/// report success.
bool configureDartvelBackendPrivacy({
  required DVDatabaseAdapter? database,
  required Map<String, String> environment,
}) =>
    DVPrivacyRuntime.configureFromEnvironment(
      environment: environment,
      database: database,
      models: database == null
          ? const <DVPrivacyModel>[]
          : dartvelPrivacyModels(database),
    );
