/** The first directive's comment is checked. */
library;

/** A second directive is not. */
import 'dart:async';

/** Checked. */
typedef F = void Function();

/** Checked. */
mixin M {}

/** Checked. */
extension X on int {}

/** Checked. */
int top = 0;

void main() {
  print(Completer<void>());
}
