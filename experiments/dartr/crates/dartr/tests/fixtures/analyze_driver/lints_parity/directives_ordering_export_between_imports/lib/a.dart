// Dart checks "exports after imports" before "sort alphabetically" and
// reports each directive once (`lintedNodes`), so an export between imports
// that is also out of alphabetical order gets the export message.
import 'dart:async';
import 'package:p/c.dart';
import 'c.dart' as c2;
export 'd.dart';
import 'b.dart';
export 'c.dart';
import 'a.dart' as self;
import 'package:p/b.dart' as b2;
export 'dart:async';

void f() => [Future, c, c2.c, b, self.f, b2.b];
