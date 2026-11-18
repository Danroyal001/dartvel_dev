// Port of lib/source/line_info.dart (the part parsing uses).

/// The location of the beginnings of each line in a file.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct LineInfo {
    /// A list containing the offsets of the first character of each line in
    /// the source code.
    pub line_starts: Vec<i32>,
}

impl LineInfo {
    pub fn new(line_starts: Vec<i32>) -> LineInfo {
        if line_starts.is_empty() {
            panic!("lineStarts must be non-empty");
        }
        LineInfo { line_starts }
    }

    pub fn line_count(&self) -> usize {
        self.line_starts.len()
    }

    /// `getLocation(offset).lineNumber - 1`: the index of the line holding
    /// [offset].
    pub fn line_index(&self, offset: i32) -> usize {
        match self.line_starts.binary_search(&offset) {
            Ok(i) => i,
            Err(i) => i - 1,
        }
    }

    /// The offset of the first character on the line with the given
    /// (zero-based) index.
    pub fn get_offset_of_line(&self, line_number: usize) -> i32 {
        if line_number >= self.line_count() {
            panic!(
                "Invalid line number: {line_number}; must be between 0 and {}",
                self.line_count() - 1
            );
        }
        self.line_starts[line_number]
    }
}
