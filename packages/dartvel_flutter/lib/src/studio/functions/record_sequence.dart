// The order entries were written in, for stores that list by time.
//
// Two entries in the same instant -- an approval and its audit entry, or a
// test's fixed clock -- used to keep their order through SQLite's rowid,
// which PostgreSQL does not have and a document database has no equivalent
// of. A store now writes this with each entry and sorts on it after time.

int _last = 0;

/// A number larger than any this process has handed out, and than the clock
/// in microseconds, so a restarted process carries on above the last one.
int dvNextSequence() {
  final int now = DateTime.now().microsecondsSinceEpoch;
  _last = now > _last ? now : _last + 1;
  return _last;
}
