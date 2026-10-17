import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

/// @DVBoot functions run in every entry their code can run in, not only the
/// Flutter app: a web server, a worker and a cron process boot through the
/// same runner, before they serve, and a headless application has no UI to
/// wait for.
void main() {
  setUp(dvResetBootForTest);

  test('steps run in order, filtered by the entry that started', () async {
    final List<String> ran = <String>[];
    final List<DVBootStep> steps = <DVBootStep>[
      DVBootStep(run: (_) => ran.add('everywhere')),
      DVBootStep(entries: const <DVEntryKind>{DVEntryKind.app}, run: (_) => ran.add('app only')),
      DVBootStep(entries: const <DVEntryKind>{DVEntryKind.server}, run: (_) async => ran.add('server only')),
    ];
    await dvRunBoot(steps, const DVBoot(entry: DVEntry.server(role: DVServerRole.web)));
    expect(ran, <String>['everywhere', 'server only']);
  });

  test('a process boots once', () async {
    int runs = 0;
    final List<DVBootStep> steps = <DVBootStep>[DVBootStep(run: (_) => runs++)];
    await dvRunBoot(steps, const DVBoot());
    await dvRunBoot(steps, const DVBoot());
    expect(runs, 1);
  });

  test('every entry names its kind', () {
    expect(const DVEntry.app().kind, DVEntryKind.app);
    expect(const DVEntry.server(role: DVServerRole.worker).kind, DVEntryKind.server);
    expect(const DVEntry.worker('mail').kind, DVEntryKind.worker);
    expect(const DVEntry.command('seed').kind, DVEntryKind.command);
  });

  test('the step receives the arguments the entry was started with', () async {
    List<String>? seen;
    await dvRunBoot(<DVBootStep>[DVBootStep(run: (boot) => seen = boot.args)],
        const DVBoot(args: <String>['--role', 'cron']));
    expect(seen, <String>['--role', 'cron']);
  });
}
