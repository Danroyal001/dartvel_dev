// Port of flutter/fml/base32.h and flutter/fml/base32.cc.

pub struct BitConverter<const FROM_LENGTH: i32, const TO_LENGTH: i32, const BUFFER_LENGTH: i32> {
    buffer_: i32,
    lower_free_bits_: i32,
}

impl<const FROM_LENGTH: i32, const TO_LENGTH: i32, const BUFFER_LENGTH: i32> Default
    for BitConverter<FROM_LENGTH, TO_LENGTH, BUFFER_LENGTH>
{
    fn default() -> Self {
        Self::new()
    }
}

impl<const FROM_LENGTH: i32, const TO_LENGTH: i32, const BUFFER_LENGTH: i32>
    BitConverter<FROM_LENGTH, TO_LENGTH, BUFFER_LENGTH>
{
    const K_MASK: i32 = {
        assert!(BUFFER_LENGTH >= 2 * FROM_LENGTH);
        assert!(BUFFER_LENGTH >= 2 * TO_LENGTH);
        assert!(BUFFER_LENGTH < (std::mem::size_of::<i32>() * 8) as i32);
        (1 << BUFFER_LENGTH) - 1
    };

    pub const fn new() -> Self {
        BitConverter { buffer_: 0, lower_free_bits_: BUFFER_LENGTH }
    }

    pub fn append(&mut self, bits: i32) {
        debug_assert!(bits >= 0 && bits < (1 << FROM_LENGTH));
        debug_assert!(self.can_append());
        self.lower_free_bits_ -= FROM_LENGTH;
        self.buffer_ |= bits << self.lower_free_bits_;
    }

    pub fn extract(&mut self) -> i32 {
        debug_assert!(self.can_extract());
        let result = self.peek();
        self.buffer_ = (self.buffer_ << TO_LENGTH) & Self::K_MASK;
        self.lower_free_bits_ += TO_LENGTH;
        result
    }

    pub fn peek(&self) -> i32 {
        self.buffer_ >> (BUFFER_LENGTH - TO_LENGTH)
    }
    pub fn bits_available(&self) -> i32 {
        BUFFER_LENGTH - self.lower_free_bits_
    }
    pub fn can_append(&self) -> bool {
        self.lower_free_bits_ >= FROM_LENGTH
    }
    pub fn can_extract(&self) -> bool {
        self.bits_available() >= TO_LENGTH
    }
}

pub type Base32DecodeConverter = BitConverter<5, 8, 16>;
pub type Base32EncodeConverter = BitConverter<8, 5, 16>;

const K_ENCODING: &[u8; 32] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

pub fn base32_encode(input: impl AsRef<[u8]>) -> (bool, String) {
    let input = input.as_ref();
    if input.is_empty() {
        return (true, String::new());
    }

    if input.len() > usize::MAX / 8 {
        return (false, String::new());
    }

    let encoded_length = (input.len() * 8 + 4) / 5;
    let mut output = Vec::with_capacity(encoded_length);

    let mut converter = Base32EncodeConverter::new();
    converter.append(input[0] as i32);
    let mut next_byte_index = 1;

    while converter.can_extract() {
        output.push(K_ENCODING[converter.extract() as usize]);
        if converter.can_append() && next_byte_index < input.len() {
            converter.append(input[next_byte_index] as i32);
            next_byte_index += 1;
        }
    }

    if converter.bits_available() > 0 {
        output.push(K_ENCODING[converter.peek() as usize]);
    }

    // Every byte pushed comes from K_ENCODING, which is ASCII.
    (true, String::from_utf8(output).expect("base32 alphabet is ASCII"))
}

const K_DECODE_MAP: [i8; 41] = [
    // starting from ASCII 50 '2'
    26, 27, 28, 29, 30, 31, -1, -1, -1, -1, -1, -1, -1, -1, //
    -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, //
    13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
];

const K_DECODE_MAP_SIZE: i32 = K_DECODE_MAP.len() as i32;

pub fn base32_decode(input: impl AsRef<[u8]>) -> (bool, Vec<u8>) {
    let mut result = Vec::new();
    let mut converter = Base32DecodeConverter::new();
    for &c in input.as_ref() {
        // `char` is signed on the engine's targets, so bytes >= 0x80 index
        // below the map and fail here.
        let map_index = (c as i8) as i32 - b'2' as i32;
        if map_index < 0
            || map_index >= K_DECODE_MAP_SIZE
            || K_DECODE_MAP[map_index as usize] == -1
        {
            return (false, result);
        }
        converter.append(K_DECODE_MAP[map_index as usize] as i32);
        if converter.can_extract() {
            result.push(converter.extract() as u8);
        }
    }
    if converter.peek() != 0 {
        // The padding should always be zero. Return false if not.
        return (false, result);
    }
    (true, result)
}
