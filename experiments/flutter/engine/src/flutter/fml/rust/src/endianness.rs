// Port of flutter/fml/endianness.h (and its empty endianness.cc).

/// `IsByteSwappable`: integral types (enums go through their underlying
/// type).
pub trait ByteSwappable: Copy {
    fn byte_swap(self) -> Self;
}

macro_rules! byte_swappable {
    ($($t:ty),*) => {$(
        impl ByteSwappable for $t {
            fn byte_swap(self) -> Self {
                self.swap_bytes()
            }
        }
    )*};
}
byte_swappable!(u8, i8, u16, i16, u32, i32, u64, i64, usize, isize);

impl ByteSwappable for bool {
    fn byte_swap(self) -> Self {
        self
    }
}

/// Flips the endianness of the given value.
/// The given value must be an integral type of size 1, 2, 4, or 8.
pub fn byte_swap<T: ByteSwappable>(n: T) -> T {
    n.byte_swap()
}

/// Convert a known big endian value to match the endianness of the
/// current architecture. This is effectively a cross platform
/// ntohl/ntohs (as network byte order is always Big Endian).
/// The given value must be an integral type of size 1, 2, 4, or 8.
pub fn big_endian_to_arch<T: ByteSwappable>(n: T) -> T {
    if cfg!(target_endian = "little") { byte_swap(n) } else { n }
}

/// Convert a known little endian value to match the endianness of the
/// current architecture.
/// The given value must be an integral type of size 1, 2, 4, or 8.
pub fn little_endian_to_arch<T: ByteSwappable>(n: T) -> T {
    if cfg!(target_endian = "little") { n } else { byte_swap(n) }
}
