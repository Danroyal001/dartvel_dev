// Contexts where parsed literals might have no resolved static type.
import 'dart:async' show Future;
export 'dart:async' show Future;
part 'literal_part.dart';

@Deprecated('reason')
class C {
  final String text;
  const C([this.text = 'default']);
  String get value => 'value';
}

const object = C('argument');
const symbol = #C.value;
String text(bool flag) => flag ? 'yes' : 'no';
void nested() {
  var values = <Object?>[true, false, null, 0.0, -1.5, #foo, r'raw'];
  var strings = '${'inner'} ${true} ${null}';
  var adjacent = 'left' r'right';
  return;
  var unreachable = false;
}
