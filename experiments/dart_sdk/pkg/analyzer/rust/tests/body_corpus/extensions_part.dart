// Part of extensions.dart: the part sees the extensions its library declares
// and imports.
part of 'extensions.dart';

extension PartOnString on String {
  int get partLength => length;
}

void inPart(String s, int i) {
  s.importedLength;
  s.partLength;
  s.ownLength;
  i.prefixedTwice;
}
