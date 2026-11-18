// An explicit import of `dart:core` removes the implicit one: `double` is
// only `core.double` here.
import 'dart:core' as core;

core.double prefixed = 1;
double unprefixed = 2;
core.int whole = 3;
