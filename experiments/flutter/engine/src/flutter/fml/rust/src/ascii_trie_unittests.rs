// Port of flutter/fml/ascii_trie_unittests.cc.

use super::ascii_trie::AsciiTrie;

#[test]
fn simple() {
    let mut trie = AsciiTrie::new();
    trie.fill(&["foo"]);
    assert!(trie.query("foobar"));
    assert!(!trie.query("google"));
}

#[test]
fn exact_match() {
    let mut trie = AsciiTrie::new();
    trie.fill(&["foo"]);
    assert!(trie.query("foo"));
}

#[test]
fn empty() {
    let trie = AsciiTrie::new();
    assert!(trie.query("foo"));
}

#[test]
fn multiple_entries() {
    let mut trie = AsciiTrie::new();
    trie.fill(&["foo", "bar"]);
    assert!(trie.query("foozzz"));
    assert!(trie.query("barzzz"));
}
