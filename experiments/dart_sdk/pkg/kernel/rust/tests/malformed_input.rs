// The reader's safety contract (not a mirrored file; see ../README.md): any
// input, however damaged, is read or refused with a `ParseError`, never a
// panic, and the reader never allocates more than the input could describe.
// Small enough to run under Miri.
use kernel::ast::{Component, StringPool};
use kernel::binary::ast_from_binary::loadComponentFromBytes;
use kernel::binary::ast_to_binary::writeComponentToBytes;

/// A component with no libraries: the smallest file the writer makes.
fn empty_component_bytes() -> Vec<u8> {
    let component = Component {
        strings: StringPool::from_table(vec![b"".to_vec().into_boxed_slice()]),
        ..Component::default()
    };
    writeComponentToBytes(&component).unwrap()
}

#[test]
fn an_empty_component_round_trips() {
    let bytes = empty_component_bytes();
    let component = loadComponentFromBytes(&bytes).unwrap();
    assert!(component.libraries.is_empty());
    assert_eq!(writeComponentToBytes(&component).unwrap(), bytes);
}

#[test]
fn every_truncation_is_refused_without_a_panic() {
    let bytes = empty_component_bytes();
    for length in 0..bytes.len() {
        assert!(
            loadComponentFromBytes(&bytes[..length]).is_err(),
            "a component cut to {length} of {} bytes was accepted",
            bytes.len()
        );
    }
}

#[test]
fn every_flipped_byte_is_read_or_refused_without_a_panic() {
    let bytes = empty_component_bytes();
    for position in 0..bytes.len() {
        for flip in [0x01u8, 0x80, 0xFF] {
            let mut damaged = bytes.clone();
            damaged[position] ^= flip;
            // Either outcome is fine; reaching this line is the test.
            let _ = loadComponentFromBytes(&damaged);
        }
    }
}

#[test]
fn a_huge_length_does_not_allocate() {
    // A maximal UInt30 (2^30 - 1) at every position: lists that claim a
    // billion items, in a file of a few hundred bytes.
    let bytes = empty_component_bytes();
    for position in 0..bytes.len().saturating_sub(3) {
        let mut damaged = bytes.clone();
        damaged[position..position + 4].copy_from_slice(&[0xFF, 0xFF, 0xFF, 0xFF]);
        let _ = loadComponentFromBytes(&damaged);
    }
}

/// A real program (tests/fixtures), so that damage lands in libraries,
/// classes, procedures, statements, expressions and types, not only in the
/// tables an empty component has.
const PROGRAM: &[u8] = include_bytes!("fixtures/hello-unlinked.dill");

#[test]
fn every_truncation_of_a_program_is_refused_without_a_panic() {
    for length in 0..PROGRAM.len() {
        assert!(
            loadComponentFromBytes(&PROGRAM[..length]).is_err(),
            "a program cut to {length} of {} bytes was accepted",
            PROGRAM.len()
        );
    }
}

#[test]
fn every_flipped_byte_of_a_program_is_read_or_refused_without_a_panic() {
    for position in 0..PROGRAM.len() {
        for flip in [0x01u8, 0x40, 0x80, 0xFF] {
            let mut damaged = PROGRAM.to_vec();
            damaged[position] ^= flip;
            // What is read must also be written without a panic.
            if let Ok(component) = loadComponentFromBytes(&damaged) {
                let _ = writeComponentToBytes(&component);
            }
        }
    }
}
