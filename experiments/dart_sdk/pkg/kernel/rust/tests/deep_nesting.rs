// Nesting deeper than upstream's stack holds (not a mirrored file; see
// ../README.md): upstream throws `Stack Overflow`, and so must the port,
// instead of exhausting its own stack and aborting the process.
use kernel::ast::*;
use kernel::binary::ast_from_binary::{loadComponentFromBytes, nestingLimit};
use kernel::binary::ast_to_binary::writeComponentToBytes;

#[test]
fn the_deepest_chain_upstream_writes_is_written() {
    let bytes = include_bytes!("fixtures/not-chain-4202.dill");
    let component = loadComponentFromBytes(bytes).unwrap();
    assert_eq!(writeComponentToBytes(&component).unwrap(), bytes);
}

#[test]
fn one_level_deeper_throws_stack_overflow() {
    let bytes = include_bytes!("fixtures/not-chain-4203.dill");
    let error = loadComponentFromBytes(bytes).err().expect("read a chain upstream cannot");
    assert_eq!(error.to_string(), "Stack Overflow");
}

#[test]
fn a_tree_too_deep_to_write_throws_stack_overflow() {
    let mut component = loadComponentFromBytes(include_bytes!("fixtures/hello-unlinked.dill")).unwrap();
    let mut expression = Expression::BoolLiteral { fileOffset: -1, value: true };
    for _ in 0..nestingLimit * 2 {
        expression = Expression::Not { fileOffset: -1, operand: Box::new(expression) };
    }
    let body = component.libraries[0].procedures[0].function.body.as_mut().unwrap();
    let Statement::Block { statements, .. } = &mut **body else { panic!("main has no block") };
    statements[0] = Statement::Expression(Box::new(expression));
    let error = writeComponentToBytes(&component).err().expect("wrote a tree upstream cannot");
    assert_eq!(error.to_string(), "Stack Overflow");
}
