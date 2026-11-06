// Port of lib/src/piece/piece.dart: State and Shape (Piece base is not ported yet).
use std::sync::Arc;

/// One splitting choice. Ordering compares values, whereas equality follows
/// Dart object identity, including canonical const objects. These are distinct
/// relations, so State intentionally does not implement Rust's Ord trait.
#[derive(Clone, Debug)]
pub struct State {
    value: i64,
    cost: i64,
    identity: Option<Arc<()>>,
}

impl State {
    pub const UNSPLIT: Self = Self::canonical(0, 0);
    pub const SPLIT: Self = Self::canonical(255, 1);

    /// A Dart non-const constructor call creates a fresh object.
    pub fn new(value: i64, cost: i64) -> Self {
        Self {
            value,
            cost,
            identity: Some(Arc::new(())),
        }
    }

    /// Dart canonicalizes const objects by their field values. Represent that
    /// identity directly without an interning table or permanently held heap.
    pub const fn canonical(value: i64, cost: i64) -> Self {
        Self {
            value,
            cost,
            identity: None,
        }
    }

    pub fn cost(&self) -> i64 {
        self.cost
    }

    pub fn compare_to(&self, other: &Self) -> i8 {
        match self.value.cmp(&other.value) {
            std::cmp::Ordering::Less => -1,
            std::cmp::Ordering::Equal => 0,
            std::cmp::Ordering::Greater => 1,
        }
    }
}

impl PartialEq for State {
    fn eq(&self, other: &Self) -> bool {
        match (&self.identity, &other.identity) {
            (Some(a), Some(b)) => Arc::ptr_eq(a, b),
            (None, None) => self.value == other.value && self.cost == other.cost,
            _ => false,
        }
    }
}
impl Eq for State {}

impl std::fmt::Display for State {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "◦{}", self.value)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Shape {
    Inline,
    Block,
    Headline,
    Other,
}

impl Shape {
    pub const ALL: &'static [Self] = &[Self::Inline, Self::Block, Self::Headline, Self::Other];
    pub const ONLY_BLOCK: &'static [Self] = &[Self::Block];
    pub const ONLY_INLINE: &'static [Self] = &[Self::Inline];
    pub const INLINE_OR_BLOCK: &'static [Self] = &[Self::Inline, Self::Block];

    pub fn any_if(condition: bool) -> &'static [Self] {
        if condition {
            Self::ALL
        } else {
            Self::ONLY_INLINE
        }
    }

    pub fn merge(self, other: Self) -> Self {
        match (self, other) {
            (Self::Inline, _) => other,
            (_, Self::Inline) => self,
            _ => Self::Other,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Inline => "inline",
            Self::Block => "block",
            Self::Headline => "headline",
            Self::Other => "other",
        }
    }
}
