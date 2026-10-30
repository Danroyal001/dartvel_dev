// An annotation's arguments correspond to the constructor's parameters by
// name, not by the index of the (name-sorted) function type parameter.
class L {
  final String path;
  final List<int> headers;
  const L({this.path = '', this.headers = const []});
}

class K {
  final String path;
  final int n;
  final bool b;
  const K(this.n, {this.path = '', this.b = false});
}

class I {
  final String path;
  final List<int> n;
  const I({this.n = const [], this.path = ''});
}

class Base {
  final String path;
  final bool optionalBody;
  final Map<String, String> headers;
  const Base({this.optionalBody = false, this.path = '', this.headers = const {}});
}

class Get extends Base {
  const Get({super.optionalBody = true, super.path, super.headers});
}

@L(path: '')
void a() {}

@L(headers: [])
void b() {}

@K(1, path: '', b: false)
void c() {}

@I(path: '')
void d() {}

abstract class S {
  @Get(path: '')
  void e();

  @Get(optionalBody: true, headers: {})
  void f();
}
