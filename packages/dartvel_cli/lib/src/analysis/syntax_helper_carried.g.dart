// The Rust syntax helper this CLI carries, written by
// `dart tool/embed_syntax_helper.dart` when a release binary is built.
//
// In the repository, and so in the package on pub.dev, it carries none: a
// CLI run from source parses in Dart. Never commit the output of the tool.

/// The helper program for the platform this CLI was built for, gzipped and
/// base64-encoded, or null when this CLI carries none.
const String? dvCarriedSyntaxHelper = null;

/// The SHA-256 of the helper program, in hexadecimal.
const String dvCarriedSyntaxHelperSha256 = '';
