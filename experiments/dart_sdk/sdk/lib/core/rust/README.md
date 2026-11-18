# `dart:core` in Rust

A file-by-file Rust port of parts of `dart:core` (`sdk/lib/core`), starting
with what the kernel binary reader port (`pkg/kernel/rust`) needs to
reproduce upstream exactly: `Uri.parse(s).toString()`, which normalises the
URIs a kernel file carries, and the text of everything that call can throw.
The port is a drop-in: for every input string it gives what the Dart VM
gives, code unit for code unit, or throws what the VM throws, with the same
`toString()`. It does not improve on upstream, bugs included (an `https`
rewrite that subtracts 3 instead of 4, an IPvFuture error whose source and
offset are inside its message, a ninth IPv6 part after a wildcard that runs
off a 16-byte list).

Each file under `src/` ports the Dart file of the same name in `..` and names
it in its first line; `lib.rs` and the test say they are not ports.

| Rust | Dart | What |
|---|---|---|
| `src/uri.rs` | `uri.dart` | `Uri.parse` with `data:` URIs (`UriData._parse`, `_computeUri`), the `_scan` state machine and `_scannerTables`, `_charTables`, `_SimpleUri`'s `file`/`http`/`https` rewrites, `_Uri.notSimple` and the `_make*`, `_normalize*`, `_removeDotSegments`, `_normalizeRelativePath`, `_escapeScheme`, IPv4/IPv6/IPvFuture validation it uses, `_Uri._initializeText` |
| `src/exceptions.rs` | `exceptions.dart` | `FormatException.toString()`: the excerpt, `...` on long lines, line and character numbers, the caret |
| `src/errors.rs` | `errors.dart` | `RangeError.range(...).toString()` and `IndexError.toString()`, which `codeUnitAt`, `substring`, `startsWith`, `replaceRange` and `Uint8List` writes throw on the parse path |

Three helpers from other libraries sit at the end of `uri.rs`, because only
this path uses them: the VM's `int.tryParse` (for the port: whitespace
trimming, signs, `0x`, the 64-bit overflow rules, hex up to 2^64 - 1 wrapping),
`Base64Codec.normalize` from `dart:convert` (for `;base64,` data) and
`hexDigitValue` / `parseHexByte` from `dart:_internal`.

Strings are Dart strings, `Vec<u16>` of UTF-16 code units with lone
surrogates kept. Names keep upstream's spelling so the port reads against
`uri.dart` line by line. `#![forbid(unsafe_code)]`, no dependencies.

## API

```rust
// Exact: Ok = toString() of the parsed Uri, Err = toString() of what it throws.
pub fn dart_core::uri::parseUriToStringUtf16(text: &[u16]) -> Result<Vec<u16>, Vec<u16>>;
// The same, with the thrown text as a Rust String (a lone surrogate in it
// becomes U+FFFD, as Dart's UTF-8 encoder prints it).
pub fn dart_core::uri::parseUriToString(text: &[u16]) -> Result<Vec<u16>, String>;
// Over WTF-8: input decoded as pkg/kernel's _decodeWtf8, result encoded as
// its _writeWtf8. A sequence cut short is refused (not a Dart message).
pub fn dart_core::uri::parseUriToStringWtf8(bytes: &[u8]) -> Result<Vec<u8>, String>;
pub fn dart_core::uri::decodeWtf8(bytes: &[u8]) -> Result<Vec<u16>, String>;
pub fn dart_core::uri::writeWtf8(source: &[u16]) -> Vec<u8>;
```

## The oracle

`tests/uri_oracle.rs` builds the inputs, runs them through
`oracle/uri_oracle.dart` on the Dart VM and through the port, and requires
the same line for every input: `ok <Uri.parse(input).toString()>` or
`error <thrown.toString()>`. Inputs and results travel in a line-safe escape
format (U+0020..U+007E except `\` as themselves, any other code unit as `\`
and four hex digits), so controls, non-ASCII and lone surrogates survive.

The VM is Dart 3.15.0-145.0.dev (`flutter-main`'s). Its `uri.dart`,
`exceptions.dart` and `errors.dart` were diffed against this fork's: the only
difference is in `UriData._uriEncodeBytes` (when a non-byte value is
reported), which `Uri.parse` does not call. So matching the VM is matching
this fork's source.

### Inputs

- `tests/seeds/kernel_corpus_uris.txt`: 1,365 URI-like strings
  (`file:`, `package:`, `dart:`, `org-dartlang-sdk:`, `http(s):`, `data:`)
  pulled out of the kernel corpus's `.dill` files
  (`target/kernel_oracle/corpus`), local paths replaced. They are cut out of
  the string table, so some run into the next string, which makes them
  realistic damage too.
- `tests/seeds/corelib_uri_test_literals.txt`: the 1,024 distinct string
  literals of `tests/corelib/uri_*_test.dart` and `data_uri_test.dart`,
  Dart escapes decoded (`oracle/extract_literals.pl`).
- 135 hand-picked edge cases in the test (ports at the 64-bit limits,
  IPv6 and IPvFuture forms, zone IDs, base64 padding, long inputs for the
  excerpt, line breaks, lone surrogates).
- Every seed damaged at up to `URI_POSITIONS` (24) positions (all of a short
  seed's): cut short from either end, one code unit flipped with each of 11
  masks (0x01, 0x04, 0x10, 0x20, 0x40, 0x60, 0x80, 0xFF, 0x2000, 0xD800,
  0xDC00, giving controls, non-ASCII and surrogates), and each of 18
  insertions (`%` `\` `[` `]` `:` `@` `?` `#` space `/` `.` U+00E9 U+2028,
  a lone lead and trail surrogate, `%4`, `../`, `//`).
- `URI_RANDOM` (60,000) random strings over the characters that matter to
  the scanner, half of them after a scheme prefix.

### Numbers

| | |
|---|---|
| Inputs (distinct) | 1,240,813 |
| Parsed | 988,036 |
| Threw | 252,777 |
| Differences | 0 |
| Run time | about 4 minutes (the port in release mode; most of it is the VM) |

A wider run (`URI_POSITIONS=64 URI_RANDOM=300000`) passed as well: 2,455,388
inputs (2,061,176 parsed, 394,212 threw), 0 differences, 7 minutes. The 13
unit tests pass under Miri.

```sh
cd experiments/dart_sdk
DART=/path/to/dart ~/heavy.sh cargo test --release -p dart_core --test uri_oracle
cargo test -p dart_core --lib                  # unit tests
cargo +nightly miri test -p dart_core --lib    # unit tests under Miri
```
