library dartvel_core.run;

/// The entry declarations retained from the application-entry prototype.
sealed class DVEntry {
  const DVEntry();
  const factory DVEntry.app() = DVAppEntry;
  const factory DVEntry.terminal() = DVTerminalEntry;
  const factory DVEntry.server({required DVServerRole role}) = DVServerEntry;
  const factory DVEntry.command(String name) = DVCommandEntry;
  const factory DVEntry.homeWidget({required DVHomeWidgetRequest request}) = DVHomeWidgetEntry;
  const factory DVEntry.background({required DVBackgroundTask task}) = DVBackgroundEntry;
  const factory DVEntry.push({required DVPushDelivery delivery}) = DVPushEntry;
  const factory DVEntry.worker(String task) = DVWorkerEntry;
  const factory DVEntry.embedded(String project) = DVEmbeddedEntry;
  const factory DVEntry.test() = DVTestEntry;
}

class const DVAppEntry() extends DVEntry;
class const DVTerminalEntry() extends DVEntry;
enum DVServerRole { all, web, worker, cron }
class const DVServerEntry({required final DVServerRole role}) extends DVEntry;
class const DVCommandEntry(final String name) extends DVEntry;
class const DVHomeWidgetRequest({required final String id}) {
  factory DVHomeWidgetRequest.fromArgs(List<String> args) => DVHomeWidgetRequest(id: args.isEmpty ? 'default' : args.first);
}
class const DVHomeWidgetEntry({required final DVHomeWidgetRequest request}) extends DVEntry;
class const DVBackgroundTask({required final String name});
class const DVBackgroundEntry({required final DVBackgroundTask task}) extends DVEntry;
class const DVPushDelivery({required final String token});
class const DVPushEntry({required final DVPushDelivery delivery}) extends DVEntry;
class const DVWorkerEntry(final String task) extends DVEntry;
class const DVEmbeddedEntry(final String project) extends DVEntry;
class const DVTestEntry() extends DVEntry;

enum DVEntryKind { app, terminal, server, command, homeWidget, background, push, worker, embedded, test }

/// Which kind of entry this is, the value an `@DVBoot(entries:)` names.
extension DVEntryKindOf on DVEntry {
  DVEntryKind get kind => switch (this) {
        DVAppEntry() => DVEntryKind.app,
        DVTerminalEntry() => DVEntryKind.terminal,
        DVServerEntry() => DVEntryKind.server,
        DVCommandEntry() => DVEntryKind.command,
        DVHomeWidgetEntry() => DVEntryKind.homeWidget,
        DVBackgroundEntry() => DVEntryKind.background,
        DVPushEntry() => DVEntryKind.push,
        DVWorkerEntry() => DVEntryKind.worker,
        DVEmbeddedEntry() => DVEntryKind.embedded,
        DVTestEntry() => DVEntryKind.test,
      };
}

/// A private startup function and its entry filter; the runtime passes its context.
class const DVBoot({final Set<DVEntryKind> entries = const <DVEntryKind>{},
    final DVEntry entry = const DVEntry.app(), final List<String> args = const <String>[]});

/// Optional existing Flutter application root. Pure Dartvel apps omit it.
class const DVAppRoot();
