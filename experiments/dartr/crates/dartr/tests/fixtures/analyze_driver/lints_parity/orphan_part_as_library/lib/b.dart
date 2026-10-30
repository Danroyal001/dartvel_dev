part of 'a.dart';

const x = 26;
final y = 'a';
Object o = 1;

void f() {
  int i = x;
  print(i + 1);
  dynamic d = o;
  d.foo();
  String s = o;
  print(s);
}
