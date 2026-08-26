/// Turning a Dart string into the bytes the Rust side reads.
///
/// Every `FfiStr` handed across the boundary is decoded with
/// `std::str::from_utf8`, so the bytes have to be UTF-8. Building them from
/// `String.codeUnits` gives UTF-16, and the two agree only for ASCII — which
/// is why passing a path, a CORS origin or a host worked in every test anyone
/// wrote.
///
/// The two failures differ in how loud they are. A character in the Latin-1
/// range emits a single byte that is not a valid UTF-8 sequence, and Rust
/// rejects the whole string. A character above U+00FF emits a code unit larger
/// than a byte, and `Uint8List.fromList` truncates rather than throwing: a
/// static directory of `/srv/中文` arrives as `/srv/--`, which is a path that
/// does not exist, so files stop being served and nothing anywhere says why.
library;

import 'dart:convert';
import 'dart:typed_data';

/// [value] as the UTF-8 bytes the Rust side expects.
Uint8List dvFfiBytes(String value) => Uint8List.fromList(utf8.encode(value));
