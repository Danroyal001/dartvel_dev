import 'dart:async';
/**
 * Only the first directive's comment is checked (`visitCompilationUnit`).
 */
import 'dart:math';

/** An extension type is not visited. */
extension type E(int i) {}

/** Checked. */
class C {
  /** Checked. */
  int f = 0;

  /** Checked. */
  void m(
    /** A parameter is not visited. */
    int p,
  ) {
    /** A local variable is not visited. */
    var v = p;
    /** A local function is checked through its preceding comment. */
    void local() {}
    // Only the first preceding comment is looked at.
    /** Not reported. */
    void local2() {}
    local();
    local2();
    print(v);
  }
}

/** Checked. */
enum En {
  /** Checked. */
  a,
}

void main() {
  print([Completer<void>(), max(1, 2), E(1)]);
}
