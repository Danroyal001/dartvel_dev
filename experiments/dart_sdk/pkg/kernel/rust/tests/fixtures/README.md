Binary fixtures for `tests/small_components.rs` (small enough for Miri):

- `empty.dill`: upstream's `BinaryPrinter` writing an empty `Component`
  (this checkout's `pkg/kernel`, format 141).
- `hello-unlinked.dill`: `tests/kernel_corpus/hello.dart` compiled by this
  checkout's `pkg/vm/bin/gen_kernel.dart --no-link-platform` against the VM
  platform `oracle/build_corpus.dart` builds.
