// Not an upstream file: how a C++ `std::ostream` prints a float with its
// default flags (`%g`, six significant digits), which upstream's
// `operator<<` overloads use, and `std::fixed` (`%f`), which Matrix's uses.

/// `out << v` for a float or double: `%g` with precision 6.
pub fn g(v: impl Into<f64>) -> String {
    let v: f64 = v.into();
    if v.is_nan() {
        return if v.is_sign_negative() { "-nan".into() } else { "nan".into() };
    }
    if v.is_infinite() {
        return if v < 0.0 { "-inf".into() } else { "inf".into() };
    }
    const P: i32 = 6;
    if v == 0.0 {
        return if v.is_sign_negative() { "-0".into() } else { "0".into() };
    }
    // The exponent after rounding to P significant digits.
    let e = format!("{:.*e}", (P - 1) as usize, v);
    let x: i32 = e[e.find('e').unwrap() + 1..].parse().unwrap();
    if x < P && x >= -4 {
        let s = format!("{:.*}", (P - 1 - x) as usize, v);
        strip(s)
    } else {
        let mant = strip(e[..e.find('e').unwrap()].to_string());
        let sign = if x < 0 { '-' } else { '+' };
        format!("{mant}e{sign}{:02}", x.abs())
    }
}

/// `std::fixed` (`%f`, precision 6).
pub fn fixed(v: impl Into<f64>) -> String {
    let v: f64 = v.into();
    if v.is_nan() {
        return if v.is_sign_negative() { "-nan".into() } else { "nan".into() };
    }
    if v.is_infinite() {
        return if v < 0.0 { "-inf".into() } else { "inf".into() };
    }
    format!("{v:.6}")
}

#[inline]
fn strip(s: String) -> String {
    if s.contains('.') {
        let t = s.trim_end_matches('0');
        t.trim_end_matches('.').to_string()
    } else {
        s
    }
}
