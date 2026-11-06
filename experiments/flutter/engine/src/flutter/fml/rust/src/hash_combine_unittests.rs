// Port of flutter/fml/hash_combine_unittests.cc.

use crate::hash_combine;

#[test]
fn can_hash() {
    let hello = String::from("Hello");
    let world = String::from("World");
    assert_eq!(hash_combine!(), hash_combine!());
    assert_eq!(hash_combine!(hello), hash_combine!(hello));
    assert_ne!(hash_combine!(hello), hash_combine!(world));
    assert_eq!(hash_combine!(hello, world), hash_combine!(hello, world));
    assert_ne!(hash_combine!(world, hello), hash_combine!(hello, world));
    assert_eq!(hash_combine!(12u32), hash_combine!(12u32));
    assert_ne!(hash_combine!(12u32), hash_combine!(12.0f32));
    assert_eq!(hash_combine!(b'a' as i8), hash_combine!(b'a' as i8));
}
