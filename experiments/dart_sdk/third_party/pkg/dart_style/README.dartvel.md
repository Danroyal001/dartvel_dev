# Pinned dart_style source

This directory vendors dart-lang/dart_style at
`76978d23bfb3d225c81ce3f119ab7055a2a57136`, the revision named by
`experiments/dart_sdk/DEPS` (`dart_style_rev`). The SDK checkout did not include
its DEPS-managed third_party packages. Source was retrieved from
https://github.com/dart-lang/dart_style/archive/76978d23bfb3d225c81ce3f119ab7055a2a57136.tar.gz.

Upstream sources, tests, README and license are unchanged. Additions are this
file and `rust/`. The Rust port is experimental and incomplete; it does not
provide a Dart formatter yet. See `rust/README.md` for measured status.
