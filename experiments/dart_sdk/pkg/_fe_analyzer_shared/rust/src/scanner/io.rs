// Port of lib/src/scanner/io.dart.
//
// Upstream takes a `Uri`; a file URI's path is what is read, so here the
// argument is the path. The asynchronous `readBytesFromFile` has no
// counterpart: nothing in this crate is asynchronous.

use std::path::Path;

pub fn read_bytes_from_file_sync(path: &Path) -> std::io::Result<Vec<u8>> {
    std::fs::read(path)
}
