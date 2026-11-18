// Fixture for null-aware member accesses `r?.m(...)` and `r?.p` and for
// cascade sections `r..m(...)`, `r..p`, `r?..m(...)` in `--members`: on
// nullable and non-nullable receivers, in null-shorting chains (`a?.b.c`,
// `a?.b?.c`, `a?.b.m()`), where the chain ends (an argument, an operand,
// parentheses, a variable's initializer, a return, an interpolation), on
// `this`, on extension members, and in cascade sections with chains after
// the first selector. Some lines are compile-time errors or warnings on
// purpose.

class Box {
  final int value;
  Box? next;
  Box(this.value);

  int get size => value;
  String describe(int precision) => '';
  Box child() => this;
  Box? maybe() => next;
  void clear() {}
  T pick<T>(T value) => value;
  int _hidden() => 0;
  var inferred = 1;

  void onThis() {
    this?.size;
    this..clear()..size;
  }
}

extension BoxTools on Box {
  int get doubled => value * 2;
  int twice(int x) => x * 2;
}

extension NullableTools on Box? {
  bool get isMissing => this == null;
}

// A variable read followed by `?.` may be promoted by flow analysis, so the
// receivers here are member accesses on a holder (and implicit `this`).
class Holder {
  Box? box;
  Box sure = Box(0);
  String? text;
  List<int>? numbers;

  void implicit() {
    box?.size;
    text?.length;
    box?.child().value;
  }
}

void nullAware(Holder holder) {
  holder.box?.size;
  holder.box?.value;
  holder.box?.describe(2);
  holder.box?.child();
  holder.box?.describe;
  holder.box?.next;
  holder.box?.maybe();
  holder.sure?.size;
  holder.sure?.describe(1);
  holder.text?.length;
  holder.text?.toUpperCase();
  holder.text?.substring(1);
  holder.numbers?.length;
  holder.numbers?.first;
  holder.box?.doubled;
  holder.box?.twice(3);
  holder.box?.isMissing;
  holder.box?.hashCode;
  holder.box?.toString();
}

void chains(Holder holder) {
  holder.box?.child().size;
  holder.box?.child().describe(4);
  holder.box?.next?.size;
  holder.box?.maybe()?.child().value;
  holder.box?.child().child().child();
  holder.text?.trim().length;
  print(holder.box?.size);
  var size = holder.box?.size;
  int? declared = holder.box?.child().size;
  (holder.box?.child()).hashCode;
  '${holder.box?.size}';
  (holder.box?.size);
  [holder.box?.size, holder.text?.length];
  holder.box?.size == 1;
  // The receiver of an assignment target continues the chain.
  holder.box?.child().next = null;
  holder.box?.child().next ??= Box(0);
  holder.box?.child()..clear();
  holder.box?..clear()..size;
  holder.box?..describe(3);
  holder.box?._hidden();
  holder.box?.pick(1);
  holder.box?.pick<int>(1);
  holder.box?.inferred;
  holder.numbers?[0];
}

void variables(Box? box, Box sure, String? text, List<int>? numbers) {
  box?.size;
  box?.value;
  box?.describe(2);
  box?.child();
  box?.describe;
  box?.next;
  box?.maybe();
  sure?.size;
  sure?.describe(1);
  text?.length;
  text?.toUpperCase();
  text?.substring(1);
  numbers?.length;
  numbers?.first;
  box?.doubled;
  box?.twice(3);
  box?.isMissing;
  box?.hashCode;
  box?.toString();

  // Chains: the whole chain is nullable, the inner accesses are not.
  box?.child().size;
  box?.child().describe(4);
  box?.next?.size;
  box?.maybe()?.child().value;
  box?.child().child().child();
  text?.trim().length;

  // Where a chain ends.
  print(box?.size);
  var size = box?.size;
  int? declared = box?.child().size;
  (box?.child()).hashCode;
  '${box?.size}';
  (box?.size);
  [box?.size, text?.length];
  box?.size == 1;

  // Left out: private, generic, inferred, type arguments, null-aware index.
  box?._hidden();
  box?.pick(1);
  box?.pick<int>(1);
  box?.inferred;
  numbers?[0];
}

int? returned(Holder holder) => holder.box?.size;

void cascades(Box box, Box? maybe, StringBuffer buffer, List<int> list) {
  box..clear();
  box..size;
  box..describe(1)..child()..size;
  box..child().size;
  box..child().describe(2);
  box..next?.size;
  box..doubled..twice(2);
  maybe?..clear()..size;
  maybe?..describe(3);
  buffer..write('a')..writeln(1)..length;
  list..add(1)..addAll([2])..length;
  var built = Box(1)..clear()..child();
  print(Box(2)..size);
  // An integer literal target takes the cascade's context: a double here.
  double fromLiteral = 1..toString();
  0..isEven;
  box
    ..value
    ..next
    ..maybe();

  // Left out: assignments, index sections, private and generic members.
  box..next = null;
  list..[0] = 1;
  list..[0];
  box.._hidden();
  box..pick(1);
}
