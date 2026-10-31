// Port of flutter/fml/memory/ref_ptr.h and
// flutter/fml/memory/ref_ptr_internal.h.
//
// `RefPtr<T>` is a nullable `Arc<T>`: copying adds a reference, dropping
// releases one, and the last release destroys the object. What has no
// counterpart is making a `RefPtr` from a raw `T*` (`RefPtr(T*)`,
// `fml::Ref(this)`): an object that needs a reference to itself keeps a
// `Weak` to itself (`Arc::new_cyclic`) or takes `self: &Arc<Self>`.
// `operator->` on a null RefPtr is a DCHECK upstream (undefined behaviour in
// release); `Deref` panics here.

use std::hash::{Hash, Hasher};
use std::sync::Arc;

pub struct RefPtr<T: ?Sized> {
    ptr_: Option<Arc<T>>,
}

impl<T: ?Sized> Default for RefPtr<T> {
    fn default() -> Self {
        RefPtr { ptr_: None }
    }
}

impl<T: ?Sized> Clone for RefPtr<T> {
    fn clone(&self) -> Self {
        RefPtr { ptr_: self.ptr_.clone() }
    }
}

impl<T: ?Sized> From<Arc<T>> for RefPtr<T> {
    fn from(ptr: Arc<T>) -> Self {
        RefPtr { ptr_: Some(ptr) }
    }
}

impl<T: ?Sized> RefPtr<T> {
    /// `RefPtr()` / `RefPtr(nullptr)`.
    pub const fn null() -> Self {
        RefPtr { ptr_: None }
    }

    /// Upcasts, as upstream's converting constructors do: pass a closure that
    /// coerces, e.g. `|p| p as Arc<dyn Base>`.
    pub fn upcast<U: ?Sized>(self, f: impl FnOnce(Arc<T>) -> Arc<U>) -> RefPtr<U> {
        RefPtr { ptr_: self.ptr_.map(f) }
    }

    pub fn get(&self) -> Option<&T> {
        self.ptr_.as_deref()
    }

    pub fn as_arc(&self) -> Option<&Arc<T>> {
        self.ptr_.as_ref()
    }

    /// The address `get()` would return, for identity comparisons.
    pub fn as_ptr(&self) -> *const () {
        match &self.ptr_ {
            Some(p) => Arc::as_ptr(p) as *const (),
            None => std::ptr::null(),
        }
    }

    pub fn swap(&mut self, r: &mut RefPtr<T>) {
        std::mem::swap(&mut self.ptr_, &mut r.ptr_);
    }

    #[allow(non_snake_case)]
    pub fn Clone(&self) -> RefPtr<T> {
        self.clone()
    }

    /// `explicit operator bool`.
    pub fn as_bool(&self) -> bool {
        self.ptr_.is_some()
    }

    /// `HasOneRef()` of the object; false for a null RefPtr.
    pub fn has_one_ref(&self) -> bool {
        self.ptr_.as_ref().is_some_and(|p| Arc::strong_count(p) == 1)
    }
}

impl<T: ?Sized> std::ops::Deref for RefPtr<T> {
    type Target = T;
    fn deref(&self) -> &T {
        self.ptr_.as_deref().expect("dereferenced a null RefPtr")
    }
}

impl<T: ?Sized, U: ?Sized> PartialEq<RefPtr<U>> for RefPtr<T> {
    fn eq(&self, rhs: &RefPtr<U>) -> bool {
        self.as_ptr() == rhs.as_ptr()
    }
}

impl<T: ?Sized> Eq for RefPtr<T> {}

impl<T: ?Sized, U: ?Sized> PartialOrd<RefPtr<U>> for RefPtr<T> {
    fn partial_cmp(&self, rhs: &RefPtr<U>) -> Option<std::cmp::Ordering> {
        self.as_ptr().partial_cmp(&rhs.as_ptr())
    }
}

/// `std::hash<fml::RefPtr<T>>`: the hash of the pointer.
impl<T: ?Sized> Hash for RefPtr<T> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.as_ptr().hash(state);
    }
}

impl<T: ?Sized> crate::hash_combine::StdHash for RefPtr<T> {
    fn std_hash(&self) -> usize {
        self.as_ptr() as usize
    }
}

impl<T: ?Sized> std::fmt::Debug for RefPtr<T> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "RefPtr({:p})", self.as_ptr())
    }
}

/// `AdoptRef(new T(...))`.
pub fn adopt_ref<T>(value: T) -> RefPtr<T> {
    RefPtr { ptr_: Some(Arc::new(value)) }
}

/// `MakeRefCounted<T>(args...)`: construct the value and adopt it.
pub fn make_ref_counted<T>(value: T) -> RefPtr<T> {
    adopt_ref(value)
}
