// Port of the API oracle of rust/oracle/ast_dump.dart (`dumpApi`): what the
// public AST API returns on the tree (see that file for the format).

use std::rc::Rc;

pub fn dump_api(source: Rc<[u16]>) -> String {
    let _ = source;
    String::new()
}
