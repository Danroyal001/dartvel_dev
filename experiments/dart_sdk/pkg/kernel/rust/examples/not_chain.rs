// The generator of tests/fixtures/not-chain-*.dill (not a mirrored file):
// not_chain <fixture> <depth> <out>: main's first statement becomes
// `!!!...!true;` nested <depth> deep, written on a thread with a large
// stack. The writer now refuses trees deeper than upstream can write
// (`nestingLimit`), so the 4203-deep fixture, written before it did, needs
// that limit raised to be made again.
use kernel::ast::*;
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let depth: usize = args[2].parse().unwrap();
    let bytes = std::fs::read(&args[1]).unwrap();
    let out = args[3].clone();
    std::thread::Builder::new().stack_size(4 << 30).spawn(move || {
        let mut c = kernel::binary::ast_from_binary::loadComponentFromBytes(&bytes).unwrap();
        let body = c.libraries[0].procedures[0].function.body.as_mut().unwrap();
        let mut e = Expression::BoolLiteral { fileOffset: -1, value: true };
        for _ in 0..depth { e = Expression::Not { fileOffset: -1, operand: Box::new(e) }; }
        if let Statement::Block { statements, .. } = &mut **body { statements[0] = Statement::Expression(Box::new(e)); } else { panic!("no block") }
        let o = kernel::binary::ast_to_binary::writeComponentToBytes(&c).unwrap();
        std::fs::write(&out, o).unwrap();
        std::mem::forget(c);
    }).unwrap().join().unwrap();
}
