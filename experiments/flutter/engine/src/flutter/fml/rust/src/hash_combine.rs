// Port of flutter/fml/hash_combine.h.
//
// HashCombine folds `std::hash<T>` of each argument into the seed, so its
// value depends on the C++ library's hash functions. `StdHash` is that
// dependency: it reproduces libc++'s (the engine's C++ library) 64-bit
// `std::hash` for the types the engine combines, including its CityHash64
// string hash (`__murmur2_or_cityhash<size_t, 64>` in
// <__functional/hash.h>), so a Rust hash equals the C++ one.
//
// HashCombine and HashCombineSeed are variadic templates; they are the
// `hash_combine!` and `hash_combine_seed!` macros here.

/// `std::hash<T>{}(value)` as libc++ computes it on a 64-bit target.
pub trait StdHash {
    fn std_hash(&self) -> usize;
}

impl<T: StdHash + ?Sized> StdHash for &T {
    fn std_hash(&self) -> usize {
        (**self).std_hash()
    }
}

// Integral types: `static_cast<size_t>(v)`, sign-extending signed ones.
macro_rules! integral_hash {
    ($($t:ty),*) => {$(
        impl StdHash for $t {
            fn std_hash(&self) -> usize {
                *self as usize
            }
        }
    )*};
}
integral_hash!(u8, i8, u16, i16, u32, i32, u64, i64, usize, isize);

impl StdHash for bool {
    fn std_hash(&self) -> usize {
        *self as usize
    }
}

/// `char32_t`.
impl StdHash for char {
    fn std_hash(&self) -> usize {
        *self as usize
    }
}

/// `-0.0f` and `0.0f` hash to 0; otherwise the float's bits, zero-extended.
impl StdHash for f32 {
    fn std_hash(&self) -> usize {
        if *self == 0.0 { 0 } else { self.to_bits() as usize }
    }
}

/// `-0.0` and `0.0` hash to 0; otherwise the double's bits.
impl StdHash for f64 {
    fn std_hash(&self) -> usize {
        if *self == 0.0 { 0 } else { self.to_bits() as usize }
    }
}

impl<T: ?Sized> StdHash for *const T {
    fn std_hash(&self) -> usize {
        self.cast::<()>() as usize
    }
}

impl StdHash for str {
    #[inline]
    fn std_hash(&self) -> usize {
        murmur2_or_cityhash(self.as_bytes())
    }
}

impl StdHash for String {
    #[inline]
    fn std_hash(&self) -> usize {
        murmur2_or_cityhash(self.as_bytes())
    }
}

/// `std::hash<std::string>` of a byte string that need not be UTF-8.
#[derive(Clone, Copy, Debug)]
pub struct ByteString<'a>(pub &'a [u8]);

impl StdHash for ByteString<'_> {
    #[inline]
    fn std_hash(&self) -> usize {
        murmur2_or_cityhash(self.0)
    }
}

// ------------------------------------------------- libc++ CityHash64 ------

const K0: u64 = 0xc3a5c85c97cb3127;
const K1: u64 = 0xb492b66fbe98f273;
const K2: u64 = 0x9ae16a3b2f90404f;
const K3: u64 = 0xc949d7c7509e6557;

// Words are read from fixed-size arrays at constant offsets (the head and
// tail of the string, and each 64-byte block), so that no read needs a bounds
// check: the length class a function serves already guarantees the bytes.

#[inline(always)]
fn word<const N: usize>(b: &[u8; N], at: usize) -> u64 {
    u64::from_ne_bytes(*b[at..].first_chunk::<8>().unwrap())
}

#[inline(always)]
fn word32<const N: usize>(b: &[u8; N], at: usize) -> u32 {
    u32::from_ne_bytes(*b[at..].first_chunk::<4>().unwrap())
}

#[inline(always)]
fn rotate(val: u64, shift: u32) -> u64 {
    if shift == 0 { val } else { val.rotate_right(shift) }
}

#[inline(always)]
fn rotate_by_at_least_1(val: u64, shift: u32) -> u64 {
    // libc++ shifts a 64-bit value by `shift` and `64 - shift`; callers pass
    // 9..=16, so this is a rotation.
    val.rotate_right(shift)
}

#[inline(always)]
fn shift_mix(val: u64) -> u64 {
    val ^ (val >> 47)
}

#[inline(always)]
fn hash_len_16(u: u64, v: u64) -> u64 {
    const MUL: u64 = 0x9ddfea08eb382d69;
    let mut a = (u ^ v).wrapping_mul(MUL);
    a ^= a >> 47;
    let mut b = (v ^ a).wrapping_mul(MUL);
    b ^= b >> 47;
    b = b.wrapping_mul(MUL);
    b
}

#[inline(always)]
fn hash_len_0_to_16(s: &[u8]) -> u64 {
    let len = s.len() as u64;
    if let (Some(head), Some(tail), true) = (s.first_chunk::<8>(), s.last_chunk::<8>(), len > 8) {
        let a = word(head, 0);
        let b = word(tail, 0);
        return hash_len_16(a, rotate_by_at_least_1(b.wrapping_add(len), len as u32)) ^ b;
    }
    if let (Some(head), Some(tail)) = (s.first_chunk::<4>(), s.last_chunk::<4>()) {
        let a = word32(head, 0);
        let b = word32(tail, 0);
        // Without _LIBCPP_ABI_FIX_CITYHASH_IMPLEMENTATION (the default ABI),
        // `__a << 3` is a 32-bit shift that drops a's top three bits.
        return hash_len_16(len.wrapping_add(a.wrapping_shl(3) as u64), b as u64);
    }
    if let (Some(&a), Some(&c)) = (s.first(), s.last()) {
        let b = s[s.len() >> 1];
        let y: u32 = (a as u32).wrapping_add((b as u32) << 8);
        let z: u32 = (len as u32).wrapping_add((c as u32) << 2);
        return shift_mix((y as u64).wrapping_mul(K2) ^ (z as u64).wrapping_mul(K3))
            .wrapping_mul(K2);
    }
    K2
}

/// 17 to 32 bytes: `head` and `tail` are the first and last 16.
#[inline(always)]
fn hash_len_17_to_32(len: u64, head: &[u8; 16], tail: &[u8; 16]) -> u64 {
    let a = word(head, 0).wrapping_mul(K1);
    let b = word(head, 8);
    let c = word(tail, 8).wrapping_mul(K2);
    let d = word(tail, 0).wrapping_mul(K0);
    hash_len_16(
        rotate(a.wrapping_sub(b), 43).wrapping_add(rotate(c, 30)).wrapping_add(d),
        a.wrapping_add(rotate(b ^ K3, 20)).wrapping_sub(c).wrapping_add(len),
    )
}

#[inline(always)]
fn weak_hash_len_32_with_seeds_words(w: u64, x: u64, y: u64, z: u64, mut a: u64, mut b: u64) -> (u64, u64) {
    a = a.wrapping_add(w);
    b = rotate(b.wrapping_add(a).wrapping_add(z), 21);
    let c = a;
    a = a.wrapping_add(x);
    a = a.wrapping_add(y);
    b = b.wrapping_add(rotate(a, 44));
    (a.wrapping_add(z), b.wrapping_add(c))
}

/// The 32 bytes of `b` from `at`.
#[inline(always)]
fn weak_hash_len_32_with_seeds<const N: usize>(b: &[u8; N], at: usize, x: u64, y: u64) -> (u64, u64) {
    weak_hash_len_32_with_seeds_words(word(b, at), word(b, at + 8), word(b, at + 16), word(b, at + 24), x, y)
}

/// 33 to 64 bytes: `head` and `tail` are the first and last 32.
#[inline(always)]
fn hash_len_33_to_64(len: u64, head: &[u8; 32], tail: &[u8; 32]) -> u64 {
    // In upstream's offsets, s + len - k is tail + 32 - k.
    let mut z = word(head, 24);
    let mut a = word(head, 0).wrapping_add(len.wrapping_add(word(tail, 16)).wrapping_mul(K0));
    let mut b = rotate(a.wrapping_add(z), 52);
    let mut c = rotate(a, 37);
    a = a.wrapping_add(word(head, 8));
    c = c.wrapping_add(rotate(a, 7));
    a = a.wrapping_add(word(head, 16));
    let vf = a.wrapping_add(z);
    let vs = b.wrapping_add(rotate(a, 31)).wrapping_add(c);
    a = word(head, 16).wrapping_add(word(tail, 0));
    z = z.wrapping_add(word(tail, 24));
    b = rotate(a.wrapping_add(z), 52);
    c = rotate(a, 37);
    a = a.wrapping_add(word(tail, 8));
    c = c.wrapping_add(rotate(a, 7));
    a = a.wrapping_add(word(tail, 16));
    let wf = a.wrapping_add(z);
    let ws = b.wrapping_add(rotate(a, 31)).wrapping_add(c);
    let r = shift_mix(
        vf.wrapping_add(ws).wrapping_mul(K2).wrapping_add(wf.wrapping_add(vs).wrapping_mul(K0)),
    );
    shift_mix(r.wrapping_mul(K0).wrapping_add(vs)).wrapping_mul(K2)
}

/// libc++'s `__murmur2_or_cityhash<size_t, 64>`, the string hash.
#[inline]
pub fn murmur2_or_cityhash(s: &[u8]) -> usize {
    let n = s.len();
    let len = n as u64;
    if n <= 16 {
        return hash_len_0_to_16(s) as usize;
    }
    if n <= 32 {
        let (head, tail) = (s.first_chunk::<16>().unwrap(), s.last_chunk::<16>().unwrap());
        return hash_len_17_to_32(len, head, tail) as usize;
    }
    if n <= 64 {
        let (head, tail) = (s.first_chunk::<32>().unwrap(), s.last_chunk::<32>().unwrap());
        return hash_len_33_to_64(len, head, tail) as usize;
    }
    murmur2_or_cityhash_long(s) as usize
}

/// More than 64 bytes. In upstream's offsets, s + len - k is tail + 64 - k.
#[inline(never)]
fn murmur2_or_cityhash_long(s: &[u8]) -> u64 {
    let n = s.len();
    let tail = s.last_chunk::<64>().unwrap();
    let mut len = n as u64;
    let mut x = word(tail, 24);
    let mut y = word(tail, 48).wrapping_add(word(tail, 8));
    let mut z = hash_len_16(word(tail, 16).wrapping_add(len), word(tail, 40));
    let mut v = weak_hash_len_32_with_seeds(tail, 0, len, z);
    let mut w = weak_hash_len_32_with_seeds(tail, 32, y.wrapping_add(K1), x);
    x = x.wrapping_mul(K1).wrapping_add(word(s.first_chunk::<8>().unwrap(), 0));

    len = (len - 1) & !63u64;
    for block in s[..len as usize].chunks_exact(64) {
        let block: &[u8; 64] = block.try_into().unwrap();
        x = rotate(x.wrapping_add(y).wrapping_add(v.0).wrapping_add(word(block, 8)), 37)
            .wrapping_mul(K1);
        y = rotate(y.wrapping_add(v.1).wrapping_add(word(block, 48)), 42).wrapping_mul(K1);
        x ^= w.1;
        y = y.wrapping_add(v.0.wrapping_add(word(block, 40)));
        z = rotate(z.wrapping_add(w.0), 33).wrapping_mul(K1);
        v = weak_hash_len_32_with_seeds(block, 0, v.1.wrapping_mul(K1), x.wrapping_add(w.0));
        w = weak_hash_len_32_with_seeds(block, 32, z.wrapping_add(w.1), y.wrapping_add(word(block, 16)));
        std::mem::swap(&mut z, &mut x);
    }
    hash_len_16(
        hash_len_16(v.0, w.0).wrapping_add(shift_mix(y).wrapping_mul(K1)).wrapping_add(z),
        hash_len_16(v.1, w.1).wrapping_add(x),
    )
}

// --------------------------------------------------------- HashCombine ------

#[inline]
pub fn hash_combine_seed_one<T: StdHash + ?Sized>(seed: &mut usize, arg: &T) {
    *seed ^= arg
        .std_hash()
        .wrapping_add(0x9e3779b9)
        .wrapping_add(*seed << 6)
        .wrapping_add(*seed >> 2);
}

/// `HashCombine()` with no arguments.
pub const fn hash_combine_empty() -> usize {
    0xdabbad00
}

/// `HashCombineSeed(seed, args...)`.
#[macro_export]
macro_rules! hash_combine_seed {
    ($seed:expr, $($arg:expr),+ $(,)?) => {{
        let seed: &mut usize = $seed;
        $( $crate::hash_combine::hash_combine_seed_one(seed, &$arg); )+
    }};
}

/// `HashCombine(args...)`.
#[macro_export]
macro_rules! hash_combine {
    () => {
        $crate::hash_combine::hash_combine_empty()
    };
    ($($arg:expr),+ $(,)?) => {{
        let mut seed = $crate::hash_combine::hash_combine_empty();
        $crate::hash_combine_seed!(&mut seed, $($arg),+);
        seed
    }};
}
