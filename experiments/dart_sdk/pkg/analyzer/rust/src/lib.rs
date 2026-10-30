// Crate root of the Rust port of pkg/analyzer (not a mirrored file).
//
// Every module below mirrors one Dart library under ../lib at the same
// relative path, keeps its structure and names, and names that library in
// its first line. So far the port covers parsing a file into the syntax
// tree: the AST, the AstBuilder and `parseString`.
//
// `src/` mirrors `../lib`: `src/dart/...` ports `lib/dart/...` and
// `src/src/...` ports `lib/src/...`.
#![forbid(unsafe_code)]
#![allow(clippy::all)]
#![allow(non_upper_case_globals, non_snake_case)]

#[macro_use]
pub mod dart {
    pub mod analysis {
        pub mod features;
        pub mod utilities;
    }
    #[macro_use]
    pub mod ast {
        pub mod doc_comment;
        pub mod precedence;
        #[rustfmt::skip]
        #[macro_use]
        pub mod visitor_g;
        pub mod visitor;
    }
    pub mod element {
        pub mod element;
        pub mod nullability_suffix;
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
// Libraries of `_fe_analyzer_shared` this crate needs before that crate has
// them (see each file's header).
pub mod fe_analyzer_shared {
    pub mod types {
        pub mod shared_type;
    }
    pub mod util {
        pub mod dependency_walker;
    }
}
pub mod src {
    pub mod context {
        pub mod packages;
    }
    pub mod dart {
        pub mod analysis {
            pub mod experiments;
            #[rustfmt::skip]
            pub mod experiments_g;
            pub mod experiments_impl;
            pub mod file_state;
        }
        pub mod ast {
            #[rustfmt::skip]
            pub mod ast;
            #[rustfmt::skip]
            pub mod ast_g;
            pub mod ast_store;
            pub mod ast_v1;
            pub mod invokes_super_self;
            pub mod to_source_visitor;
            pub mod utilities;
        }
        pub mod element {
            pub mod display_string_builder;
            pub mod element;
            pub mod r#type;
            pub mod scope;
            pub mod type_algebra;
            pub mod type_system;
            pub mod normalize;
            pub mod top_merge;
            pub mod class_hierarchy;
            pub mod subtype;
        }
        pub mod resolver {
            pub mod scope;
        }
        pub mod scanner {
            pub mod scanner;
            pub mod translate_error_token;
        }
        pub mod sdk {
            pub mod sdk;
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
    pub mod summary2 {
        pub mod type_builder;
        pub mod interface_cycles;
        pub mod type_alias;
        pub mod types_builder;
        pub mod default_types_builder;
        pub mod reference_resolver;
        pub mod element_builder;
        pub mod export;
        pub mod library_builder;
        pub mod link;
        pub mod not_serializable_nodes;
    }
    pub mod utilities {
        pub mod uri_cache;
    }
    pub mod util {
        pub mod graph;
    }
}
