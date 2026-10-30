// `element.metadata.hasOptionalTypeArgs`: a raw reference to a class or a
// type alias annotated with `@optionalTypeArgs` is not reported.
import 'package:meta/meta.dart';

@optionalTypeArgs
abstract class Parser<R> {
  bool isEqualTo(Parser other) => identical(this, other);
}

@optionalTypeArgs
typedef Callback<T> = void Function(T);

typedef Plain<T> = List<T>;

class Box<T> {}

void f(Parser p, Callback c, Plain l, Box b, List<Box> boxes) {}
