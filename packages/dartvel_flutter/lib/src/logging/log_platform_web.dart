import 'package:dartvel_core/dartvel.dart' show DVLogConfig, DVLogFile;

/// A browser has no file to keep: its records stay in the in-process buffer
/// and the console for the life of the tab.
DVLogFile? dvDefaultLogFile(String appId, DVLogConfig config) => null;
bool dvLogHostedByTestRunner() => false;
String dvLogPlatformName() => 'web';
