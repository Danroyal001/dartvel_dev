// `_ValidUseVisitor.visitRethrowExpression` assigns `hasValidUse =
// _canRethrow`, and `_canRethrow` stays false after the first nested catch
// clause: a later `rethrow` undoes an earlier valid use.
Future<void> a(Future<void> Function() g) async {
  try {
    await g();
  } catch (error) {
    try {
      await g();
    } catch (e) {
      print(e);
    }
    if (error is int) throw StateError('$error');
    rethrow;
  }
}

Future<void> b(Future<void> Function() g) async {
  try {
    await g();
  } catch (error) {
    if (error is int) throw StateError('$error');
    rethrow;
  }
}

Future<void> c(Future<void> Function() g) async {
  try {
    await g();
  } catch (error) {
    if (error is int) rethrow;
    try {
      await g();
    } catch (e) {
      print(e);
    }
  }
}

Future<void> d(Future<void> Function() g) async {
  try {
    await g();
  } catch (error) {
    try {
      await g();
    } catch (e) {
      print(e);
    }
    if (error is String) rethrow;
    throw StateError('$error');
  }
}
