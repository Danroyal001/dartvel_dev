/// The Dartvel Cloud protocol, shared by the CLI and the Cloud service.
///
/// A library of its own rather than part of `dartvel.dart`: an application
/// never talks to Dartvel Cloud, and nothing in it should arrive in one.
library;

export 'src/cloud/cloud_protocol.dart';
