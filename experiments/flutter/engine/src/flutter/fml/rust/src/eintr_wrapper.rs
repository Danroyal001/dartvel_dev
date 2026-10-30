// Port of flutter/fml/eintr_wrapper.h.
//
// FML_HANDLE_EINTR(x) retries `x` while it returns -1 with errno EINTR;
// FML_IGNORE_EINTR(x) maps that result to 0. Both take the call as a closure.
// On Windows both are the identity, as upstream.

/// `EINTR` on Linux, Android and the Apple platforms.
const EINTR: i32 = 4;

fn interrupted() -> bool {
    std::io::Error::last_os_error().raw_os_error() == Some(EINTR)
}

/// An integer result of a POSIX call: -1 marks an error.
pub trait EintrResult: Copy + PartialEq {
    const MINUS_ONE: Self;
    const ZERO: Self;
}

macro_rules! eintr_result {
    ($($t:ty),*) => {$(
        impl EintrResult for $t {
            const MINUS_ONE: Self = -1;
            const ZERO: Self = 0;
        }
    )*};
}
eintr_result!(i32, i64, isize);

pub fn handle_eintr<T: EintrResult>(mut x: impl FnMut() -> T) -> T {
    if cfg!(windows) {
        return x();
    }
    loop {
        let eintr_wrapper_result = x();
        if !(eintr_wrapper_result == T::MINUS_ONE && interrupted()) {
            return eintr_wrapper_result;
        }
    }
}

pub fn ignore_eintr<T: EintrResult>(mut x: impl FnMut() -> T) -> T {
    let eintr_wrapper_result = x();
    if !cfg!(windows) && eintr_wrapper_result == T::MINUS_ONE && interrupted() {
        return T::ZERO;
    }
    eintr_wrapper_result
}
