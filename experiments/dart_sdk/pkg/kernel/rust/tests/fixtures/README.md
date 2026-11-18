Binary fixtures for `tests/small_components.rs` (small enough for Miri):

- `empty.dill`: upstream's `BinaryPrinter` writing an empty `Component`
  (this checkout's `pkg/kernel`, format 141).
- `hello-unlinked.dill`: `tests/kernel_corpus/hello.dart` compiled by this
  checkout's `pkg/vm/bin/gen_kernel.dart --no-link-platform` against the VM
  platform `oracle/build_corpus.dart` builds.
- `not-chain-4202.dill`, `not-chain-4203.dill`: `hello-unlinked.dill` with
  `main`'s statement replaced by `!!!...!true;` nested 4202 and 4203 deep
  (written by `examples/not_chain.rs`).
  Upstream's oracle (Dart 3.15.0-145.0.dev, JIT, as `oracle/damage.dart`
  runs it) writes the first and throws `Stack Overflow` on the second, on
  every run.
- `json_roundtrip-unlinked.dill`: `tests/kernel_corpus/json_roundtrip.dart`
  compiled the same way as `hello-unlinked.dill` (`oracle/build_corpus.dart`
  makes it as `json_roundtrip-unlinked.part`). Upstream cannot write it
  (its import of `dart:convert` is not in the component), which the damage
  oracle compares too.
