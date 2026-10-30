// A type parameter is erased to itself promoted to its erased bound
// (`EraseNonJSInteropTypes.visitTypeParameterType`), not to the bound.
import 'dart:js_interop';

extension type User(JSObject _) implements JSObject {}

class C<T extends JSAny> {
  final T t;
  final T u;
  C()
    : t = JSObject() as T,
      u = JSObject() as T;
}

T asT<T extends JSAny>() => JSObject() as T;
T? asNullableT<T extends JSAny?>(JSAny? a) => a as T?;
T asObjectT<T extends JSObject>(JSObject o) => o as T;
T asAnyT<T extends JSAny>(JSAny a) => a as T;
T asDartT<T extends Object>(JSObject o) => o as T;
bool isT<T extends JSAny>(JSObject o) => o is T;
bool isAnyT<T extends JSAny>(JSAny a) => a is T;
bool isUserT<T extends User>(JSObject o) => o is T;
JSObject fromT<T extends JSAny>(T t) => t as JSObject;
bool tIsObject<T extends JSAny>(T t) => t is JSObject;
U asU<T extends JSAny, U extends T>(T t) => t as U;
