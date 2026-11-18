// Differential test of Uri.parse against upstream (not a mirrored file; see
// ../README.md).
//
// Every input is parsed by the Dart VM (oracle/uri_oracle.dart) and by the
// port, and both must give the same `toString()` of the parsed Uri, or throw
// something whose `toString()` is the same, code unit for code unit.
//
// Inputs: the seed files in tests/seeds (URI strings found in the kernel
// corpus, and the string literals of tests/corelib/uri_*_test.dart and
// data_uri_test.dart), a few hand-picked edge cases, every seed damaged
// (cut short from either end, one code unit flipped with each of several
// masks, one significant character inserted) at a number of positions, and
// random strings over the characters that matter to the parser.
//
// Environment:
//   DART             the Dart executable (default: `dart` on PATH).
//   URI_POSITIONS    damage positions per seed: every position of a seed up
//                    to this length, otherwise the first and last third of
//                    this many plus positions spread by a fixed sequence
//                    (default 24).
//   URI_RANDOM       number of random inputs (default 60000).
//   URI_WORK         scratch directory (default: target/uri_oracle).
#![allow(non_snake_case)]
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use dart_core::uri::parseUriToStringUtf16;

fn sdk_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../..").canonicalize().unwrap()
}

fn env_number(name: &str, default: usize) -> usize {
    std::env::var(name).ok().and_then(|value| value.parse().ok()).unwrap_or(default)
}

/// The oracle's line format: U+0020..U+007E except `\` as itself, any other
/// code unit as `\` and four lower-case hex digits.
fn encode(text: &[u16]) -> String {
    let mut line = String::with_capacity(text.len());
    for &codeUnit in text {
        if (0x20..0x7F).contains(&codeUnit) && codeUnit != 0x5C {
            line.push(codeUnit as u8 as char);
        } else {
            line.push_str(&format!("\\{codeUnit:04x}"));
        }
    }
    line
}

/// The inverse of [encode]. Other characters (in the hand-written edge
/// cases) stand for their UTF-16 code units.
fn decode(line: &str) -> Vec<u16> {
    let mut text = Vec::with_capacity(line.len());
    let mut chars = line.chars();
    while let Some(char) = chars.next() {
        if char == '\\' {
            let hex: String = chars.by_ref().take(4).collect();
            text.push(u16::from_str_radix(&hex, 16).unwrap());
        } else {
            let mut buffer = [0u16; 2];
            text.extend_from_slice(char.encode_utf16(&mut buffer));
        }
    }
    text
}

fn units(text: &str) -> Vec<u16> {
    text.encode_utf16().collect()
}

/// Hand-picked inputs on the edges of the parser, written in the oracle's
/// escape format (`\d800` is a lone surrogate, `\005c` a backslash).
fn edgeCases() -> Vec<Vec<u16>> {
    let mut cases: Vec<Vec<u16>> = [
        "", ":", "a:", "1:", "//", "///", "/", "?", "#", "%", "%2", "%25", "%zz", "..", ".", "./", "../",
        "a/..", "a/./b/../c", "/..", "/../", "x:..", "x:/..", "x://h/..?q", "x:..#f",
        "data:", "data:,", "DATA:,", "dAtA:text/plain,a", "data:;base64,", "data:;base64,AAA",
        "data:;base64,AA%3D%3D", "data:;base64,A-_=", "data:a/b;c=d;base64,QQ", "data:a;b",
        "data:a/b/c,", "data:,#frag", "data:,?q#f", "data:;base64,A=A=",
        "file:", "file:a", "file:/a", "file://h", "file://h?q", "FILE:x", "fIle://", "file:..",
        "http://h:80/", "http://h:80", "http://h:080/", "http://h:0x50/", "http://h:+80/",
        "http://h: 80/", "http://h:\u{a0}80\u{3000}/", "http://h:-0/", "http://h:99999999999999999999/",
        "http://h:0xffffffffffffffff/", "http://h:0x10000000000000000/", "http://h:-0x8000000000000000/",
        "http://h:-0x8000000000000001/", "http://h:9223372036854775807/", "http://h:9223372036854775808/",
        "http://h:-9223372036854775808/", "http://h:-9223372036854775809/", "https://h:443/",
        "https://h:443", "https://H:443?x", "http://u@h/", "http://u:p@h:1/", "http://@h/",
        "http://h:/", "http:\\005c\\005ch\\005cp", "http:/\\005ch", "\\005c\\005ch", "http://[::1]/", "http://[::1%25eth0]/",
        "http://[::1%eth0]/", "http://[::1%25%41]/", "http://[::1%25%]/", "http://[v1.x]/",
        "http://[v.x]/", "http://[v1]/", "http://[v1.]/", "http://[v1.\u{100}]/", "http://[vg.x]/",
        "http://[]/", "http://[/", "http://]/", "http://[1:2:3:4:5:6:7:8]/", "http://[1:2:3:4:5:6:7:8:9]/",
        "http://[::ffff:1.2.3.4]/", "http://[::1.2.3.4.5]/", "http://[::256.1.1.1]/",
        "http://[::01.1.1.1]/", "http://[:1]/", "http://[1::2::3]/", "http://[12345::]/", "http://[1:]/",
        "http://[::1]:8/", "http://[A::B]/", "http://H%41%4a/", "http://h%zz/", "http://h%/",
        "http://h%7e/", "http://h%7E/", "http://h\u{e9}/", "http://h\\d800/", "http://h\\d800\\dc00/",
        "http://h<>/", "http://a b/", "s:%7e%7E%2f%2F", "S+-.:x", "s_:x", "1s:x", "-:x", "a\u{e9}:x",
        "foo:\\d800", "foo:\\dc00", "foo:\\d800\\dc00", "?\\d800", "#\\dfff\\d800",
        "package:foo/bar.dart", "package:../foo", "dart:core", "org-dartlang-sdk:///sdk/lib/core/uri.dart",
        "a\nb", "a\rb", "a\r\nb", "\n%", "a:b\nc[d", "x://[\n]",
    ]
    .iter()
    .map(|text| decode(text))
    .collect();
    // A long input, for the FormatException's excerpt with `...`.
    let long = format!("http://{}[{}", "a".repeat(100), "b".repeat(100));
    cases.push(units(&long));
    cases.push(units(&format!("{}%", "x".repeat(200))));
    cases.push(units(&format!("http://{}\n{}[x", "a".repeat(10), "b".repeat(90))));
    cases.push(units(&format!("http://h/{}?{}#{}", "p".repeat(80), "q".repeat(80), "f".repeat(80))));
    cases
}

fn seeds() -> Vec<Vec<u16>> {
    let directory = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/seeds");
    let mut seeds = edgeCases();
    for name in ["kernel_corpus_uris.txt", "corelib_uri_test_literals.txt"] {
        let text = fs::read_to_string(directory.join(name)).unwrap();
        seeds.extend(text.lines().map(decode));
    }
    seeds
}

struct Lcg(u64);

impl Lcg {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        self.0 >> 33
    }
}

const FLIP_MASKS: [u16; 11] = [0x01, 0x04, 0x10, 0x20, 0x40, 0x60, 0x80, 0xFF, 0x2000, 0xD800, 0xDC00];

const INSERTIONS: [&[u16]; 18] = [
    &[0x25], &[0x5C], &[0x5B], &[0x5D], &[0x3A], &[0x40], &[0x3F], &[0x23], &[0x20], &[0x2F], &[0x2E],
    &[0xE9], &[0x2028], &[0xD800], &[0xDC00], &[0x25, 0x34], &[0x2E, 0x2E, 0x2F], &[0x2F, 0x2F],
];

fn damage(seed: &[u16], positionsWanted: usize, random: &mut Lcg, out: &mut Vec<Vec<u16>>) {
    let length = seed.len();
    let positions: Vec<usize> = if length <= positionsWanted {
        (0..=length).collect()
    } else {
        let edge = positionsWanted / 3;
        let mut positions: Vec<usize> = (0..edge).chain(length + 1 - edge..=length).collect();
        for _ in 0..positionsWanted - 2 * edge {
            positions.push(random.next() as usize % (length + 1));
        }
        positions.sort_unstable();
        positions.dedup();
        positions
    };
    for &position in &positions {
        out.push(seed[..position].to_vec());
        out.push(seed[position..].to_vec());
        if position < length {
            for mask in FLIP_MASKS {
                let mut flipped = seed.to_vec();
                flipped[position] ^= mask;
                out.push(flipped);
            }
        }
        for insertion in INSERTIONS {
            let mut inserted = seed[..position].to_vec();
            inserted.extend_from_slice(insertion);
            inserted.extend_from_slice(&seed[position..]);
            out.push(inserted);
        }
    }
}

const RANDOM_PREFIXES: [&str; 9] = ["", "http://", "https://", "file:", "file://", "package:", "data:", "x:", "//"];

const RANDOM_ALPHABET: [u16; 40] = [
    0x61, 0x62, 0x41, 0x5A, 0x30, 0x31, 0x38, 0x3A, 0x2F, 0x3F, 0x23, 0x5B, 0x5D, 0x40, 0x21, 0x24, 0x26,
    0x27, 0x28, 0x2B, 0x2C, 0x3B, 0x3D, 0x25, 0x2D, 0x2E, 0x5F, 0x7E, 0x5C, 0x20, 0x76, 0x66, 0x78, 0x0A,
    0x7F, 0xE9, 0x2028, 0xD800, 0xDC00, 0x22,
];

fn randomInputs(count: usize, random: &mut Lcg, out: &mut Vec<Vec<u16>>) {
    for _ in 0..count {
        let prefix = RANDOM_PREFIXES[random.next() as usize % RANDOM_PREFIXES.len()];
        let mut text = units(prefix);
        let length = random.next() as usize % 25;
        for _ in 0..length {
            // Favour the structural characters and dots.
            let pick = random.next() as usize;
            let char = if pick % 4 == 0 { [0x2E, 0x2F, 0x25, 0x3A][pick / 4 % 4] } else {
                RANDOM_ALPHABET[pick / 4 % RANDOM_ALPHABET.len()]
            };
            text.push(char);
        }
        out.push(text);
    }
}

fn inputs() -> Vec<Vec<u16>> {
    let positionsWanted = env_number("URI_POSITIONS", 24);
    let mut random = Lcg(0x2545F4914F6CDD1D);
    let mut all = Vec::new();
    for seed in seeds() {
        all.push(seed.clone());
        damage(&seed, positionsWanted, &mut random, &mut all);
    }
    randomInputs(env_number("URI_RANDOM", 60000), &mut random, &mut all);
    let mut seen = HashSet::new();
    all.retain(|text| seen.insert(text.clone()));
    all
}

fn portResult(text: &[u16]) -> String {
    match parseUriToStringUtf16(text) {
        Ok(result) => format!("ok {}", encode(&result)),
        Err(thrown) => format!("error {}", encode(&thrown)),
    }
}

#[test]
fn uri_parse_does_what_upstream_does() {
    let work = std::env::var("URI_WORK").map(PathBuf::from).unwrap_or_else(|_| sdk_root().join("target/uri_oracle"));
    fs::create_dir_all(&work).unwrap();
    let inputs = inputs();
    let mut inputText = String::new();
    for text in &inputs {
        inputText.push_str(&encode(text));
        inputText.push('\n');
    }
    let inputPath = work.join("inputs.txt");
    let expectedPath = work.join("expected.txt");
    fs::write(&inputPath, inputText).unwrap();
    let dart = std::env::var("DART").unwrap_or_else(|_| "dart".into());
    let oracle = Path::new(env!("CARGO_MANIFEST_DIR")).join("oracle/uri_oracle.dart");
    let output = Command::new(&dart)
        .arg(&oracle)
        .arg(&inputPath)
        .arg(&expectedPath)
        .output()
        .unwrap_or_else(|e| panic!("cannot run {dart}: {e}"));
    assert!(output.status.success(), "oracle failed: {}", String::from_utf8_lossy(&output.stderr));
    let expected = fs::read_to_string(&expectedPath).unwrap();
    let expected: Vec<&str> = expected.lines().collect();
    assert_eq!(expected.len(), inputs.len(), "oracle wrote one line per input");
    let mut differences = 0;
    let mut okCount = 0;
    for (text, expectedLine) in inputs.iter().zip(&expected) {
        if expectedLine.starts_with("ok ") {
            okCount += 1;
        }
        let actual = portResult(text);
        if actual != *expectedLine {
            differences += 1;
            if differences <= 30 {
                eprintln!("input:    {}\nexpected: {expectedLine}\nactual:   {actual}\n", encode(text));
            }
        }
    }
    eprintln!(
        "{} inputs ({} parsed, {} threw), {} differences",
        inputs.len(),
        okCount,
        inputs.len() - okCount,
        differences
    );
    let _ = fs::remove_file(&inputPath);
    let _ = fs::remove_file(&expectedPath);
    assert_eq!(differences, 0, "the port differs from upstream on {differences} of {} inputs", inputs.len());
}
