// Port of flutter/fml/unique_object.h.

use crate::fml_check_at;

const FILE: &str = "flutter/fml/unique_object.h";

/// `UniqueObjectTraits`: what a `UniqueObject` needs to know about the handle
/// it owns. `free` is never called with the invalid value.
pub trait UniqueObjectTraits {
    type T: Copy + PartialEq;

    /// Should be fast and inline.
    fn invalid_value() -> Self::T;

    /// Should be fast and inline.
    fn is_valid(value: Self::T) -> bool;

    /// Will not be called if value == invalid_value()!
    fn free(&mut self, value: Self::T);
}

/// Owns a handle (a file descriptor, a `DIR*`, ...) and frees it with its
/// traits when dropped or reset.
pub struct UniqueObject<Traits: UniqueObjectTraits> {
    generic: Traits::T,
    traits: Traits,
}

impl<Traits: UniqueObjectTraits + Default> Default for UniqueObject<Traits> {
    fn default() -> Self {
        UniqueObject { generic: Traits::invalid_value(), traits: Traits::default() }
    }
}

impl<Traits: UniqueObjectTraits + Default> UniqueObject<Traits> {
    pub fn new(value: Traits::T) -> Self {
        UniqueObject { generic: value, traits: Traits::default() }
    }
}

impl<Traits: UniqueObjectTraits> UniqueObject<Traits> {
    pub fn with_traits(value: Traits::T, traits: Traits) -> Self {
        UniqueObject { generic: value, traits }
    }

    /// Upstream's `operator=(UniqueObject&&)`.
    pub fn assign(&mut self, mut other: UniqueObject<Traits>) {
        let value = other.release();
        self.reset(value);
    }

    /// `reset()` with the default argument: frees the object.
    pub fn reset_invalid(&mut self) {
        self.reset(Traits::invalid_value());
    }

    pub fn reset(&mut self, value: Traits::T) {
        fml_check_at!(
            FILE,
            68,
            "data_.generic == Traits::InvalidValue() || data_.generic != value",
            self.generic == Traits::invalid_value() || self.generic != value
        );
        self.free_if_necessary();
        self.generic = value;
    }

    pub fn swap(&mut self, other: &mut UniqueObject<Traits>) {
        std::mem::swap(self, other);
    }

    /// Release the object. The return value is the current object held by
    /// this object. After this operation, this object will hold an invalid
    /// value, and will not own the object any more.
    #[must_use]
    pub fn release(&mut self) -> Traits::T {
        std::mem::replace(&mut self.generic, Traits::invalid_value())
    }

    pub fn get(&self) -> Traits::T {
        self.generic
    }

    pub fn is_valid(&self) -> bool {
        Traits::is_valid(self.generic)
    }

    pub fn get_traits(&self) -> &Traits {
        &self.traits
    }

    pub fn get_traits_mut(&mut self) -> &mut Traits {
        &mut self.traits
    }

    fn free_if_necessary(&mut self) {
        if self.generic != Traits::invalid_value() {
            self.traits.free(self.generic);
            self.generic = Traits::invalid_value();
        }
    }
}

impl<Traits: UniqueObjectTraits> PartialEq<Traits::T> for UniqueObject<Traits> {
    fn eq(&self, value: &Traits::T) -> bool {
        self.generic == *value
    }
}

impl<Traits: UniqueObjectTraits> Drop for UniqueObject<Traits> {
    fn drop(&mut self) {
        self.free_if_necessary();
    }
}
