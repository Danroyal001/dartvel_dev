// Port of lib/src/scanner/recover.dart.

pub fn close_brace_for(open_brace: &str) -> &'static str {
    match open_brace {
        "(" => ")",
        "[" => "]",
        "{" => "}",
        "<" => ">",
        "${" => "}",
        _ => panic!("no close brace for {open_brace}"),
    }
}

pub fn close_quote_for(open_quote: &str) -> &'static str {
    match open_quote {
        "\"" => "\"",
        "'" => "'",
        "\"\"\"" => "\"\"\"",
        "'''" => "'''",
        "r\"" => "\"",
        "r'" => "'",
        "r\"\"\"" => "\"\"\"",
        "r'''" => "'''",
        _ => panic!("no close quote for {open_quote}"),
    }
}
