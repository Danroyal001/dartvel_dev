/// Crash symbolication for a server: decoding obfuscated Dart stacks.
///
/// Its own entry point because the decoder reads files through `dart:io`, so
/// it cannot be part of `core.dart`, which an application that only calls a
/// remote API imports and compiles for a browser.
library dartvel_shelf.symbols;

export 'src/native_stack_symbolizer.dart' show DVNativeStackSymbolizer;
