// Port of rust/oracle/ast_dump.dart: the Rust side of the AST oracle.
//
// Writes, for every `.dart` file under the corpus roots, the syntax tree and
// parse diagnostics the Rust port produces, in exactly the format the Dart
// oracle writes for the analyzer, so the two outputs can be compared byte
// for byte.
//
// Usage: ast_dump [--bench=N] --out <dir> <root>...

fn main() {
    // Not ported yet: writes no dumps, so every file differs.
    eprintln!("ast_dump: not ported yet");
}
