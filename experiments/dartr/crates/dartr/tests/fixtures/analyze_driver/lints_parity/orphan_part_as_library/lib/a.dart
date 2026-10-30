// `b.dart` is `part of` this library, which does not include it, and
// `c.dart` imports it. Dart analyzes the orphan part as a library of its own
// (`AnalysisDriver._analyzeFile`: `kind.library ?? kind.asLibrary`), while
// `c.dart` still sees a part.
void main() {}
