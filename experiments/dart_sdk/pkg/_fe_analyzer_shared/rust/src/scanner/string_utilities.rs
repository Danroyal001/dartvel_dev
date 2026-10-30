// Port of lib/src/scanner/string_utilities.dart.
//
// Upstream's `INTERNER` is a mutable static that tools replace; here it is a
// thread-local, which is what a Dart isolate's static is.

use std::cell::RefCell;

use super::interner::{Interner, NullInterner};

thread_local! {
    static INTERNER: RefCell<Box<dyn Interner>> = RefCell::new(Box::new(NullInterner));
}

pub struct StringUtilities;

impl StringUtilities {
    /// `StringUtilities.INTERNER = interner`.
    pub fn set_interner(interner: Box<dyn Interner>) {
        INTERNER.with(|i| *i.borrow_mut() = interner);
    }

    pub fn intern(string: String) -> String {
        INTERNER.with(|i| i.borrow().intern(string))
    }
}
