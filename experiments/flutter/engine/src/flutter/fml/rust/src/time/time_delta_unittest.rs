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

// Not upstream's: a double out of int64_t's range converts as upstream's
// compiled code converts it. On x86-64 that is cvttsd2si, which gives
// INT64_MIN for anything out of range and for NaN (seen from the C++ built
// as the oracle is, at -O2, on runtime values); on AArch64 it is fcvtzs,
// which saturates and gives 0 for NaN, as Rust's `as` does.
#[test]
fn out_of_range_doubles_convert_as_upstreams_code_does() {
    let cases = [1e300, -1e300, f64::NAN, -f64::NAN, f64::INFINITY, 9.3e9, -9.3e9];
    for v in cases {
        let ns = TimeDelta::from_seconds_f(v).to_nanoseconds();
        if cfg!(target_arch = "x86_64") {
            assert_eq!(ns, i64::MIN, "{v}");
        } else {
            assert_eq!(ns, (v * 1e9) as i64, "{v}");
        }
    }
    assert_eq!(TimeDelta::from_milliseconds_f(9.3e9).to_nanoseconds(), 9300000000000000);
    assert_eq!(TimeDelta::from_seconds_f(9e9).to_nanoseconds(), 9000000000000000000);
    assert_eq!(TimeDelta::from_seconds_f(1.5).to_nanoseconds(), 1500000000);
    assert_eq!(TimeDelta::from_seconds_f(-1.5).to_nanoseconds(), -1500000000);
}
