// Port of flutter/fml/container_unittests.cc.

use std::collections::HashMap;

use super::container::erase_if;

#[test]
fn map_erase_if() {
    let mut map: HashMap<i32, i32> = HashMap::from([(0, 1), (2, 3), (4, 5)]);

    erase_if(&mut map, |k: &i32, v: &mut i32| *k == 0 || *v == 5);

    assert_eq!(map.len(), 1);
    assert!(map.contains_key(&2));
}
