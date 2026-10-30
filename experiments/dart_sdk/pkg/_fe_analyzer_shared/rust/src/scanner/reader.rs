// Port of lib/src/scanner/reader.dart.
//
// Strings are UTF-16 code units, as Dart's are.

/// An object used by the scanner to read the characters to be scanned.
pub trait CharacterReader {
    /// The current offset relative to the beginning of the source. Returns
    /// the initial offset if the scanner has not yet scanned the source code,
    /// and one (1) past the end of the source code if the entire source code
    /// has been scanned.
    fn offset(&self) -> i32;

    /// Set the current offset relative to the beginning of the source.
    fn set_offset(&mut self, offset: i32);

    /// Advance the current position and return the character at the new
    /// current position.
    fn advance(&mut self) -> i32;

    /// Return the source to be scanned.
    fn get_contents(&self) -> Vec<u16>;

    /// Return the substring of the source code between the [start] offset
    /// and the modified current position. The current position is modified
    /// by adding the [end_delta], which is the number of characters after
    /// the current location to be included in the string, or the number of
    /// characters before the current location to be excluded if the offset
    /// is negative.
    fn get_string(&self, start: i32, end_delta: i32) -> Vec<u16>;

    /// Return the character at the current position without changing the
    /// current position.
    fn peek(&self) -> i32;
}

/// A [CharacterReader] that reads characters from a character sequence.
pub struct CharSequenceReader {
    /// The sequence from which characters will be read.
    sequence: Vec<u16>,

    /// The number of characters in the string.
    string_length: i32,

    /// The index, relative to the string, of the next character to be read.
    char_offset: i32,
}

impl CharSequenceReader {
    pub fn new(sequence: Vec<u16>) -> CharSequenceReader {
        let string_length = sequence.len() as i32;
        CharSequenceReader {
            sequence,
            string_length,
            char_offset: 0,
        }
    }
}

impl CharacterReader for CharSequenceReader {
    fn offset(&self) -> i32 {
        self.char_offset - 1
    }

    fn set_offset(&mut self, offset: i32) {
        self.char_offset = offset + 1;
    }

    fn advance(&mut self) -> i32 {
        if self.char_offset >= self.string_length {
            return -1;
        }
        let c = self.sequence[self.char_offset as usize] as i32;
        self.char_offset += 1;
        c
    }

    fn get_contents(&self) -> Vec<u16> {
        self.sequence.clone()
    }

    fn get_string(&self, start: i32, end_delta: i32) -> Vec<u16> {
        self.sequence[start as usize..(self.char_offset + end_delta) as usize].to_vec()
    }

    fn peek(&self) -> i32 {
        if self.char_offset >= self.string_length {
            return -1;
        }
        self.sequence[self.char_offset as usize] as i32
    }
}

/// A [CharacterReader] that reads characters from a character sequence, but
/// adds a delta when reporting the current character offset so that the
/// character sequence can be a subsequence from a larger sequence.
pub struct SubSequenceReader {
    base: CharSequenceReader,

    /// The offset from the beginning of the file to the beginning of the
    /// source being scanned.
    offset_delta: i32,
}

impl SubSequenceReader {
    pub fn new(sequence: Vec<u16>, offset_delta: i32) -> SubSequenceReader {
        SubSequenceReader {
            base: CharSequenceReader::new(sequence),
            offset_delta,
        }
    }
}

impl CharacterReader for SubSequenceReader {
    fn offset(&self) -> i32 {
        self.offset_delta + self.base.offset()
    }

    fn set_offset(&mut self, offset: i32) {
        self.base.set_offset(offset - self.offset_delta);
    }

    fn advance(&mut self) -> i32 {
        self.base.advance()
    }

    fn get_contents(&self) -> Vec<u16> {
        self.base.get_contents()
    }

    fn get_string(&self, start: i32, end_delta: i32) -> Vec<u16> {
        self.base.get_string(start - self.offset_delta, end_delta)
    }

    fn peek(&self) -> i32 {
        self.base.peek()
    }
}
