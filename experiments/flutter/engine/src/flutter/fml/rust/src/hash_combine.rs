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
    fn std_hash(&self) -> usize {
        murmur2_or_cityhash(self.as_bytes())
    }
}

impl StdHash for String {
    fn std_hash(&self) -> usize {
        murmur2_or_cityhash(self.as_bytes())
    }
}

/// `std::hash<std::string>` of a byte string that need not be UTF-8.
#[derive(Clone, Copy, Debug)]
pub struct ByteString<'a>(pub &'a [u8]);

impl StdHash for ByteString<'_> {
    fn std_hash(&self) -> usize {
        murmur2_or_cityhash(self.0)
    }
}

// ------------------------------------------------- libc++ CityHash64 ------

const K0: u64 = 0xc3a5c85c97cb3127;
const K1: u64 = 0xb492b66fbe98f273;
const K2: u64 = 0x9ae16a3b2f90404f;
const K3: u64 = 0xc949d7c7509e6557;

fn loadword(s: &[u8], at: usize) -> u64 {
    u64::from_ne_bytes(s[at..at + 8].try_into().unwrap())
}

fn loadword32(s: &[u8], at: usize) -> u32 {
    u32::from_ne_bytes(s[at..at + 4].try_into().unwrap())
}

fn rotate(val: u64, shift: u32) -> u64 {
    if shift == 0 { val } else { val.rotate_right(shift) }
}

fn rotate_by_at_least_1(val: u64, shift: u32) -> u64 {
    // libc++ shifts a 64-bit value by `shift` and `64 - shift`; callers pass
    // 9..=16, so this is a rotation.
    val.rotate_right(shift)
}

fn shift_mix(val: u64) -> u64 {
    val ^ (val >> 47)
}

fn hash_len_16(u: u64, v: u64) -> u64 {
    const MUL: u64 = 0x9ddfea08eb382d69;
    let mut a = (u ^ v).wrapping_mul(MUL);
    a ^= a >> 47;
    let mut b = (v ^ a).wrapping_mul(MUL);
    b ^= b >> 47;
    b = b.wrapping_mul(MUL);
    b
}

fn hash_len_0_to_16(s: &[u8]) -> u64 {
    let len = s.len() as u64;
    if len > 8 {
        let a = loadword(s, 0);
        let b = loadword(s, s.len() - 8);
        return hash_len_16(a, rotate_by_at_least_1(b.wrapping_add(len), len as u32)) ^ b;
    }
    if len >= 4 {
        let a = loadword32(s, 0);
        let b = loadword32(s, s.len() - 4);
        // Without _LIBCPP_ABI_FIX_CITYHASH_IMPLEMENTATION (the default ABI),
        // `__a << 3` is a 32-bit shift that drops a's top three bits.
        return hash_len_16(len.wrapping_add(a.wrapping_shl(3) as u64), b as u64);
    }
    if len > 0 {
        let a = s[0];
        let b = s[s.len() >> 1];
        let c = s[s.len() - 1];
        let y: u32 = (a as u32).wrapping_add((b as u32) << 8);
        let z: u32 = (len as u32).wrapping_add((c as u32) << 2);
        return shift_mix((y as u64).wrapping_mul(K2) ^ (z as u64).wrapping_mul(K3))
            .wrapping_mul(K2);
    }
    K2
}

fn hash_len_17_to_32(s: &[u8]) -> u64 {
    let len = s.len() as u64;
    let a = loadword(s, 0).wrapping_mul(K1);
    let b = loadword(s, 8);
    let c = loadword(s, s.len() - 8).wrapping_mul(K2);
    let d = loadword(s, s.len() - 16).wrapping_mul(K0);
    hash_len_16(
        rotate(a.wrapping_sub(b), 43).wrapping_add(rotate(c, 30)).wrapping_add(d),
        a.wrapping_add(rotate(b ^ K3, 20)).wrapping_sub(c).wrapping_add(len),
    )
}

fn weak_hash_len_32_with_seeds_words(w: u64, x: u64, y: u64, z: u64, mut a: u64, mut b: u64) -> (u64, u64) {
    a = a.wrapping_add(w);
    b = rotate(b.wrapping_add(a).wrapping_add(z), 21);
    let c = a;
    a = a.wrapping_add(x);
    a = a.wrapping_add(y);
    b = b.wrapping_add(rotate(a, 44));
    (a.wrapping_add(z), b.wrapping_add(c))
}

fn weak_hash_len_32_with_seeds(s: &[u8], at: usize, a: u64, b: u64) -> (u64, u64) {
    weak_hash_len_32_with_seeds_words(
        loadword(s, at),
        loadword(s, at + 8),
        loadword(s, at + 16),
        loadword(s, at + 24),
        a,
        b,
    )
}

fn hash_len_33_to_64(s: &[u8]) -> u64 {
    let n = s.len();
    let len = n as u64;
    let mut z = loadword(s, 24);
    let mut a = loadword(s, 0)
        .wrapping_add(len.wrapping_add(loadword(s, n - 16)).wrapping_mul(K0));
    let mut b = rotate(a.wrapping_add(z), 52);
    let mut c = rotate(a, 37);
    a = a.wrapping_add(loadword(s, 8));
    c = c.wrapping_add(rotate(a, 7));
    a = a.wrapping_add(loadword(s, 16));
    let vf = a.wrapping_add(z);
    let vs = b.wrapping_add(rotate(a, 31)).wrapping_add(c);
    a = loadword(s, 16).wrapping_add(loadword(s, n - 32));
    z = z.wrapping_add(loadword(s, n - 8));
    b = rotate(a.wrapping_add(z), 52);
    c = rotate(a, 37);
    a = a.wrapping_add(loadword(s, n - 24));
    c = c.wrapping_add(rotate(a, 7));
    a = a.wrapping_add(loadword(s, n - 16));
    let wf = a.wrapping_add(z);
    let ws = b.wrapping_add(rotate(a, 31)).wrapping_add(c);
    let r = shift_mix(
        vf.wrapping_add(ws).wrapping_mul(K2).wrapping_add(wf.wrapping_add(vs).wrapping_mul(K0)),
    );
    shift_mix(r.wrapping_mul(K0).wrapping_add(vs)).wrapping_mul(K2)
}

/// libc++'s `__murmur2_or_cityhash<size_t, 64>`, the string hash.
pub fn murmur2_or_cityhash(s: &[u8]) -> usize {
    let n = s.len();
    if n <= 32 {
        if n <= 16 {
            return hash_len_0_to_16(s) as usize;
        } else {
            return hash_len_17_to_32(s) as usize;
        }
    } else if n <= 64 {
        return hash_len_33_to_64(s) as usize;
    }

    let mut len = n as u64;
    let mut x = loadword(s, n - 40);
    let mut y = loadword(s, n - 16).wrapping_add(loadword(s, n - 56));
    let mut z = hash_len_16(loadword(s, n - 48).wrapping_add(len), loadword(s, n - 24));
    let mut v = weak_hash_len_32_with_seeds(s, n - 64, len, z);
    let mut w = weak_hash_len_32_with_seeds(s, n - 32, y.wrapping_add(K1), x);
    x = x.wrapping_mul(K1).wrapping_add(loadword(s, 0));

    len = (len - 1) & !63u64;
    let mut at = 0usize;
    loop {
        x = rotate(x.wrapping_add(y).wrapping_add(v.0).wrapping_add(loadword(s, at + 8)), 37)
            .wrapping_mul(K1);
        y = rotate(y.wrapping_add(v.1).wrapping_add(loadword(s, at + 48)), 42).wrapping_mul(K1);
        x ^= w.1;
        y = y.wrapping_add(v.0.wrapping_add(loadword(s, at + 40)));
        z = rotate(z.wrapping_add(w.0), 33).wrapping_mul(K1);
        v = weak_hash_len_32_with_seeds(s, at, v.1.wrapping_mul(K1), x.wrapping_add(w.0));
        w = weak_hash_len_32_with_seeds(
            s,
            at + 32,
            z.wrapping_add(w.1),
            y.wrapping_add(loadword(s, at + 16)),
        );
        std::mem::swap(&mut z, &mut x);
        at += 64;
        len -= 64;
        if len == 0 {
            break;
        }
    }
    hash_len_16(
        hash_len_16(v.0, w.0).wrapping_add(shift_mix(y).wrapping_mul(K1)).wrapping_add(z),
        hash_len_16(v.1, w.1).wrapping_add(x),
    ) as usize
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
