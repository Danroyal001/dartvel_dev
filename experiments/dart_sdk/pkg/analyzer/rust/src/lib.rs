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
        pub mod utilities;
    }
    pub mod ast {
        pub mod doc_comment;
    }
    pub mod element {
        pub mod element;
    }
}
pub mod diagnostic {
    pub mod diagnostic;
}
pub mod error {
    pub mod listener;
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
        pub mod scanner {
            pub mod scanner;
            pub mod translate_error_token;
        }
    }
    pub mod diagnostic {
        pub mod diagnostic;
        #[rustfmt::skip]
        pub mod diagnostic_code_values_g;
        #[rustfmt::skip]
        pub mod diagnostic_g;
    }
    pub mod error {
        pub mod listener;
    }
    pub mod fasta {
        pub mod ast_builder;
        pub mod doc_comment_builder;
        pub mod error_converter;
    }
    pub mod generated {
        pub mod parser;
        pub mod utilities_dart;
    }
}
