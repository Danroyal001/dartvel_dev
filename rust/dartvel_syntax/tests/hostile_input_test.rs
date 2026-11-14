// Sources nobody would write on purpose (not a ported file).
//
// `check_source_bytes` promises never to panic: whatever the bytes are, it
// answers clean, flagged or deferred. These feed it malformed files and
// seeded mutations of well-formed ones. A caught parser panic is allowed
// (it is answered as deferred, and Dart then decides) and is counted and
// printed, so a run shows how often the port takes that exit.

use dartvel_syntax::{DeferReason, SyntaxOutcome, check_source_bytes};

const WELL_FORMED_SOURCES: &[&str] = &[
    r#"
import 'dart:async';
import 'package:flutter/widgets.dart' as widgets show Widget, BuildContext;

/// A counter page.
@Deprecated('use CounterPage')
class Counter<T extends num> extends Base with Mixin implements Comparable<Counter<T>> {
  Counter(this.value, {required this.label, int? step}) : step = step ?? 1, super();
  final T value;
  final String label;
  final int step;
  static const List<int> primes = <int>[2, 3, 5, 7];
  T get doubled => (value * 2) as T;
  set ignored(Object? _) {}
  @override
  int compareTo(Counter<T> other) => value.compareTo(other.value);
  Future<void> run() async {
    await for (final event in Stream<int>.periodic(const Duration(seconds: 1))) {
      if (event > 3) break;
      print('tick $event of ${primes.length} "${label.toUpperCase()}"');
    }
  }
  Counter<T> operator +(Counter<T> other) => Counter<T>((value + other.value) as T, label: label);
}
"#,
    r#"
sealed class Shape {}
class Circle(final double radius) extends Shape;
extension type Meters(double value) implements double {}
enum Colour { red, green, blue; const Colour(); bool get warm => this == red; }
mixin Named on Object { String get name; }
typedef Callback<T> = void Function(T value, {bool? urgent});
String describe(Object shape) => switch (shape) {
  Circle(radius: final radius) when radius > 10 => 'big circle',
  Circle() => 'circle',
  (int first, String second) => 'record $first $second',
  [var head, ...var tail] => 'list of ${tail.length + 1}',
  {'key': final value?} => 'map $value',
  _ => 'unknown',
};
void main(List<String> arguments) {
  final (left, right) = (1, 'two');
  var numbers = [for (var index = 0; index < 3; index++) if (index.isEven) index, ...?null];
  numbers..add(4)..sort();
  final text = '''multi
line ${numbers.map((number) => number * 2).join(', ')}''';
  label: while (true) { try { throw StateError(text); } on StateError catch (error, stack) { break label; } finally {} }
  assert(left is int && right is! int, 'never');
  final closure = <T>(T value) { return value; };
  closure?.call(left as dynamic ?? right);
}
"#,
];

const MALFORMED_SOURCES: &[&str] = &[
    "class",
    "class {",
    "class A extends {",
    "void main( {",
    "void main() { return",
    "'unterminated",
    "\"unterminated ${",
    "'''unterminated",
    "r'raw",
    "/* unterminated comment",
    "/** /* nested */",
    "var x = ${};",
    "var x = '${'${'${",
    "}}}}}}}}",
    ")))))))",
    "]]]]]]]",
    ">>>>>>>>>>>",
    "<<<<<<<<<<<",
    "@",
    "@@@@@@",
    "#",
    "#!",
    "import",
    "import 'a' as;",
    "import 'a' show hide deferred as;",
    "library;;;;",
    "part of;",
    "enum {",
    "enum E { a, b, ; ; }",
    "extension on {",
    "extension type (",
    "mixin on on on {}",
    "typedef = ;",
    "switch",
    "void f() { switch (x) { case } }",
    "void f() { for (;;;;) }",
    "void f() { if else }",
    "void f() { try } catch",
    "void f() => => =>;",
    "var x = (,);",
    "var x = (a: , b: );",
    "var x = [...];",
    "var x = {...?};",
    "var x = a ? : ;",
    "var x = a ?? ?? b;",
    "var x = 0x;",
    "var x = 1e;",
    "var x = 1.;",
    "var x = 1__0;",
    "var x = '\\u{110000}';",
    "var x = '\\x';",
    "var \u{0}x = 1;",
    "\u{0}\u{0}\u{0}",
    "\u{feff}void main() {}",
    "void main() {}\u{1a}",
    "var \u{1F600} = 1;",
    "// @dart=2.9\nint? x;",
    "// @dart=99.99\nvoid main() {}",
    "// @dart=\nvoid main() {}",
    "external abstract static const final late var covariant required x;",
    "augment augment class A {}",
    "macro class A {}",
    "class A { A.() ; factory = ; operator ; get ; set ; }",
    "class A { int operator [](int i, int j) => 0; operator []=() {} }",
    "f<><><>() {}",
    "List<List<List<List<",
    "void Function(void Function(void Function(",
    "x!!!!!!!!!!.y?..z?.[w]",
    "await await await",
    "yield* yield* yield",
    "new new new A()",
    "const const const A()",
    "throw throw throw",
    "is is is as as as",
    "a = b = c = = d;",
    "a..b..c....d",
    "this.super.this.super",
    "super",
    "null",
    "\n\n\n\r\r\r\n\t\t",
];

/// xorshift64*: a seed gives the same mutations on every machine.
struct SeededRandom(u64);

impl SeededRandom {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }

    fn below(&mut self, bound: usize) -> usize {
        (self.next() % bound as u64) as usize
    }
}

const SPLICED_FRAGMENTS: &[&str] = &[
    "(",
    ")",
    "{",
    "}",
    "[",
    "]",
    "<",
    ">",
    "'",
    "\"",
    "'''",
    "${",
    "$",
    "\\",
    "/*",
    "*/",
    "//",
    ";",
    ",",
    ".",
    "..",
    "...",
    "?",
    "??",
    "?.",
    "!",
    "=>",
    "=",
    "==",
    ">>",
    ">>>",
    "@",
    "#",
    "class ",
    "extension type ",
    "enum ",
    "mixin ",
    "switch ",
    "case ",
    "when ",
    "await ",
    "async ",
    "yield ",
    "late ",
    "final ",
    "const ",
    "required ",
    "covariant ",
    "augment ",
    "import ",
    "part of ",
    "0x",
    "1e",
    "r'",
    "\u{0}",
    "\n",
    "\r",
    "\u{2028}",
    "\u{1F600}",
];

fn mutate(source: &str, random: &mut SeededRandom) -> Vec<u8> {
    let mut bytes = source.as_bytes().to_vec();
    for _ in 0..=random.below(4) {
        if bytes.is_empty() {
            break;
        }
        let position = random.below(bytes.len());
        match random.below(6) {
            0 => bytes.truncate(position),
            1 => {
                bytes.remove(position);
            }
            2 => bytes[position] = (random.next() & 0xff) as u8,
            3 => {
                let fragment = SPLICED_FRAGMENTS[random.below(SPLICED_FRAGMENTS.len())];
                bytes.splice(position..position, fragment.bytes());
            }
            4 => {
                let end = (position + 1 + random.below(40)).min(bytes.len());
                bytes.drain(position..end);
            }
            _ => {
                let end = (position + 1 + random.below(40)).min(bytes.len());
                let repeated = bytes[position..end].to_vec();
                bytes.splice(position..position, repeated);
            }
        }
    }
    bytes
}

#[test]
fn every_well_formed_source_here_is_clean() {
    for source in WELL_FORMED_SOURCES {
        assert_eq!(
            check_source_bytes(source.as_bytes()),
            SyntaxOutcome::Clean,
            "{source}"
        );
    }
}

#[test]
fn malformed_sources_are_answered() {
    let mut parser_panics = Vec::new();
    for source in MALFORMED_SOURCES {
        if check_source_bytes(source.as_bytes())
            == SyntaxOutcome::Deferred(DeferReason::ParserPanic)
        {
            parser_panics.push(*source);
        }
    }
    println!(
        "malformed sources: {} answered, {} by a caught parser panic: {parser_panics:?}",
        MALFORMED_SOURCES.len(),
        parser_panics.len()
    );
}

#[test]
fn every_prefix_of_a_well_formed_source_is_answered() {
    let mut parser_panics = 0;
    let mut prefixes = 0;
    for source in WELL_FORMED_SOURCES {
        for length in 0..source.len() {
            prefixes += 1;
            if check_source_bytes(&source.as_bytes()[..length])
                == SyntaxOutcome::Deferred(DeferReason::ParserPanic)
            {
                parser_panics += 1;
            }
        }
    }
    println!("prefixes: {prefixes} answered, {parser_panics} by a caught parser panic");
}

#[test]
fn seeded_mutations_are_answered() {
    let mut random = SeededRandom(0x00DA_127E_15EE_D001);
    let mut parser_panics = 0;
    let mut first_panicking_inputs: Vec<String> = Vec::new();
    let mut clean = 0;
    let mut flagged = 0;
    let mut deferred_for_encoding = 0;
    const MUTATIONS: usize = 40_000;
    for round in 0..MUTATIONS {
        let source = WELL_FORMED_SOURCES[round % WELL_FORMED_SOURCES.len()];
        let mutated = mutate(source, &mut random);
        match check_source_bytes(&mutated) {
            SyntaxOutcome::Clean => clean += 1,
            SyntaxOutcome::Flagged(_) => flagged += 1,
            SyntaxOutcome::Deferred(DeferReason::ParserPanic) => {
                parser_panics += 1;
                if first_panicking_inputs.len() < 5 {
                    first_panicking_inputs.push(String::from_utf8_lossy(&mutated).into_owned());
                }
            }
            SyntaxOutcome::Deferred(_) => deferred_for_encoding += 1,
        }
    }
    println!(
        "mutations: {MUTATIONS} answered: {clean} clean, {flagged} flagged, \
         {deferred_for_encoding} not UTF-8, {parser_panics} by a caught parser panic"
    );
    for input in &first_panicking_inputs {
        println!("--- a mutation the parser panicked on ---\n{input}");
    }
    assert_eq!(
        clean + flagged + deferred_for_encoding + parser_panics,
        MUTATIONS
    );
    // The mutations must actually reach the parser's error paths.
    assert!(
        flagged > MUTATIONS / 2,
        "only {flagged} mutations were flagged"
    );
}
