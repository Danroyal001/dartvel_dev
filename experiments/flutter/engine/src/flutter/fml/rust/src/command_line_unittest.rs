// Port of flutter/fml/command_line_unittest.cc (the Windows wide-argv test
// is not ported, nor is the parser it tests).

use super::command_line::*;

fn opt(name: &str) -> Option {
    Option::new(name)
}

fn optv(name: &str, value: &str) -> Option {
    Option::with_value(name, value)
}

fn strings(list: &[&str]) -> Vec<String> {
    list.iter().map(|s| s.to_string()).collect()
}

#[test]
fn basic() {
    let cl = command_line_from_initializer_list(&[
        "my_program",
        "--flag1",
        "--flag2=value2",
        "arg1",
        "arg2",
        "arg3",
    ]);

    assert!(cl.has_argv0());
    assert_eq!("my_program", cl.argv0());

    assert_eq!(2, cl.options().len());
    assert_eq!("flag1", cl.options()[0].name);
    assert_eq!("", cl.options()[0].value);
    assert_eq!("flag2", cl.options()[1].name);
    assert_eq!("value2", cl.options()[1].value);

    assert_eq!(3, cl.positional_args().len());
    assert_eq!("arg1", cl.positional_args()[0]);
    assert_eq!("arg2", cl.positional_args()[1]);
    assert_eq!("arg3", cl.positional_args()[2]);

    assert!(cl.has_option("flag1").is_some());
    assert_eq!(cl.has_option("flag2"), Some(1));
    assert!(cl.has_option("flag3").is_none());

    let mut value = String::from("nonempty");
    assert!(cl.get_option_value("flag1", &mut value));
    assert_eq!("", value);
    assert!(cl.get_option_value("flag2", &mut value));
    assert_eq!("value2", value);
    assert!(!cl.get_option_value("flag3", &mut value));

    assert_eq!("", cl.get_option_value_with_default("flag1", "nope"));
    assert_eq!("value2", cl.get_option_value_with_default("flag2", "nope"));
    assert_eq!("nope", cl.get_option_value_with_default("flag3", "nope"));
}

#[test]
fn default_constructor() {
    let cl = CommandLine::new();
    assert!(!cl.has_argv0());
    assert_eq!("", cl.argv0());
    assert_eq!(&Vec::<Option>::new(), cl.options());
    assert_eq!(&Vec::<String>::new(), cl.positional_args());
}

#[test]
fn component_constructor() {
    let argv0 = "my_program";
    let options = vec![optv("flag", "value")];
    let positional_args = strings(&["arg"]);

    let cl = CommandLine::with_components(argv0, &options, &positional_args);
    assert!(cl.has_argv0());
    assert_eq!(argv0, cl.argv0());
    assert_eq!(&options, cl.options());
    assert_eq!(&positional_args, cl.positional_args());
    assert_eq!("value", cl.get_option_value_with_default("flag", "nope"));
}

#[test]
fn command_line_from_iterators_find_first_positional_arg_test() {
    {
        let argv = ["my_program", "--flag1", "--flag2", "subcommand", "--subflag", "subarg"];
        let (cl, sub_first) = command_line_from_iterators_find_first_positional_arg(&argv);
        assert!(cl.has_argv0());
        assert_eq!(argv[0], cl.argv0());
        assert_eq!(&vec![opt("flag1"), opt("flag2")], cl.options());
        assert_eq!(&strings(&argv[3..6]), cl.positional_args());
        assert!(cl.has_option("flag1").is_some());
        assert!(cl.has_option("flag2").is_some());
        assert!(cl.has_option("subflag").is_none());

        assert_eq!(3, sub_first);
        let sub_cl = command_line_from_iterators(&argv[sub_first..]);
        assert!(sub_cl.has_argv0());
        assert_eq!(argv[3], sub_cl.argv0());
        assert_eq!(&vec![opt("subflag")], sub_cl.options());
        assert_eq!(&strings(&[argv[5]]), sub_cl.positional_args());
        assert!(sub_cl.has_option("flag1").is_none());
        assert!(sub_cl.has_option("flag2").is_none());
        assert!(sub_cl.has_option("subflag").is_some());
    }

    {
        let argv = ["my_program", "--flag"];
        let (_, sub_first) = command_line_from_iterators_find_first_positional_arg(&argv);
        assert_eq!(argv.len(), sub_first);
    }

    {
        let argv = ["my_program", "arg1", "arg2"];
        let (_, sub_first) = command_line_from_iterators_find_first_positional_arg(&argv);
        assert_eq!(1, sub_first);
    }

    {
        let argv = ["my_program", "--", "--arg"];
        let (_, sub_first) = command_line_from_iterators_find_first_positional_arg(&argv);
        assert_eq!(2, sub_first);
    }
}

#[test]
fn commmand_line_from_iterators() {
    {
        let argv = strings(&["my_program", "--flag=value", "arg"]);

        let cl = command_line_from_iterators(&argv);
        assert!(cl.has_argv0());
        assert_eq!(&argv[0], cl.argv0());
        assert_eq!(&vec![optv("flag", "value")], cl.options());
        assert_eq!(&vec![argv[2].clone()], cl.positional_args());
        assert_eq!("value", cl.get_option_value_with_default("flag", "nope"));
    }

    {
        let argv: Vec<String> = Vec::new();

        let cl = command_line_from_iterators(&argv);
        assert!(!cl.has_argv0());
        assert_eq!("", cl.argv0());
        assert_eq!(&Vec::<Option>::new(), cl.options());
        assert_eq!(&Vec::<String>::new(), cl.positional_args());
    }

    {
        let argv = [""];

        let cl = command_line_from_iterators(&argv);
        assert!(cl.has_argv0());
        assert_eq!("", cl.argv0());
        assert_eq!(&Vec::<Option>::new(), cl.options());
        assert_eq!(&Vec::<String>::new(), cl.positional_args());
    }

    {
        let argv: Vec<&str> = vec!["my_program", "--flag=value", "arg"];

        let cl = command_line_from_iterators(&argv);
        assert!(cl.has_argv0());
        assert_eq!(argv[0], cl.argv0());
        assert_eq!(&vec![optv("flag", "value")], cl.options());
        assert_eq!(&strings(&[argv[2]]), cl.positional_args());
        assert_eq!("value", cl.get_option_value_with_default("flag", "nope"));
    }
}

#[test]
fn command_line_from_argc_argv_test() {
    let argv = ["my_program", "--flag=value", "arg"];

    let cl = command_line_from_argc_argv(&argv);
    assert!(cl.has_argv0());
    assert_eq!(argv[0], cl.argv0());
    assert_eq!(&vec![optv("flag", "value")], cl.options());
    assert_eq!(&strings(&[argv[2]]), cl.positional_args());
    assert_eq!("value", cl.get_option_value_with_default("flag", "nope"));
}

#[test]
fn command_line_from_initializer_list_test() {
    {
        let cl = command_line_from_initializer_list(&["my_program", "--flag=value", "arg"]);
        assert!(cl.has_argv0());
        assert_eq!("my_program", cl.argv0());
        assert_eq!(&vec![optv("flag", "value")], cl.options());
        assert_eq!(&strings(&["arg"]), cl.positional_args());
        assert_eq!("value", cl.get_option_value_with_default("flag", "nope"));
    }

    {
        let il = strings(&["my_program", "--flag=value", "arg"]);
        let cl = command_line_from_initializer_list(&il);
        assert!(cl.has_argv0());
        assert_eq!("my_program", cl.argv0());
        assert_eq!(&vec![optv("flag", "value")], cl.options());
        assert_eq!(&strings(&["arg"]), cl.positional_args());
        assert_eq!("value", cl.get_option_value_with_default("flag", "nope"));
    }
}

#[test]
fn odd_arguments() {
    {
        let cl = command_line_from_initializer_list(&[
            "my_program", "--=", "--=foo", "--bar=", "--==", "--===", "--==x", "arg",
        ]);
        assert!(cl.has_argv0());
        assert_eq!("my_program", cl.argv0());
        let expected_options =
            vec![opt("="), opt("=foo"), opt("bar"), opt("="), optv("=", "="), optv("=", "x")];
        assert_eq!(&expected_options, cl.options());
        assert_eq!(&strings(&["arg"]), cl.positional_args());
    }

    {
        let cl = command_line_from_initializer_list(&["", "-x"]);
        assert!(cl.has_argv0());
        assert_eq!("", cl.argv0());
        assert_eq!(&Vec::<Option>::new(), cl.options());
        assert_eq!(&strings(&["-x"]), cl.positional_args());
    }

    {
        let cl = command_line_from_initializer_list(&["", "-"]);
        assert!(cl.has_argv0());
        assert_eq!("", cl.argv0());
        assert_eq!(&Vec::<Option>::new(), cl.options());
        assert_eq!(&strings(&["-"]), cl.positional_args());
    }

    {
        let cl = command_line_from_initializer_list(&[
            "",
            "--flag=value",
            "--",
            "--not-a-flag",
            "arg",
            "--",
        ]);
        assert!(cl.has_argv0());
        assert_eq!("", cl.argv0());
        assert_eq!(&vec![optv("flag", "value")], cl.options());
        assert_eq!(&strings(&["--not-a-flag", "arg", "--"]), cl.positional_args());
    }
}

#[test]
fn multiple_occurrences_of_option() {
    let cl = command_line_from_initializer_list(&[
        "my_program",
        "--flag1=value1",
        "--flag2=value2",
        "--flag1=value3",
    ]);
    let expected_options =
        vec![optv("flag1", "value1"), optv("flag2", "value2"), optv("flag1", "value3")];
    assert_eq!(&expected_options, cl.options());
    assert_eq!("value3", cl.get_option_value_with_default("flag1", "nope"));
    assert_eq!("value2", cl.get_option_value_with_default("flag2", "nope"));
    let values = cl.get_option_values("flag1");
    assert_eq!(2, values.len());
    assert_eq!("value1", values[0]);
    assert_eq!("value3", values[1]);
}

fn expect_not_equal(message: &str, c1: &[&str], c2: &[&str]) {
    let cl1 = command_line_from_initializer_list(c1);
    let cl2 = command_line_from_initializer_list(c2);

    assert!(cl1 == cl1, "{message}");
    assert!(!(cl1 != cl1), "{message}");
    assert!(cl2 == cl2, "{message}");
    assert!(!(cl2 != cl2), "{message}");

    assert!(!(cl1 == cl2), "{message}");
    assert!(cl1 != cl2, "{message}");
    assert!(!(cl2 == cl1), "{message}");
    assert!(cl2 != cl1, "{message}");
}

fn expect_equal(message: &str, c1: &[&str], c2: &[&str]) {
    let cl1 = command_line_from_initializer_list(c1);
    let cl2 = command_line_from_initializer_list(c2);

    assert!(cl1 == cl1, "{message}");
    assert!(!(cl1 != cl1), "{message}");
    assert!(cl2 == cl2, "{message}");
    assert!(!(cl2 != cl2), "{message}");

    assert!(cl1 == cl2, "{message}");
    assert!(!(cl1 != cl2), "{message}");
    assert!(cl2 == cl1, "{message}");
    assert!(!(cl2 != cl1), "{message}");
}

#[test]
fn comparison_operators() {
    expect_not_equal("1", &[], &[""]);
    expect_not_equal("2", &["abc"], &["def"]);
    expect_not_equal("3", &["abc", "--flag"], &["abc"]);
    expect_not_equal("4", &["abc", "--flag1"], &["abc", "--flag2"]);
    expect_not_equal("5", &["abc", "--flag1", "--flag2"], &["abc", "--flag1"]);
    expect_not_equal("6", &["abc", "arg"], &["abc"]);
    expect_not_equal("7", &["abc", "arg1"], &["abc", "arg2"]);
    expect_not_equal("8", &["abc", "arg1", "arg2"], &["abc", "arg1"]);
    expect_not_equal("9", &["abc", "--flag", "arg1"], &["abc", "--flag", "arg2"]);

    expect_equal("10", &["abc", "--flag", "arg"], &["abc", "--flag", "--", "arg"]);
}

#[test]
fn move_and_copy() {
    let cl = command_line_from_initializer_list(&["my_program", "--flag1=value1", "--flag2", "arg"]);

    let cl2 = cl.clone();
    assert_eq!(cl, cl2);
    assert_eq!("value1", cl2.get_option_value_with_default("flag1", "nope"));

    let cl3 = cl2;
    assert_eq!(cl, cl3);
    assert_eq!("value1", cl3.get_option_value_with_default("flag1", "nope"));

    let mut cl4 = CommandLine::new();
    assert_ne!(cl, cl4);
    cl4 = cl.clone();
    assert_eq!(cl, cl4);
    assert_eq!("value1", cl4.get_option_value_with_default("flag1", "nope"));

    let mut cl5 = CommandLine::new();
    assert_ne!(cl, cl5);
    cl5 = cl4;
    assert_eq!(cl, cl5);
    assert_eq!("value1", cl5.get_option_value_with_default("flag1", "nope"));
}

fn to_argv_helper(message: &str, c: &[&str]) {
    let argv = strings(c);
    let cl = command_line_from_initializer_list(c);
    assert_eq!(argv, command_line_to_argv(&cl), "{message}");
}

#[test]
fn command_line_to_argv_test() {
    to_argv_helper("1", &[]);
    to_argv_helper("2", &[""]);
    to_argv_helper("3", &["my_program"]);
    to_argv_helper("4", &["my_program", "--flag"]);
    to_argv_helper("5", &["my_program", "--flag1", "--flag2=value"]);
    to_argv_helper("6", &["my_program", "arg"]);
    to_argv_helper("7", &["my_program", "arg1", "arg2"]);
    to_argv_helper("8", &["my_program", "--flag1", "--flag2=value", "arg1", "arg2"]);
    to_argv_helper("9", &["my_program", "--flag", "--", "--not-a-flag"]);
    to_argv_helper("10", &["my_program", "--flag", "arg", "--"]);

    {
        let cl = command_line_from_initializer_list(&["my_program", "--"]);
        assert_eq!(strings(&["my_program"]), command_line_to_argv(&cl));
    }
    {
        let cl = command_line_from_initializer_list(&["my_program", "--flag", "--", "arg"]);
        assert_eq!(strings(&["my_program", "--flag", "arg"]), command_line_to_argv(&cl));
    }
}

// Not upstream's: an option is looked up up to the first NUL of the name
// asked for (upstream's `find(name.data())`), while GetOptionValues
// compares whole names.
#[test]
fn lookup_stops_at_nul() {
    let cl = command_line_from_initializer_list(&["p", "--a=1", "--a\0b=2"]);
    assert_eq!(cl.has_option("a\0b"), Some(0));
    assert_eq!(cl.get_option_values("a\0b"), vec!["2"]);
    assert_eq!(cl.get_option_value_with_default("a\0zzz", "d"), "1");
}
