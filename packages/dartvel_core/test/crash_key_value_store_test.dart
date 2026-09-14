// A crash store over a synchronous key-value store: what a browser has.
//
// The file store is the only persistent one, and it throws on the web by
// design. So a web build had nowhere a crash handler could write before the
// page went away, and recovering at the next launch was impossible there.
// localStorage is synchronous, which is the one property the handler needs.
//
// The silent failures: a record written by one page load and invisible to
// the next, a rate limit that restarts with every reload (which limits
// nothing in a reload loop), and a record cut short that is sent as though it
// were whole.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _Map implements DVCrashKeyValue {
  final Map<String, String> values = <String, String>{};

  @override
  String? read(String key) => values[key];

  @override
  void write(String key, String value) => values[key] = value;

  @override
  void delete(String key) => values.remove(key);

  @override
  Iterable<String> get keys => values.keys.toList();
}

DVCrashReport report(String id) => DVCrashReport(
      id: id,
      kind: DVCrashKind.fatal,
      errorType: 'StateError',
      message: 'boom',
      frames: const <DVCrashFrame>[DVCrashFrame(function: 'main')],
      fingerprint: 'f',
      context: const DVCrashContext(release: '1.0.0', installId: 'i'),
      occurredAt: DateTime.utc(2026, 9, 14),
    );

void main() {
  test('a record written by one load is pending in the next', () {
    final _Map storage = _Map();
    DVKeyValueCrashStore(storage).writeSync(report('a'));

    final List<DVCrashStoreEntry> pending =
        DVKeyValueCrashStore(storage).pending();
    expect(pending.map((DVCrashStoreEntry e) => e.id), <String>['a']);
    expect(pending.single.report!.message, 'boom');
  });

  test('keys that are not its own are not read as records', () {
    final _Map storage = _Map()..values['theme'] = 'dark';
    DVKeyValueCrashStore(storage).writeSync(report('a'));

    expect(DVKeyValueCrashStore(storage).pending(), hasLength(1));
  });

  test('a record cut short is pending and truncated, never whole', () {
    final _Map storage = _Map();
    final DVKeyValueCrashStore store = DVKeyValueCrashStore(storage)
      ..writeSync(report('a'));
    final String key =
        storage.values.keys.firstWhere((String k) => k.endsWith('a'));
    storage.values[key] = storage.values[key]!.substring(0, 20);

    expect(store.pending().single.truncated, isTrue);
  });

  test('sent notes survive a reload and remove clears both', () {
    final _Map storage = _Map();
    DVKeyValueCrashStore(storage)
      ..writeSync(report('a'))
      ..markSent('a');

    final DVKeyValueCrashStore next = DVKeyValueCrashStore(storage);
    expect(next.isSent('a'), isTrue);
    next.remove('a');
    expect(next.isSent('a'), isFalse);
    expect(next.pending(), isEmpty);
  });

  test('the per-release count survives a reload', () {
    final _Map storage = _Map();
    expect(DVKeyValueCrashStore(storage).countCrash('1.0.0'), 1);
    expect(DVKeyValueCrashStore(storage).countCrash('1.0.0'), 2);
    expect(DVKeyValueCrashStore(storage).countCrash('1.1.0'), 1);
  });

  test('two stores with different prefixes do not see each other', () {
    final _Map storage = _Map();
    DVKeyValueCrashStore(storage, prefix: 'one.').writeSync(report('a'));

    expect(DVKeyValueCrashStore(storage, prefix: 'two.').pending(), isEmpty);
  });
}
