// A part that its library does not include: upstream analyzes it as a
// library of its own (`kind.asLibrary`), so `double` is `dart:core`'s and
// the library's alias `Real` is not in scope.
part of 'integers.dart';

double orphan = 1;
Real notInScope = 2;
