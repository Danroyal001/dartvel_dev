/// The arguments every headless Chrome this CLI starts is launched with.
///
/// One list because it had already drifted: three launch sites, each with its
/// own hand-written pair of flags, so a fix applied to one reached none of the
/// others.
library;

/// Flags for a headless Chrome, in the environments this actually runs in.
///
/// `--no-sandbox` and `--disable-setuid-sandbox` are the usual pair for a
/// container, where the sandbox has no user namespace to work with.
///
/// `--disable-dev-shm-usage` is the one that was missing everywhere, and it
/// is not a tuning flag. A container gives `/dev/shm` 64 megabytes -- Docker's
/// default, so every Codespace, every Actions container job and most CI --
/// and Chrome puts its shared memory there. It runs out during startup and
/// dies before printing the DevTools address it was asked for, so the caller
/// times out waiting and reports that no browser could be found. There is a
/// browser. It cannot allocate.
///
/// The cost of that is a failed build rather than a slow one: `dartvel build
/// web` refuses when the semantics capture comes back empty, because four
/// pages with no crawler-visible content is worse than stopping. The refusal
/// is right and it was firing on machines where the only thing wrong was a
/// flag. Pointing the shared memory at the ordinary temp directory costs
/// nothing on a machine that never needed it.
const List<String> dvChromeLaunchArgs = <String>[
  '--no-sandbox',
  '--disable-setuid-sandbox',
  '--disable-dev-shm-usage',
];
