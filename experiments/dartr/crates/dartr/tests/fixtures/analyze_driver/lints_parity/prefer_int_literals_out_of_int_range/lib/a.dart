// The analyzer runs on the Dart VM, where `double.truncate()` saturates to
// the 64-bit int range, and `double != int` compares against
// `int.toDouble()`. A whole double outside that range is not reported.
const double a = 1e300;
const double b = -1.7976931348623157e+308;
const double c = 1e19;
const double d = 9.2e18;
const double e = 9223372036854775808.0;
const double f = -9223372036854775808.0;
const double g = 9.3e18;
const double h = 3.0;
const List<double> l = <double>[1e300, 2.0, 1e100];
