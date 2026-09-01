/// Replacing a file something may have mapped.
///
/// The build hook wrote the compiled library with File.copy, which opens the
/// destination and truncates it. When a process has that file mapped -- which
/// is what dlopen does, and what the native-symbols test does in the same run
/// -- truncating the inode pulls the backing out from under the mapping.
/// Touching those pages raises SIGBUS with BUS_ADRERR, and the VM aborted at
/// exit with code 134 after every test had already passed.
///
/// CI found it and a local run did not, because the crash needs cargo present
/// so the hook actually rebuilds.
library dartvel_shelf.atomic_copy;

import 'dart:io';

/// Copies [source] over [destination], replacing rather than overwriting.
///
/// Writes a sibling temporary and renames it into place. A rename swaps the
/// directory entry: anything still holding the old file keeps the old inode,
/// which stays alive until the last reference goes. Writing through would
/// destroy what those references point at.
///
/// The temporary is a sibling deliberately -- rename is only atomic within a
/// filesystem, and a temp directory is often on a different one, where the
/// call degrades to a copy and the guarantee is lost.
Future<void> dvAtomicCopy(File source, String destination) async {
  final File target = File(destination);
  await target.parent.create(recursive: true);

  final File staged = File('$destination.dvtmp-$pid');
  try {
    await source.copy(staged.path);
    await staged.rename(destination);
  } on Object {
    // A failed rename must not leave a half-written sibling next to the
    // library, where the next build could mistake it for output.
    if (staged.existsSync()) {
      try {
        staged.deleteSync();
      } on Object {
        // Nothing useful to do; the original error is the one that matters.
      }
    }
    rethrow;
  }
}
