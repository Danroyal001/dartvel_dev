// `InterfaceElementExtension.asEnumLikeClass` reads the values of the
// static const fields with `computeConstantValue()`, also for a class of
// another library (`Endian` of `dart:typed_data`).
import 'dart:typed_data';

void sdk(Endian e) {
  switch (e) {
    case Endian.big:
      break;
    default:
      break;
  }
  switch (e) {
    case Endian.little:
      break;
  }
}

class Local {
  final int i;
  const Local._(this.i);
  static const Local a = Local._(1);
  static const Local b = Local._(2);
  @deprecated
  static const Local oldB = Local._(2);
  static const Local c = Local._(3);
}

const Local alsoA = Local.a;

void local(Local l) {
  switch (l) {
    case alsoA:
      break;
  }
  switch (l) {
    case Local.a:
    case Local.oldB:
      break;
    default:
      break;
  }
}

// The subclass check compares `superclass` types with `==`: `Sub` extends
// `Generic<int>`, not `Generic<T>`, so `Generic` is still enum-like.
class Generic<T> {
  const Generic._();
  static const Generic<int> x = Generic._();
  static const Generic<String> y = Generic._();
  static const Generic<Object?> z = Generic._();
}

class Sub extends Generic<int> {
  const Sub() : super._();
}

class Plain {
  const Plain._();
  static const Plain p = Plain._();
  static const Plain q = Plain._();
}

class PlainSub extends Plain {
  const PlainSub() : super._();
}

void generic(Generic<Object?> g, Plain p) {
  switch (g) {
    default:
      break;
  }
  switch (p) {
    default:
      break;
  }
}
