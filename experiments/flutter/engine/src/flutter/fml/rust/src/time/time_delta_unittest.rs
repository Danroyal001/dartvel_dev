// Port of flutter/fml/time/time_delta_unittest.cc.

use super::time_delta::TimeDelta;

#[test]
fn time_delta_control() {
    assert!(TimeDelta::min() < TimeDelta::zero());
    assert!(TimeDelta::max() > TimeDelta::zero());
    assert!(TimeDelta::zero() > TimeDelta::from_milliseconds(-100));
    assert!(TimeDelta::zero() < TimeDelta::from_milliseconds(100));
    assert_eq!(TimeDelta::from_milliseconds(1000), TimeDelta::from_seconds(1));
}
