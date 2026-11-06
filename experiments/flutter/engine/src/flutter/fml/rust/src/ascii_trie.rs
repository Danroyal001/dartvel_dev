// Port of flutter/fml/ascii_trie.h and flutter/fml/ascii_trie.cc.
//
// Entries and queries are byte strings read up to a NUL, as upstream's
// `const char*` are. A byte >= 0x80 is a negative `char` upstream and
// indexes outside the node (undefined behaviour); here it panics.

pub type TrieNodePtr = Option<Box<TrieNode>>;

/// A trie for looking for ASCII prefixes.
#[derive(Default)]
pub struct AsciiTrie {
    node_: TrieNodePtr,
}

pub struct TrieNode {
    pub children: [TrieNodePtr; AsciiTrie::K_MAX_ASCII_VALUE],
}

impl Default for TrieNode {
    fn default() -> Self {
        TrieNode { children: std::array::from_fn(|_| None) }
    }
}

fn char_at(s: &[u8], i: usize) -> usize {
    s.get(i).copied().unwrap_or(0) as usize
}

fn add(trie: &mut TrieNodePtr, entry: &[u8]) {
    let ch = char_at(entry, 0);
    debug_assert!(ch < AsciiTrie::K_MAX_ASCII_VALUE);
    if ch != 0 {
        let node = trie.get_or_insert_with(Box::default);
        add(&mut node.children[ch], &entry[1..]);
    }
}

fn make_trie<S: AsRef<[u8]>>(entries: &[S]) -> TrieNodePtr {
    let mut result = None;
    for entry in entries {
        add(&mut result, entry.as_ref());
    }
    result
}

impl AsciiTrie {
    /// The max Ascii value.
    pub const K_MAX_ASCII_VALUE: usize = 128;

    pub fn new() -> Self {
        Self::default()
    }

    /// Clear and insert all the entries into the trie.
    pub fn fill<S: AsRef<[u8]>>(&mut self, entries: &[S]) {
        self.node_ = make_trie(entries);
    }

    /// Returns true if `argument` is prefixed by the contents of the trie.
    pub fn query(&self, argument: impl AsRef<[u8]>) -> bool {
        match &self.node_ {
            None => true,
            Some(node) => Self::query_node(node, argument.as_ref()),
        }
    }

    fn query_node(trie: &TrieNode, query: &[u8]) -> bool {
        let mut char_position = 0;
        let mut trie_position: &TrieNode = trie;
        let mut child: Option<&TrieNode> = None;
        loop {
            let ch = char_at(query, char_position);
            if ch == 0 {
                break;
            }
            // `child` keeps its last value when the loop stops on the NUL, as
            // upstream's `(ch = *p) && (child = ...)` does.
            child = trie_position.children[ch].as_deref();
            match child {
                None => break,
                Some(c) => {
                    char_position += 1;
                    trie_position = c;
                }
            }
        }
        child.is_none() && !std::ptr::eq(trie_position, trie)
    }
}
