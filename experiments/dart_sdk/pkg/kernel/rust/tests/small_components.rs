// Round trips of small real components (not a mirrored file; see
// ../README.md), small enough for Miri to run every reader and writer path
// they reach. The byte-for-byte comparison with upstream is
// tests/roundtrip_oracle.rs; this checks that the port reproduces
// upstream's own bytes where upstream wrote them, and is stable.
use kernel::binary::ast_from_binary::loadComponentFromBytes;
use kernel::binary::ast_to_binary::writeComponentToBytes;

fn round_trip(bytes: &[u8]) -> Vec<u8> {
    writeComponentToBytes(&loadComponentFromBytes(bytes).unwrap()).unwrap()
}

#[test]
fn upstreams_empty_component_is_written_back_as_upstream_wrote_it() {
    let bytes = include_bytes!("fixtures/empty.dill");
    assert_eq!(round_trip(bytes), bytes);
}

#[test]
fn a_program_round_trips_and_its_output_is_stable() {
    let bytes = include_bytes!("fixtures/hello-unlinked.dill");
    let once = round_trip(bytes);
    assert_eq!(round_trip(&once), once);
}

#[test]
fn a_program_concatenated_with_itself_reads_as_one() {
    let bytes = include_bytes!("fixtures/hello-unlinked.dill");
    let once = round_trip(bytes);
    let twice = round_trip(&[bytes.as_slice(), bytes.as_slice()].concat());
    assert_eq!(twice, once);
}
