// Crate root of the Rust port of pkg/analyzer (not a mirrored file).
//
// Every module below mirrors one Dart library under ../lib at the same
// relative path, keeps its structure and names, and names that library in
// its first line. So far the port covers parsing a file into the syntax
// tree: the AST, the AstBuilder and `parseString`.
//
// `src/` mirrors `../lib`: `src/dart/...` ports `lib/dart/...` and
// `src/src/...` ports `lib/src/...`.
#![allow(clippy::all)]
#![allow(non_upper_case_globals, non_snake_case)]

pub mod dart {
    pub mod analysis {
        pub mod features;
    }
    pub mod ast {
        pub mod doc_comment;
    }
    pub mod element {
        pub mod element;
    }
}
pub mod source {
    pub mod line_info;
}
#[allow(clippy::module_inception)]
pub mod src {
    pub mod dart {
        pub mod analysis {
            pub mod experiments;
            #[rustfmt::skip]
            pub mod experiments_g;
            pub mod experiments_impl;
        }
        pub mod ast {
            #[rustfmt::skip]
            pub mod ast;
            pub mod ast_store;
        }
    }
    pub mod generated {
        pub mod utilities_dart;
    }
}
