// Port of lib/src/util/link.dart (the part the scanner uses).
//
// Upstream's `Link<T>` is an immutable cons list whose cells are objects, so
// lists share tails and compare by identity. Here the cells live in a
// `LinkStore` and a `Link` is a cell's index; index 0 is the empty list, so
// identity of lists is equality of indexes, as `identical` is upstream.
// Only `head`, `tail`, `isEmpty`, `isNotEmpty`, `prepend` and `slowLength`
// are ported; the iteration and builder helpers are not used by the scanner.

/// A list: the index of its first cell, or [Link::EMPTY].
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Link(u32);

impl Link {
    /// `const Link()`.
    pub const EMPTY: Link = Link(0);
}

/// The cells of every list built from it. Each cell is (head, tail).
#[derive(Debug)]
pub struct LinkStore<T: Copy> {
    cells: Vec<(T, Link)>,
}

impl<T: Copy + Default> Default for LinkStore<T> {
    fn default() -> Self {
        LinkStore::new()
    }
}

impl<T: Copy + Default> LinkStore<T> {
    pub fn new() -> LinkStore<T> {
        // Cell 0 stands for the empty list and is never read as a cell.
        LinkStore {
            cells: vec![(T::default(), Link::EMPTY)],
        }
    }

    #[inline(always)]
    pub fn is_empty(&self, link: Link) -> bool {
        link == Link::EMPTY
    }

    #[inline(always)]
    pub fn is_not_empty(&self, link: Link) -> bool {
        link != Link::EMPTY
    }

    /// `Link.head`; throws (here: panics) on the empty list.
    #[inline(always)]
    pub fn head(&self, link: Link) -> T {
        assert!(link != Link::EMPTY, "no elements");
        self.cells[link.0 as usize].0
    }

    /// `Link.tail`; null (here: the empty list) on the empty list.
    #[inline(always)]
    pub fn tail(&self, link: Link) -> Link {
        if link == Link::EMPTY {
            Link::EMPTY
        } else {
            self.cells[link.0 as usize].1
        }
    }

    /// `Link.prepend`.
    #[inline]
    pub fn prepend(&mut self, link: Link, element: T) -> Link {
        self.cells.push((element, link));
        Link((self.cells.len() - 1) as u32)
    }

    /// `Link.slowLength`.
    pub fn slow_length(&self, mut link: Link) -> i32 {
        let mut length = 0;
        while link != Link::EMPTY {
            length += 1;
            link = self.tail(link);
        }
        length
    }

    /// The number of cells allocated, so that a caller can drop cells it
    /// knows are unreachable with [LinkStore::truncate].
    pub fn cell_count(&self) -> usize {
        self.cells.len()
    }

    pub fn truncate(&mut self, cell_count: usize) {
        self.cells.truncate(cell_count);
    }
}
