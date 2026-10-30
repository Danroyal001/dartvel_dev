// Port of lib/src/messages/diagnostic.dart and its part diagnostic.g.dart.
//
// Upstream generates diagnostic.g.dart from pkg/front_end/messages.yaml; this
// file was translated from it mechanically, one item per upstream item, in
// the same order and with the same names. A `MessageCode` is a constant; a
// `Template` is a constant whose `with_arguments` is the upstream
// `_withArguments...` function, taking its named arguments positionally in
// the order upstream declares them, after a `&TokenStore` when one of them
// is a token. The analyzer and severity mappings are not carried (see
// codes.rs).
#![allow(non_upper_case_globals, non_snake_case)]

use std::borrow::Cow;

use crate::messages::codes::{Code, Message, MessageCode, Template};
use crate::messages::conversions;
use crate::scanner::token::{TokenId, TokenStore};

pub const abstractClassMember: MessageCode = MessageCode {
    name: "AbstractClassMember",
    problem_message: "Members of classes can't be declared to be 'abstract'.",
    correction_message: Some(
        "Try removing the 'abstract' keyword. You can add the 'abstract' keyword before the class declaration.",
    ),
};

pub const abstractExtensionField: MessageCode = MessageCode {
    name: "AbstractExtensionField",
    problem_message: "Extension fields can't be declared 'abstract'.",
    correction_message: Some("Try removing the 'abstract' keyword."),
};

pub const abstractExternalField: MessageCode = MessageCode {
    name: "AbstractExternalField",
    problem_message: "Fields can't be declared both 'abstract' and 'external'.",
    correction_message: Some("Try removing the 'abstract' or 'external' keyword."),
};

pub const abstractFinalBaseClass: MessageCode = MessageCode {
    name: "AbstractFinalBaseClass",
    problem_message: "An 'abstract' class can't be declared as both 'final' and 'base'.",
    correction_message: Some("Try removing either the 'final' or 'base' keyword."),
};

pub const abstractFinalInterfaceClass: MessageCode = MessageCode {
    name: "AbstractFinalInterfaceClass",
    problem_message: "An 'abstract' class can't be declared as both 'final' and 'interface'.",
    correction_message: Some("Try removing either the 'final' or 'interface' keyword."),
};

pub const abstractLateField: MessageCode = MessageCode {
    name: "AbstractLateField",
    problem_message: "Abstract fields cannot be late.",
    correction_message: Some("Try removing the 'abstract' or 'late' keyword."),
};

pub const abstractNotSync: MessageCode = MessageCode {
    name: "AbstractNotSync",
    problem_message: "Abstract methods can't use 'async', 'async*', or 'sync*'.",
    correction_message: None,
};

pub const abstractSealedClass: MessageCode = MessageCode {
    name: "AbstractSealedClass",
    problem_message: "A 'sealed' class can't be marked 'abstract' because it's already implicitly abstract.",
    correction_message: Some("Try removing the 'abstract' keyword."),
};

pub const abstractStaticField: MessageCode = MessageCode {
    name: "AbstractStaticField",
    problem_message: "Static fields can't be declared 'abstract'.",
    correction_message: Some("Try removing the 'abstract' or 'static' keyword."),
};

pub const annotationOnTypeArgument: MessageCode = MessageCode {
    name: "AnnotationOnTypeArgument",
    problem_message: "Type arguments can't have annotations because they aren't declarations.",
    correction_message: None,
};

pub const anonymousMethodWrongParameterList: MessageCode = MessageCode {
    name: "AnonymousMethodWrongParameterList",
    problem_message: "An anonymous method with a parameter list must have exactly one required, positional parameter.",
    correction_message: Some(
        "Try removing the parameter list, or changing it to have exactly one required positional parameter.",
    ),
};

pub const asciiControlCharacter: Template<fn(i64) -> Message> = Template {
    name: "AsciiControlCharacter",
    with_arguments: _withArgumentsAsciiControlCharacter,
};

fn _withArgumentsAsciiControlCharacter(character: i64) -> Message {
    let character_0 = conversions::code_point_to_unicode(character);
    Message {
        code: Code {
            name: asciiControlCharacter.name,
        },
        problem_message: Cow::Owned(format!(
            "The control character {character_0} can only be used in strings and comments."
        )),
        correction_message: None,
    }
}

pub const assertAsExpression: MessageCode = MessageCode {
    name: "AssertAsExpression",
    problem_message: "`assert` can't be used as an expression.",
    correction_message: None,
};

pub const assignmentToPrimaryConstructorParameter: MessageCode = MessageCode {
    name: "AssignmentToPrimaryConstructorParameter",
    problem_message: "A primary constructor parameter can't be assigned to in an initializer.",
    correction_message: Some("Try removing the assignment."),
};

pub const augmentationExtendsClauseAlreadyPresent: MessageCode = MessageCode {
    name: "AugmentationExtendsClauseAlreadyPresent",
    problem_message: "The augmentation has an 'extends' clause, but an augmentation target already includes an 'extends' clause and it isn't allowed to be repeated or changed.",
    correction_message: Some(
        "Try removing the 'extends' clause, either here or in the augmentation target.",
    ),
};

pub const awaitAsIdentifier: MessageCode = MessageCode {
    name: "AwaitAsIdentifier",
    problem_message: "'await' can't be used as an identifier in 'async', 'async*', or 'sync*' methods.",
    correction_message: None,
};

pub const awaitForNotAsync: MessageCode = MessageCode {
    name: "AwaitForNotAsync",
    problem_message: "The asynchronous for-in can only be used in functions marked with 'async' or 'async*'.",
    correction_message: Some(
        "Try marking the function body with either 'async' or 'async*', or removing the 'await' before the for loop.",
    ),
};

pub const awaitNotAsync: MessageCode = MessageCode {
    name: "AwaitNotAsync",
    problem_message: "'await' can only be used in 'async' or 'async*' methods.",
    correction_message: None,
};

pub const baseEnum: MessageCode = MessageCode {
    name: "BaseEnum",
    problem_message: "Enums can't be declared to be 'base'.",
    correction_message: Some("Try removing the keyword 'base'."),
};

pub const binaryOperatorWrittenOut: Template<fn(&str, &str) -> Message> = Template {
    name: "BinaryOperatorWrittenOut",
    with_arguments: _withArgumentsBinaryOperatorWrittenOut,
};

fn _withArgumentsBinaryOperatorWrittenOut(
    actual_operator: &str,
    expected_operator: &str,
) -> Message {
    let actualOperator_0 = conversions::validate_string(actual_operator);
    let expectedOperator_0 = conversions::validate_string(expected_operator);
    Message {
        code: Code {
            name: binaryOperatorWrittenOut.name,
        },
        problem_message: Cow::Owned(format!(
            "Binary operator '{actualOperator_0}' is written as '{expectedOperator_0}' instead of the written out word."
        )),
        correction_message: Some(Cow::Owned(format!(
            "Try replacing '{actualOperator_0}' with '{expectedOperator_0}'."
        ))),
    }
}

pub const breakOutsideOfLoop: MessageCode = MessageCode {
    name: "BreakOutsideOfLoop",
    problem_message: "A break statement can't be used outside of a loop or switch statement.",
    correction_message: Some("Try removing the break statement."),
};

pub const builtInIdentifierAsType: Template<fn(&TokenStore, TokenId) -> Message> = Template {
    name: "BuiltInIdentifierAsType",
    with_arguments: _withArgumentsBuiltInIdentifierAsType,
};

fn _withArgumentsBuiltInIdentifierAsType(tokens: &TokenStore, lexeme: TokenId) -> Message {
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: builtInIdentifierAsType.name,
        },
        problem_message: Cow::Owned(format!(
            "The built-in identifier '{lexeme_0}' can't be used as a type."
        )),
        correction_message: None,
    }
}

pub const builtInIdentifierInDeclaration: Template<fn(&TokenStore, TokenId) -> Message> =
    Template {
        name: "BuiltInIdentifierInDeclaration",
        with_arguments: _withArgumentsBuiltInIdentifierInDeclaration,
    };

fn _withArgumentsBuiltInIdentifierInDeclaration(tokens: &TokenStore, lexeme: TokenId) -> Message {
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: builtInIdentifierInDeclaration.name,
        },
        problem_message: Cow::Owned(format!("Can't use '{lexeme_0}' as a name here.")),
        correction_message: None,
    }
}

pub const catchSyntax: MessageCode = MessageCode {
    name: "CatchSyntax",
    problem_message: "'catch' must be followed by '(identifier)' or '(identifier, identifier)'.",
    correction_message: Some(
        "No types are needed, the first is given by 'on', the second is always 'StackTrace'.",
    ),
};

pub const catchSyntaxExtraParameters: MessageCode = MessageCode {
    name: "CatchSyntaxExtraParameters",
    problem_message: "'catch' must be followed by '(identifier)' or '(identifier, identifier)'.",
    correction_message: Some(
        "No types are needed, the first is given by 'on', the second is always 'StackTrace'.",
    ),
};

pub const classInClass: MessageCode = MessageCode {
    name: "ClassInClass",
    problem_message: "Classes can't be declared inside other classes.",
    correction_message: Some("Try moving the class to the top-level."),
};

pub const colonInPlaceOfIn: MessageCode = MessageCode {
    name: "ColonInPlaceOfIn",
    problem_message: "For-in loops use 'in' rather than a colon.",
    correction_message: Some("Try replacing the colon with the keyword 'in'."),
};

pub const conflictingModifiers: Template<fn(&str, &str) -> Message> = Template {
    name: "ConflictingModifiers",
    with_arguments: _withArgumentsConflictingModifiers,
};

fn _withArgumentsConflictingModifiers(modifier: &str, earlier_modifier: &str) -> Message {
    let modifier_0 = conversions::validate_string(modifier);
    let earlierModifier_0 = conversions::validate_string(earlier_modifier);
    Message {
        code: Code {
            name: conflictingModifiers.name,
        },
        problem_message: Cow::Owned(format!(
            "Members can't be declared to be both '{modifier_0}' and '{earlierModifier_0}'."
        )),
        correction_message: Some(Cow::Borrowed("Try removing one of the keywords.")),
    }
}

pub const constAndFinal: MessageCode = MessageCode {
    name: "ConstAndFinal",
    problem_message: "Members can't be declared to be both 'const' and 'final'.",
    correction_message: Some("Try removing either the 'const' or 'final' keyword."),
};

pub const constClass: MessageCode = MessageCode {
    name: "ConstClass",
    problem_message: "Classes can't be declared to be 'const'.",
    correction_message: Some(
        "Try removing the 'const' keyword. If you're trying to indicate that instances of the class can be constants, place the 'const' keyword on  the class' constructor(s).",
    ),
};

pub const constConstructorWithBody: MessageCode = MessageCode {
    name: "ConstConstructorWithBody",
    problem_message: "A const constructor can't have a body.",
    correction_message: Some("Try removing either the 'const' keyword or the body."),
};

pub const constFactory: MessageCode = MessageCode {
    name: "ConstFactory",
    problem_message: "Only redirecting factory constructors can be declared to be 'const'.",
    correction_message: Some(
        "Try removing the 'const' keyword, or replacing the body with '=' followed by a valid target.",
    ),
};

pub const constFieldWithoutInitializer: Template<fn(&str) -> Message> = Template {
    name: "ConstFieldWithoutInitializer",
    with_arguments: _withArgumentsConstFieldWithoutInitializer,
};

fn _withArgumentsConstFieldWithoutInitializer(name: &str) -> Message {
    let name_0 = conversions::validate_and_demangle_name(name);
    Message {
        code: Code {
            name: constFieldWithoutInitializer.name,
        },
        problem_message: Cow::Owned(format!(
            "The const variable '{name_0}' must be initialized."
        )),
        correction_message: Some(Cow::Borrowed(
            "Try adding an initializer ('= expression') to the declaration.",
        )),
    }
}

pub const constMethod: MessageCode = MessageCode {
    name: "ConstMethod",
    problem_message: "Getters, setters and methods can't be declared to be 'const'.",
    correction_message: Some("Try removing the 'const' keyword."),
};

pub const constWithoutPrimaryConstructor: MessageCode = MessageCode {
    name: "ConstWithoutPrimaryConstructor",
    problem_message: "'const' can only be used together with a primary constructor declaration.",
    correction_message: Some(
        "Try removing the 'const' keyword or adding a primary constructor declaration.",
    ),
};

pub const constructorWithReturnType: MessageCode = MessageCode {
    name: "ConstructorWithReturnType",
    problem_message: "Constructors can't have a return type.",
    correction_message: Some("Try removing the return type."),
};

pub const constructorWithTypeArguments: MessageCode = MessageCode {
    name: "ConstructorWithTypeArguments",
    problem_message: "A constructor invocation can't have type arguments after the constructor name.",
    correction_message: Some(
        "Try removing the type arguments or placing them after the class name.",
    ),
};

pub const constructorWithTypeParameters: MessageCode = MessageCode {
    name: "ConstructorWithTypeParameters",
    problem_message: "Constructors can't have type parameters.",
    correction_message: Some("Try removing the type parameters."),
};

pub const constructorWithWrongName: MessageCode = MessageCode {
    name: "ConstructorWithWrongName",
    problem_message: "The name of a constructor must match the name of the enclosing class.",
    correction_message: None,
};

pub const continueOutsideOfLoop: MessageCode = MessageCode {
    name: "ContinueOutsideOfLoop",
    problem_message: "A continue statement can't be used outside of a loop or switch statement.",
    correction_message: Some("Try removing the continue statement."),
};

pub const continueWithoutLabelInCase: MessageCode = MessageCode {
    name: "ContinueWithoutLabelInCase",
    problem_message: "A continue statement in a switch statement must have a label as a target.",
    correction_message: Some(
        "Try adding a label associated with one of the case clauses to the continue statement.",
    ),
};

pub const covariantAndStatic: MessageCode = MessageCode {
    name: "CovariantAndStatic",
    problem_message: "Members can't be declared to be both 'covariant' and 'static'.",
    correction_message: Some("Try removing either the 'covariant' or 'static' keyword."),
};

pub const covariantMember: MessageCode = MessageCode {
    name: "CovariantMember",
    problem_message: "Getters, setters and methods can't be declared to be 'covariant'.",
    correction_message: Some("Try removing the 'covariant' keyword."),
};

pub const defaultInSwitchExpression: MessageCode = MessageCode {
    name: "DefaultInSwitchExpression",
    problem_message: "A switch expression may not use the `default` keyword.",
    correction_message: Some("Try replacing `default` with `_`."),
};

pub const defaultValueAlreadySpecifiedInAugmentationChain: MessageCode = MessageCode {
    name: "DefaultValueAlreadySpecifiedInAugmentationChain",
    problem_message: "The default value for this optional parameter was already specified in the augmentation chain.",
    correction_message: Some("Try removing all but one of the default values."),
};

pub const deferredAfterPrefix: MessageCode = MessageCode {
    name: "DeferredAfterPrefix",
    problem_message: "The deferred keyword should come immediately before the prefix ('as' clause).",
    correction_message: Some("Try moving the deferred keyword before the prefix."),
};

pub const directiveAfterDeclaration: MessageCode = MessageCode {
    name: "DirectiveAfterDeclaration",
    problem_message: "Directives must appear before any declarations.",
    correction_message: Some("Try moving the directive before any declarations."),
};

pub const duplicateDeferred: MessageCode = MessageCode {
    name: "DuplicateDeferred",
    problem_message: "An import directive can only have one 'deferred' keyword.",
    correction_message: Some("Try removing all but one 'deferred' keyword."),
};

pub const duplicateLabelInSwitchStatement: Template<fn(&str) -> Message> = Template {
    name: "DuplicateLabelInSwitchStatement",
    with_arguments: _withArgumentsDuplicateLabelInSwitchStatement,
};

fn _withArgumentsDuplicateLabelInSwitchStatement(label_name: &str) -> Message {
    let labelName_0 = conversions::validate_and_demangle_name(label_name);
    Message {
        code: Code {
            name: duplicateLabelInSwitchStatement.name,
        },
        problem_message: Cow::Owned(format!(
            "The label '{labelName_0}' was already used in this switch statement."
        )),
        correction_message: Some(Cow::Borrowed(
            "Try choosing a different name for this label.",
        )),
    }
}

pub const duplicatePrefix: MessageCode = MessageCode {
    name: "DuplicatePrefix",
    problem_message: "An import directive can only have one prefix ('as' clause).",
    correction_message: Some("Try removing all but one prefix."),
};

pub const duplicatedModifier: Template<fn(&TokenStore, TokenId) -> Message> = Template {
    name: "DuplicatedModifier",
    with_arguments: _withArgumentsDuplicatedModifier,
};

fn _withArgumentsDuplicatedModifier(tokens: &TokenStore, lexeme: TokenId) -> Message {
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: duplicatedModifier.name,
        },
        problem_message: Cow::Owned(format!("The modifier '{lexeme_0}' was already specified.")),
        correction_message: Some(Cow::Borrowed(
            "Try removing all but one occurrence of the modifier.",
        )),
    }
}

pub const emptyNamedParameterList: MessageCode = MessageCode {
    name: "EmptyNamedParameterList",
    problem_message: "Named parameter lists cannot be empty.",
    correction_message: Some("Try adding a named parameter to the list."),
};

pub const emptyOptionalParameterList: MessageCode = MessageCode {
    name: "EmptyOptionalParameterList",
    problem_message: "Optional parameter lists cannot be empty.",
    correction_message: Some("Try adding an optional parameter to the list."),
};

pub const emptyRecordTypeNamedFieldsList: MessageCode = MessageCode {
    name: "EmptyRecordTypeNamedFieldsList",
    problem_message: "The list of named fields in a record type can't be empty.",
    correction_message: Some("Try adding a named field to the list."),
};

pub const encoding: MessageCode = MessageCode {
    name: "Encoding",
    problem_message: "Unable to decode bytes as UTF-8.",
    correction_message: None,
};

pub const enumInClass: MessageCode = MessageCode {
    name: "EnumInClass",
    problem_message: "Enums can't be declared inside classes.",
    correction_message: Some("Try moving the enum to the top-level."),
};

pub const equalityCannotBeEqualityOperand: MessageCode = MessageCode {
    name: "EqualityCannotBeEqualityOperand",
    problem_message: "A comparison expression can't be an operand of another comparison expression.",
    correction_message: Some("Try putting parentheses around one of the comparisons."),
};

pub const expectedAfterButGot: Template<fn(&str) -> Message> = Template {
    name: "ExpectedAfterButGot",
    with_arguments: _withArgumentsExpectedAfterButGot,
};

fn _withArgumentsExpectedAfterButGot(expected: &str) -> Message {
    let expected_0 = conversions::validate_string(expected);
    Message {
        code: Code {
            name: expectedAfterButGot.name,
        },
        problem_message: Cow::Owned(format!("Expected '{expected_0}' after this.")),
        correction_message: None,
    }
}

pub const expectedAnInitializer: MessageCode = MessageCode {
    name: "ExpectedAnInitializer",
    problem_message: "Expected an initializer.",
    correction_message: None,
};

pub const expectedBody: MessageCode = MessageCode {
    name: "ExpectedBody",
    problem_message: "Expected a function body or '=>'.",
    correction_message: Some("Try adding {}."),
};

pub const expectedButGot: Template<fn(&str) -> Message> = Template {
    name: "ExpectedButGot",
    with_arguments: _withArgumentsExpectedButGot,
};

fn _withArgumentsExpectedButGot(expected: &str) -> Message {
    let expected_0 = conversions::validate_string(expected);
    Message {
        code: Code {
            name: expectedButGot.name,
        },
        problem_message: Cow::Owned(format!("Expected '{expected_0}' before this.")),
        correction_message: None,
    }
}

pub const expectedButGot2: Template<fn(&str, &str) -> Message> = Template {
    name: "ExpectedButGot2",
    with_arguments: _withArgumentsExpectedButGot2,
};

fn _withArgumentsExpectedButGot2(expected: &str, expected2: &str) -> Message {
    let expected_0 = conversions::validate_string(expected);
    let expected2_0 = conversions::validate_string(expected2);
    Message {
        code: Code {
            name: expectedButGot2.name,
        },
        problem_message: Cow::Owned(format!(
            "Expected '{expected_0}' or '{expected2_0}' before this."
        )),
        correction_message: None,
    }
}

pub const expectedCatchClauseBody: MessageCode = MessageCode {
    name: "ExpectedCatchClauseBody",
    problem_message: "A catch clause must have a body, even if it is empty.",
    correction_message: Some("Try adding an empty body."),
};

pub const expectedClassBody: MessageCode = MessageCode {
    name: "ExpectedClassBody",
    problem_message: "A class declaration must have a body, even if it is empty.",
    correction_message: Some("Try adding an empty body."),
};

pub const expectedClassMember: Template<fn(&TokenStore, TokenId) -> Message> = Template {
    name: "ExpectedClassMember",
    with_arguments: _withArgumentsExpectedClassMember,
};

fn _withArgumentsExpectedClassMember(tokens: &TokenStore, lexeme: TokenId) -> Message {
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: expectedClassMember.name,
        },
        problem_message: Cow::Owned(format!("Expected a class member, but got '{lexeme_0}'.")),
        correction_message: None,
    }
}

pub const expectedDeclaration: Template<fn(&TokenStore, TokenId) -> Message> = Template {
    name: "ExpectedDeclaration",
    with_arguments: _withArgumentsExpectedDeclaration,
};

fn _withArgumentsExpectedDeclaration(tokens: &TokenStore, lexeme: TokenId) -> Message {
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: expectedDeclaration.name,
        },
        problem_message: Cow::Owned(format!("Expected a declaration, but got '{lexeme_0}'.")),
        correction_message: None,
    }
}

pub const expectedElseOrComma: MessageCode = MessageCode {
    name: "ExpectedElseOrComma",
    problem_message: "Expected 'else' or comma.",
    correction_message: None,
};

pub const expectedEnumBody: Template<fn(&TokenStore, TokenId) -> Message> = Template {
    name: "ExpectedEnumBody",
    with_arguments: _withArgumentsExpectedEnumBody,
};

fn _withArgumentsExpectedEnumBody(tokens: &TokenStore, lexeme: TokenId) -> Message {
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: expectedEnumBody.name,
        },
        problem_message: Cow::Owned(format!("Expected a enum body, but got '{lexeme_0}'.")),
        correction_message: Some(Cow::Borrowed(
            "An enum definition must have a body with at least one constant name.",
        )),
    }
}

pub const expectedExtensionBody: MessageCode = MessageCode {
    name: "ExpectedExtensionBody",
    problem_message: "An extension declaration must have a body, even if it is empty.",
    correction_message: Some("Try adding an empty body."),
};

pub const expectedExtensionTypeBody: MessageCode = MessageCode {
    name: "ExpectedExtensionTypeBody",
    problem_message: "An extension type declaration must have a body, even if it is empty.",
    correction_message: Some("Try adding an empty body."),
};

pub const expectedFinallyClauseBody: MessageCode = MessageCode {
    name: "ExpectedFinallyClauseBody",
    problem_message: "A finally clause must have a body, even if it is empty.",
    correction_message: Some("Try adding an empty body."),
};

pub const expectedFunctionBody: Template<fn(&TokenStore, TokenId) -> Message> = Template {
    name: "ExpectedFunctionBody",
    with_arguments: _withArgumentsExpectedFunctionBody,
};

fn _withArgumentsExpectedFunctionBody(tokens: &TokenStore, lexeme: TokenId) -> Message {
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: expectedFunctionBody.name,
        },
        problem_message: Cow::Owned(format!("Expected a function body, but got '{lexeme_0}'.")),
        correction_message: None,
    }
}

pub const expectedHexDigit: MessageCode = MessageCode {
    name: "ExpectedHexDigit",
    problem_message: "A hex digit (0-9 or A-F) must follow '0x'.",
    correction_message: None,
};

pub const expectedIdentifier: Template<fn(&TokenStore, TokenId) -> Message> = Template {
    name: "ExpectedIdentifier",
    with_arguments: _withArgumentsExpectedIdentifier,
};

fn _withArgumentsExpectedIdentifier(tokens: &TokenStore, lexeme: TokenId) -> Message {
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: expectedIdentifier.name,
        },
        problem_message: Cow::Owned(format!("Expected an identifier, but got '{lexeme_0}'.")),
        correction_message: Some(Cow::Owned(format!(
            "Try inserting an identifier before '{lexeme_0}'."
        ))),
    }
}

pub const expectedIdentifierButGotKeyword: Template<fn(&TokenStore, TokenId) -> Message> =
    Template {
        name: "ExpectedIdentifierButGotKeyword",
        with_arguments: _withArgumentsExpectedIdentifierButGotKeyword,
    };

fn _withArgumentsExpectedIdentifierButGotKeyword(tokens: &TokenStore, lexeme: TokenId) -> Message {
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: expectedIdentifierButGotKeyword.name,
        },
        problem_message: Cow::Owned(format!(
            "'{lexeme_0}' can't be used as an identifier because it's a keyword."
        )),
        correction_message: Some(Cow::Borrowed(
            "Try renaming this to be an identifier that isn't a keyword.",
        )),
    }
}

pub const expectedInstead: Template<fn(&str) -> Message> = Template {
    name: "ExpectedInstead",
    with_arguments: _withArgumentsExpectedInstead,
};

fn _withArgumentsExpectedInstead(expected: &str) -> Message {
    let expected_0 = conversions::validate_string(expected);
    Message {
        code: Code {
            name: expectedInstead.name,
        },
        problem_message: Cow::Owned(format!("Expected '{expected_0}' instead of this.")),
        correction_message: None,
    }
}

pub const expectedMixinBody: MessageCode = MessageCode {
    name: "ExpectedMixinBody",
    problem_message: "A mixin declaration must have a body, even if it is empty.",
    correction_message: Some("Try adding an empty body."),
};

pub const expectedStatement: MessageCode = MessageCode {
    name: "ExpectedStatement",
    problem_message: "Expected a statement.",
    correction_message: None,
};

pub const expectedString: Template<fn(&TokenStore, TokenId) -> Message> = Template {
    name: "ExpectedString",
    with_arguments: _withArgumentsExpectedString,
};

fn _withArgumentsExpectedString(tokens: &TokenStore, lexeme: TokenId) -> Message {
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: expectedString.name,
        },
        problem_message: Cow::Owned(format!("Expected a String, but got '{lexeme_0}'.")),
        correction_message: None,
    }
}

pub const expectedSwitchExpressionBody: MessageCode = MessageCode {
    name: "ExpectedSwitchExpressionBody",
    problem_message: "A switch expression must have a body, even if it is empty.",
    correction_message: Some("Try adding an empty body."),
};

pub const expectedSwitchStatementBody: MessageCode = MessageCode {
    name: "ExpectedSwitchStatementBody",
    problem_message: "A switch statement must have a body, even if it is empty.",
    correction_message: Some("Try adding an empty body."),
};

pub const expectedToken: Template<fn(&str) -> Message> = Template {
    name: "ExpectedToken",
    with_arguments: _withArgumentsExpectedToken,
};

fn _withArgumentsExpectedToken(expected: &str) -> Message {
    let expected_0 = conversions::validate_string(expected);
    Message {
        code: Code {
            name: expectedToken.name,
        },
        problem_message: Cow::Owned(format!("Expected to find '{expected_0}'.")),
        correction_message: None,
    }
}

pub const expectedTryStatementBody: MessageCode = MessageCode {
    name: "ExpectedTryStatementBody",
    problem_message: "A try statement must have a body, even if it is empty.",
    correction_message: Some("Try adding an empty body."),
};

pub const expectedType: Template<fn(&TokenStore, TokenId) -> Message> = Template {
    name: "ExpectedType",
    with_arguments: _withArgumentsExpectedType,
};

fn _withArgumentsExpectedType(tokens: &TokenStore, lexeme: TokenId) -> Message {
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: expectedType.name,
        },
        problem_message: Cow::Owned(format!("Expected a type, but got '{lexeme_0}'.")),
        correction_message: None,
    }
}

pub const experimentNotEnabled: Template<fn(&str, &str) -> Message> = Template {
    name: "ExperimentNotEnabled",
    with_arguments: _withArgumentsExperimentNotEnabled,
};

fn _withArgumentsExperimentNotEnabled(feature_name: &str, enabled_version: &str) -> Message {
    let featureName_0 = conversions::validate_string(feature_name);
    let enabledVersion_0 = conversions::validate_string(enabled_version);
    Message {
        code: Code {
            name: experimentNotEnabled.name,
        },
        problem_message: Cow::Owned(format!(
            "This requires the '{featureName_0}' language feature to be enabled."
        )),
        correction_message: Some(Cow::Owned(format!(
            "Try updating your pubspec.yaml to set the minimum SDK constraint to {enabledVersion_0} or higher, and running 'pub get'."
        ))),
    }
}

pub const experimentNotEnabledOffByDefault: Template<fn(&str) -> Message> = Template {
    name: "ExperimentNotEnabledOffByDefault",
    with_arguments: _withArgumentsExperimentNotEnabledOffByDefault,
};

fn _withArgumentsExperimentNotEnabledOffByDefault(feature_name: &str) -> Message {
    let featureName_0 = conversions::validate_string(feature_name);
    Message {
        code: Code {
            name: experimentNotEnabledOffByDefault.name,
        },
        problem_message: Cow::Owned(format!(
            "This requires the experimental '{featureName_0}' language feature to be enabled."
        )),
        correction_message: Some(Cow::Owned(format!(
            "Try passing the '--enable-experiment={featureName_0}' command line option."
        ))),
    }
}

pub const exportAfterPart: MessageCode = MessageCode {
    name: "ExportAfterPart",
    problem_message: "Export directives must precede part directives.",
    correction_message: Some("Try moving the export directives before the part directives."),
};

pub const extensionAugmentationHasOnClause: MessageCode = MessageCode {
    name: "ExtensionAugmentationHasOnClause",
    problem_message: "Extension augmentations can't have 'on' clauses.",
    correction_message: Some("Try removing the 'on' clause."),
};

pub const extensionAugmentationWithoutName: MessageCode = MessageCode {
    name: "ExtensionAugmentationWithoutName",
    problem_message: "An extension augmentation must have a name.",
    correction_message: Some("Try adding the name of the extension to augment."),
};

pub const extensionDeclaresAbstractMember: MessageCode = MessageCode {
    name: "ExtensionDeclaresAbstractMember",
    problem_message: "Extensions can't declare abstract members.",
    correction_message: Some("Try providing an implementation for the member."),
};

pub const extensionDeclaresConstructor: MessageCode = MessageCode {
    name: "ExtensionDeclaresConstructor",
    problem_message: "Extensions can't declare constructors.",
    correction_message: Some("Try removing the constructor declaration."),
};

pub const extensionDeclaresInstanceField: MessageCode = MessageCode {
    name: "ExtensionDeclaresInstanceField",
    problem_message: "Extensions can't declare instance fields",
    correction_message: Some("Try removing the field declaration or making it a static field"),
};

pub const extensionPrimaryConstructor: MessageCode = MessageCode {
    name: "ExtensionPrimaryConstructor",
    problem_message: "Extensions can't have primary constructors.",
    correction_message: Some(
        "Try removing the primary constructor or changing the extension to an extension type.",
    ),
};

pub const extensionTypeAugmentationSpecifiesRepresentationField: MessageCode = MessageCode {
    name: "ExtensionTypeAugmentationSpecifiesRepresentationField",
    problem_message: "An extension type augmentation can't specify a representation field.",
    correction_message: Some("Try removing the representation field."),
};

pub const extensionTypeDeclaresInstanceField: MessageCode = MessageCode {
    name: "ExtensionTypeDeclaresInstanceField",
    problem_message: "Extension types can't declare instance fields",
    correction_message: Some("Try removing the field declaration or making it a static field"),
};

pub const extensionTypeExtends: MessageCode = MessageCode {
    name: "ExtensionTypeExtends",
    problem_message: "An extension type declaration can't have an 'extends' clause.",
    correction_message: Some(
        "Try removing the 'extends' clause or replacing the 'extends' with 'implements'.",
    ),
};

pub const extensionTypeWith: MessageCode = MessageCode {
    name: "ExtensionTypeWith",
    problem_message: "An extension type declaration can't have a 'with' clause.",
    correction_message: Some(
        "Try removing the 'with' clause or replacing the 'with' with 'implements'.",
    ),
};

pub const extensionTypeWithAbstractMember: Template<fn(&str, &str) -> Message> = Template {
    name: "ExtensionTypeWithAbstractMember",
    with_arguments: _withArgumentsExtensionTypeWithAbstractMember,
};

fn _withArgumentsExtensionTypeWithAbstractMember(
    method_name: &str,
    extension_type_name: &str,
) -> Message {
    let methodName_0 = conversions::validate_string(method_name);
    let extensionTypeName_0 = conversions::validate_string(extension_type_name);
    Message {
        code: Code {
            name: extensionTypeWithAbstractMember.name,
        },
        problem_message: Cow::Owned(format!(
            "'{methodName_0}' must have a method body because '{extensionTypeName_0}' is an extension type."
        )),
        correction_message: Some(Cow::Owned(format!(
            "Try adding a body to '{methodName_0}'."
        ))),
    }
}

pub const externalClass: MessageCode = MessageCode {
    name: "ExternalClass",
    problem_message: "Classes can't be declared to be 'external'.",
    correction_message: Some("Try removing the keyword 'external'."),
};

pub const externalConstructorWithFieldInitializers: MessageCode = MessageCode {
    name: "ExternalConstructorWithFieldInitializers",
    problem_message: "An external constructor can't initialize fields.",
    correction_message: Some(
        "Try removing the field initializers, or removing the keyword 'external'.",
    ),
};

pub const externalConstructorWithInitializer: MessageCode = MessageCode {
    name: "ExternalConstructorWithInitializer",
    problem_message: "An external constructor can't have any initializers.",
    correction_message: None,
};

pub const externalEnum: MessageCode = MessageCode {
    name: "ExternalEnum",
    problem_message: "Enums can't be declared to be 'external'.",
    correction_message: Some("Try removing the keyword 'external'."),
};

pub const externalFactoryRedirection: MessageCode = MessageCode {
    name: "ExternalFactoryRedirection",
    problem_message: "A redirecting factory can't be external.",
    correction_message: Some("Try removing the 'external' modifier."),
};

pub const externalFactoryWithBody: MessageCode = MessageCode {
    name: "ExternalFactoryWithBody",
    problem_message: "External factories can't have a body.",
    correction_message: Some(
        "Try removing the body of the factory, or removing the keyword 'external'.",
    ),
};

pub const externalLateField: MessageCode = MessageCode {
    name: "ExternalLateField",
    problem_message: "External fields cannot be late.",
    correction_message: Some("Try removing the 'external' or 'late' keyword."),
};

pub const externalMethodWithBody: MessageCode = MessageCode {
    name: "ExternalMethodWithBody",
    problem_message: "An external or native method can't have a body.",
    correction_message: None,
};

pub const externalTypedef: MessageCode = MessageCode {
    name: "ExternalTypedef",
    problem_message: "Typedefs can't be declared to be 'external'.",
    correction_message: Some("Try removing the keyword 'external'."),
};

pub const extraneousModifier: Template<fn(&TokenStore, TokenId) -> Message> = Template {
    name: "ExtraneousModifier",
    with_arguments: _withArgumentsExtraneousModifier,
};

fn _withArgumentsExtraneousModifier(tokens: &TokenStore, lexeme: TokenId) -> Message {
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: extraneousModifier.name,
        },
        problem_message: Cow::Owned(format!("Can't have modifier '{lexeme_0}' here.")),
        correction_message: Some(Cow::Owned(format!("Try removing '{lexeme_0}'."))),
    }
}

pub const extraneousModifierInExtension: Template<fn(&TokenStore, TokenId) -> Message> = Template {
    name: "ExtraneousModifierInExtension",
    with_arguments: _withArgumentsExtraneousModifierInExtension,
};

fn _withArgumentsExtraneousModifierInExtension(tokens: &TokenStore, lexeme: TokenId) -> Message {
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: extraneousModifierInExtension.name,
        },
        problem_message: Cow::Owned(format!("Can't have modifier '{lexeme_0}' in an extension.")),
        correction_message: Some(Cow::Owned(format!("Try removing '{lexeme_0}'."))),
    }
}

pub const extraneousModifierInExtensionType: Template<fn(&TokenStore, TokenId) -> Message> =
    Template {
        name: "ExtraneousModifierInExtensionType",
        with_arguments: _withArgumentsExtraneousModifierInExtensionType,
    };

fn _withArgumentsExtraneousModifierInExtensionType(
    tokens: &TokenStore,
    lexeme: TokenId,
) -> Message {
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: extraneousModifierInExtensionType.name,
        },
        problem_message: Cow::Owned(format!(
            "Can't have modifier '{lexeme_0}' in an extension type."
        )),
        correction_message: Some(Cow::Owned(format!("Try removing '{lexeme_0}'."))),
    }
}

pub const extraneousModifierInPrimaryConstructor: Template<fn(&TokenStore, TokenId) -> Message> =
    Template {
        name: "ExtraneousModifierInPrimaryConstructor",
        with_arguments: _withArgumentsExtraneousModifierInPrimaryConstructor,
    };

fn _withArgumentsExtraneousModifierInPrimaryConstructor(
    tokens: &TokenStore,
    lexeme: TokenId,
) -> Message {
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: extraneousModifierInPrimaryConstructor.name,
        },
        problem_message: Cow::Owned(format!(
            "Can't have modifier '{lexeme_0}' in a primary constructor."
        )),
        correction_message: Some(Cow::Owned(format!("Try removing '{lexeme_0}'."))),
    }
}

pub const factoryConstructorNewName: MessageCode = MessageCode {
    name: "FactoryConstructorNewName",
    problem_message: "Factory constructors can't be named 'new'.",
    correction_message: Some("Try removing the 'new' keyword or changing it to a different name."),
};

pub const factoryNotSync: MessageCode = MessageCode {
    name: "FactoryNotSync",
    problem_message: "Factory bodies can't use 'async', 'async*', or 'sync*'.",
    correction_message: None,
};

pub const factoryTopLevelDeclaration: MessageCode = MessageCode {
    name: "FactoryTopLevelDeclaration",
    problem_message: "Top-level declarations can't be declared to be 'factory'.",
    correction_message: Some("Try removing the keyword 'factory'."),
};

pub const fastaCLIArgumentRequired: Template<fn(&str) -> Message> = Template {
    name: "FastaCLIArgumentRequired",
    with_arguments: _withArgumentsFastaCLIArgumentRequired,
};

fn _withArgumentsFastaCLIArgumentRequired(argument_name: &str) -> Message {
    let argumentName_0 = conversions::validate_and_demangle_name(argument_name);
    Message {
        code: Code {
            name: fastaCLIArgumentRequired.name,
        },
        problem_message: Cow::Owned(format!("Expected value after '{argumentName_0}'.")),
        correction_message: None,
    }
}

pub const fieldInitializedInDeclarationAndInitializerOfPrimaryConstructor: MessageCode =
    MessageCode {
        name: "FieldInitializedInDeclarationAndInitializerOfPrimaryConstructor",
        problem_message: "Fields can't be initialized in both the primary constructor and at their declaration.",
        correction_message: Some("Try removing one of the initializations."),
    };

pub const fieldInitializedInDeclarationAndParameterOfPrimaryConstructor: MessageCode =
    MessageCode {
        name: "FieldInitializedInDeclarationAndParameterOfPrimaryConstructor",
        problem_message: "Fields can't be initialized in both the primary constructor parameter list and at their declaration.",
        correction_message: Some("Try removing one of the initializations."),
    };

pub const fieldInitializedOutsideDeclaringClass: MessageCode = MessageCode {
    name: "FieldInitializedOutsideDeclaringClass",
    problem_message: "A field can only be initialized in its declaring class",
    correction_message: Some(
        "Try passing a value into the superclass constructor, or moving the initialization into the constructor body.",
    ),
};

pub const fieldInitializerOutsideConstructor: MessageCode = MessageCode {
    name: "FieldInitializerOutsideConstructor",
    problem_message: "Field formal parameters can only be used in a constructor.",
    correction_message: Some("Try removing 'this.'."),
};

pub const finalAndCovariant: MessageCode = MessageCode {
    name: "FinalAndCovariant",
    problem_message: "Members can't be declared to be both 'final' and 'covariant'.",
    correction_message: Some("Try removing either the 'final' or 'covariant' keyword."),
};

pub const finalAndCovariantLateWithInitializer: MessageCode = MessageCode {
    name: "FinalAndCovariantLateWithInitializer",
    problem_message: "Members marked 'late' with an initializer can't be declared to be both 'final' and 'covariant'.",
    correction_message: Some(
        "Try removing either the 'final' or 'covariant' keyword, or removing the initializer.",
    ),
};

pub const finalAndVar: MessageCode = MessageCode {
    name: "FinalAndVar",
    problem_message: "Members can't be declared to be both 'final' and 'var'.",
    correction_message: Some("Try removing the keyword 'var'."),
};

pub const finalEnum: MessageCode = MessageCode {
    name: "FinalEnum",
    problem_message: "Enums can't be declared to be 'final'.",
    correction_message: Some("Try removing the keyword 'final'."),
};

pub const finalFieldWithoutInitializer: Template<fn(&str) -> Message> = Template {
    name: "FinalFieldWithoutInitializer",
    with_arguments: _withArgumentsFinalFieldWithoutInitializer,
};

fn _withArgumentsFinalFieldWithoutInitializer(name: &str) -> Message {
    let name_0 = conversions::validate_and_demangle_name(name);
    Message {
        code: Code {
            name: finalFieldWithoutInitializer.name,
        },
        problem_message: Cow::Owned(format!(
            "The final variable '{name_0}' must be initialized."
        )),
        correction_message: Some(Cow::Borrowed(
            "Try adding an initializer ('= expression') to the declaration.",
        )),
    }
}

pub const finalMixin: MessageCode = MessageCode {
    name: "FinalMixin",
    problem_message: "A mixin can't be declared 'final'.",
    correction_message: Some("Try removing the 'final' keyword."),
};

pub const finalMixinClass: MessageCode = MessageCode {
    name: "FinalMixinClass",
    problem_message: "A mixin class can't be declared 'final'.",
    correction_message: Some("Try removing the 'final' keyword."),
};

pub const functionTypeDefaultValue: MessageCode = MessageCode {
    name: "FunctionTypeDefaultValue",
    problem_message: "Can't have a default value in a function type.",
    correction_message: None,
};

pub const functionTypedParameterVar: MessageCode = MessageCode {
    name: "FunctionTypedParameterVar",
    problem_message: "Function-typed parameters can't specify 'const', 'final' or 'var' in place of a return type.",
    correction_message: Some("Try replacing the keyword with a return type."),
};

pub const generatorReturnsValue: MessageCode = MessageCode {
    name: "GeneratorReturnsValue",
    problem_message: "'sync*' and 'async*' can't return a value.",
    correction_message: None,
};

pub const getterConstructor: MessageCode = MessageCode {
    name: "GetterConstructor",
    problem_message: "Constructors can't be a getter.",
    correction_message: Some("Try removing 'get'."),
};

pub const getterWithFormals: MessageCode = MessageCode {
    name: "GetterWithFormals",
    problem_message: "A getter can't have formal parameters.",
    correction_message: Some("Try removing '(...)'."),
};

pub const illegalAssignmentToNonAssignable: MessageCode = MessageCode {
    name: "IllegalAssignmentToNonAssignable",
    problem_message: "Illegal assignment to non-assignable expression.",
    correction_message: None,
};

pub const illegalPatternAssignmentVariableName: Template<fn(&TokenStore, TokenId) -> Message> =
    Template {
        name: "IllegalPatternAssignmentVariableName",
        with_arguments: _withArgumentsIllegalPatternAssignmentVariableName,
    };

fn _withArgumentsIllegalPatternAssignmentVariableName(
    tokens: &TokenStore,
    variable_name: TokenId,
) -> Message {
    let variableName_0 = conversions::token_to_lexeme(tokens, variable_name);
    Message {
        code: Code {
            name: illegalPatternAssignmentVariableName.name,
        },
        problem_message: Cow::Owned(format!(
            "A variable assigned by a pattern assignment can't be named '{variableName_0}'."
        )),
        correction_message: Some(Cow::Borrowed("Choose a different name.")),
    }
}

pub const illegalPatternIdentifierName: Template<fn(&TokenStore, TokenId) -> Message> = Template {
    name: "IllegalPatternIdentifierName",
    with_arguments: _withArgumentsIllegalPatternIdentifierName,
};

fn _withArgumentsIllegalPatternIdentifierName(tokens: &TokenStore, identifier: TokenId) -> Message {
    let identifier_0 = conversions::token_to_lexeme(tokens, identifier);
    Message {
        code: Code {
            name: illegalPatternIdentifierName.name,
        },
        problem_message: Cow::Owned(format!(
            "A pattern can't refer to an identifier named '{identifier_0}'."
        )),
        correction_message: Some(Cow::Borrowed("Match the identifier using '==")),
    }
}

pub const illegalPatternVariableName: Template<fn(&TokenStore, TokenId) -> Message> = Template {
    name: "IllegalPatternVariableName",
    with_arguments: _withArgumentsIllegalPatternVariableName,
};

fn _withArgumentsIllegalPatternVariableName(
    tokens: &TokenStore,
    variable_name: TokenId,
) -> Message {
    let variableName_0 = conversions::token_to_lexeme(tokens, variable_name);
    Message {
        code: Code {
            name: illegalPatternVariableName.name,
        },
        problem_message: Cow::Owned(format!(
            "The variable declared by a variable pattern can't be named '{variableName_0}'."
        )),
        correction_message: Some(Cow::Borrowed("Choose a different name.")),
    }
}

pub const implementsBeforeExtends: MessageCode = MessageCode {
    name: "ImplementsBeforeExtends",
    problem_message: "The extends clause must be before the implements clause.",
    correction_message: Some("Try moving the extends clause before the implements clause."),
};

pub const implementsBeforeOn: MessageCode = MessageCode {
    name: "ImplementsBeforeOn",
    problem_message: "The on clause must be before the implements clause.",
    correction_message: Some("Try moving the on clause before the implements clause."),
};

pub const implementsBeforeWith: MessageCode = MessageCode {
    name: "ImplementsBeforeWith",
    problem_message: "The with clause must be before the implements clause.",
    correction_message: Some("Try moving the with clause before the implements clause."),
};

pub const importAfterPart: MessageCode = MessageCode {
    name: "ImportAfterPart",
    problem_message: "Import directives must precede part directives.",
    correction_message: Some("Try moving the import directives before the part directives."),
};

pub const initializedVariableInForEach: MessageCode = MessageCode {
    name: "InitializedVariableInForEach",
    problem_message: "The loop variable in a for-each loop can't be initialized.",
    correction_message: Some("Try removing the initializer, or using a different kind of loop."),
};

pub const initializingDeclaringParameter: MessageCode = MessageCode {
    name: "InitializingDeclaringParameter",
    problem_message: "Declaring parameters can't be initializing.",
    correction_message: Some(
        "Try removing the `this.` prefix or making the parameter non-declaring.",
    ),
};

pub const interfaceEnum: MessageCode = MessageCode {
    name: "InterfaceEnum",
    problem_message: "Enums can't be declared to be 'interface'.",
    correction_message: Some("Try removing the keyword 'interface'."),
};

pub const interfaceMixin: MessageCode = MessageCode {
    name: "InterfaceMixin",
    problem_message: "A mixin can't be declared 'interface'.",
    correction_message: Some("Try removing the 'interface' keyword."),
};

pub const interfaceMixinClass: MessageCode = MessageCode {
    name: "InterfaceMixinClass",
    problem_message: "A mixin class can't be declared 'interface'.",
    correction_message: Some("Try removing the 'interface' keyword."),
};

pub const internalProblemStackNotEmpty: Template<fn(&str, &str) -> Message> = Template {
    name: "InternalProblemStackNotEmpty",
    with_arguments: _withArgumentsInternalProblemStackNotEmpty,
};

fn _withArgumentsInternalProblemStackNotEmpty(type_name: &str, stack_contents: &str) -> Message {
    let typeName_0 = conversions::validate_and_demangle_name(type_name);
    let stackContents_0 = conversions::validate_string(stack_contents);
    Message {
        code: Code {
            name: internalProblemStackNotEmpty.name,
        },
        problem_message: Cow::Owned(format!(
            "{typeName_0}.stack isn't empty:
  {stackContents_0}"
        )),
        correction_message: None,
    }
}

pub const internalProblemUnhandled: Template<fn(&str, &str) -> Message> = Template {
    name: "InternalProblemUnhandled",
    with_arguments: _withArgumentsInternalProblemUnhandled,
};

fn _withArgumentsInternalProblemUnhandled(what: &str, r#where: &str) -> Message {
    let what_0 = conversions::validate_string(what);
    let where_0 = conversions::validate_string(r#where);
    Message {
        code: Code {
            name: internalProblemUnhandled.name,
        },
        problem_message: Cow::Owned(format!("Unhandled {what_0} in {where_0}.")),
        correction_message: None,
    }
}

pub const internalProblemUnsupported: Template<fn(&str) -> Message> = Template {
    name: "InternalProblemUnsupported",
    with_arguments: _withArgumentsInternalProblemUnsupported,
};

fn _withArgumentsInternalProblemUnsupported(operation: &str) -> Message {
    let operation_0 = conversions::validate_and_demangle_name(operation);
    Message {
        code: Code {
            name: internalProblemUnsupported.name,
        },
        problem_message: Cow::Owned(format!("Unsupported operation: '{operation_0}'.")),
        correction_message: None,
    }
}

pub const interpolationInUri: MessageCode = MessageCode {
    name: "InterpolationInUri",
    problem_message: "Can't use string interpolation in a URI.",
    correction_message: None,
};

pub const invalidAwaitFor: MessageCode = MessageCode {
    name: "InvalidAwaitFor",
    problem_message: "The keyword 'await' isn't allowed for a normal 'for' statement.",
    correction_message: Some("Try removing the keyword, or use a for-each statement."),
};

pub const invalidCodePoint: MessageCode = MessageCode {
    name: "InvalidCodePoint",
    problem_message: "The escape sequence starting with '\\u' isn't a valid code point.",
    correction_message: None,
};

pub const invalidConstantPatternBinary: Template<fn(&str) -> Message> = Template {
    name: "InvalidConstantPatternBinary",
    with_arguments: _withArgumentsInvalidConstantPatternBinary,
};

fn _withArgumentsInvalidConstantPatternBinary(operator_name: &str) -> Message {
    let operatorName_0 = conversions::validate_and_demangle_name(operator_name);
    Message {
        code: Code {
            name: invalidConstantPatternBinary.name,
        },
        problem_message: Cow::Owned(format!(
            "The binary operator {operatorName_0} is not supported as a constant pattern."
        )),
        correction_message: Some(Cow::Borrowed(
            "Try wrapping the expression in 'const ( ... )'.",
        )),
    }
}

pub const invalidConstantPatternConstPrefix: MessageCode = MessageCode {
    name: "InvalidConstantPatternConstPrefix",
    problem_message: "The expression can't be prefixed by 'const' to form a constant pattern.",
    correction_message: Some("Try wrapping the expression in 'const ( ... )' instead."),
};

pub const invalidConstantPatternDuplicateConst: MessageCode = MessageCode {
    name: "InvalidConstantPatternDuplicateConst",
    problem_message: "Duplicate 'const' keyword in constant expression.",
    correction_message: Some("Try removing one of the 'const' keywords."),
};

pub const invalidConstantPatternEmptyRecordLiteral: MessageCode = MessageCode {
    name: "InvalidConstantPatternEmptyRecordLiteral",
    problem_message: "The empty record literal is not supported as a constant pattern.",
    correction_message: None,
};

pub const invalidConstantPatternGeneric: MessageCode = MessageCode {
    name: "InvalidConstantPatternGeneric",
    problem_message: "This expression is not supported as a constant pattern.",
    correction_message: Some("Try wrapping the expression in 'const ( ... )'."),
};

pub const invalidConstantPatternNegation: MessageCode = MessageCode {
    name: "InvalidConstantPatternNegation",
    problem_message: "Only negation of a numeric literal is supported as a constant pattern.",
    correction_message: Some("Try wrapping the expression in 'const ( ... )'."),
};

pub const invalidConstantPatternUnary: Template<fn(&str) -> Message> = Template {
    name: "InvalidConstantPatternUnary",
    with_arguments: _withArgumentsInvalidConstantPatternUnary,
};

fn _withArgumentsInvalidConstantPatternUnary(operator_name: &str) -> Message {
    let operatorName_0 = conversions::validate_and_demangle_name(operator_name);
    Message {
        code: Code {
            name: invalidConstantPatternUnary.name,
        },
        problem_message: Cow::Owned(format!(
            "The unary operator {operatorName_0} is not supported as a constant pattern."
        )),
        correction_message: Some(Cow::Borrowed(
            "Try wrapping the expression in 'const ( ... )'.",
        )),
    }
}

pub const invalidCovariantModifierInPrimaryConstructor: MessageCode = MessageCode {
    name: "InvalidCovariantModifierInPrimaryConstructor",
    problem_message: "The 'covariant' modifier can only be used on non-final declaring parameters.",
    correction_message: Some("Try removing 'covariant'."),
};

pub const invalidEscapeStarted: MessageCode = MessageCode {
    name: "InvalidEscapeStarted",
    problem_message: "The string '\\' can't stand alone.",
    correction_message: Some("Try adding another backslash (\\) to escape the '\\'."),
};

pub const invalidHexEscape: MessageCode = MessageCode {
    name: "InvalidHexEscape",
    problem_message: "An escape sequence starting with '\\x' must be followed by 2 hexadecimal digits.",
    correction_message: None,
};

pub const invalidInitializer: MessageCode = MessageCode {
    name: "InvalidInitializer",
    problem_message: "Not a valid initializer.",
    correction_message: Some("To initialize a field, use the syntax 'name = value'."),
};

pub const invalidInlineFunctionType: MessageCode = MessageCode {
    name: "InvalidInlineFunctionType",
    problem_message: "Inline function types cannot be used for parameters in a generic function type.",
    correction_message: Some(
        "Try changing the inline function type (as in 'int f()') to a prefixed function type using the `Function` keyword (as in 'int Function() f').",
    ),
};

pub const invalidInsideUnaryPattern: MessageCode = MessageCode {
    name: "InvalidInsideUnaryPattern",
    problem_message: "This pattern cannot appear inside a unary pattern (cast pattern, null check pattern, or null assert pattern) without parentheses.",
    correction_message: Some(
        "Try combining into a single pattern if possible, or enclose the inner pattern in parentheses.",
    ),
};

pub const invalidOperator: Template<fn(&TokenStore, TokenId) -> Message> = Template {
    name: "InvalidOperator",
    with_arguments: _withArgumentsInvalidOperator,
};

fn _withArgumentsInvalidOperator(tokens: &TokenStore, lexeme: TokenId) -> Message {
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: invalidOperator.name,
        },
        problem_message: Cow::Owned(format!(
            "The string '{lexeme_0}' isn't a user-definable operator."
        )),
        correction_message: None,
    }
}

pub const invalidSuperInInitializer: MessageCode = MessageCode {
    name: "InvalidSuperInInitializer",
    problem_message: "Can only use 'super' in an initializer for calling the superclass constructor (e.g. 'super()' or 'super.namedConstructor()')",
    correction_message: None,
};

pub const invalidSyncModifier: MessageCode = MessageCode {
    name: "InvalidSyncModifier",
    problem_message: "Invalid modifier 'sync'.",
    correction_message: Some("Try replacing 'sync' with 'sync*'."),
};

pub const invalidThisInInitializer: MessageCode = MessageCode {
    name: "InvalidThisInInitializer",
    problem_message: "Can only use 'this' in an initializer for field initialization (e.g. 'this.x = something') and constructor redirection (e.g. 'this()' or 'this.namedConstructor())",
    correction_message: None,
};

pub const invalidUnicodeEscapeUBracket: MessageCode = MessageCode {
    name: "InvalidUnicodeEscapeUBracket",
    problem_message: "An escape sequence starting with '\\u{' must be followed by 1 to 6 hexadecimal digits followed by a '}'.",
    correction_message: None,
};

pub const invalidUnicodeEscapeUNoBracket: MessageCode = MessageCode {
    name: "InvalidUnicodeEscapeUNoBracket",
    problem_message: "An escape sequence starting with '\\u' must be followed by 4 hexadecimal digits.",
    correction_message: None,
};

pub const invalidUnicodeEscapeUStarted: MessageCode = MessageCode {
    name: "InvalidUnicodeEscapeUStarted",
    problem_message: "An escape sequence starting with '\\u' must be followed by 4 hexadecimal digits or from 1 to 6 digits between '{' and '}'.",
    correction_message: None,
};

pub const invalidVoid: MessageCode = MessageCode {
    name: "InvalidVoid",
    problem_message: "Type 'void' can't be used here.",
    correction_message: Some(
        "Try removing 'void' keyword or replace it with 'var', 'final', or a type.",
    ),
};

pub const latePatternVariableDeclaration: MessageCode = MessageCode {
    name: "LatePatternVariableDeclaration",
    problem_message: "A pattern variable declaration may not use the `late` keyword.",
    correction_message: Some("Try removing the keyword `late`."),
};

pub const libraryDirectiveNotFirst: MessageCode = MessageCode {
    name: "LibraryDirectiveNotFirst",
    problem_message: "The library directive must appear before all other directives.",
    correction_message: Some("Try moving the library directive before any other directives."),
};

pub const literalWithClass: Template<fn(&TokenStore, &str, TokenId) -> Message> = Template {
    name: "LiteralWithClass",
    with_arguments: _withArgumentsLiteralWithClass,
};

fn _withArgumentsLiteralWithClass(tokens: &TokenStore, kind: &str, lexeme: TokenId) -> Message {
    let kind_0 = conversions::validate_string(kind);
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: literalWithClass.name,
        },
        problem_message: Cow::Owned(format!(
            "A {kind_0} literal can't be prefixed by '{lexeme_0}'."
        )),
        correction_message: Some(Cow::Owned(format!("Try removing '{lexeme_0}'"))),
    }
}

pub const literalWithClassAndNew: Template<fn(&TokenStore, &str, TokenId) -> Message> = Template {
    name: "LiteralWithClassAndNew",
    with_arguments: _withArgumentsLiteralWithClassAndNew,
};

fn _withArgumentsLiteralWithClassAndNew(
    tokens: &TokenStore,
    kind: &str,
    lexeme: TokenId,
) -> Message {
    let kind_0 = conversions::validate_string(kind);
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: literalWithClassAndNew.name,
        },
        problem_message: Cow::Owned(format!(
            "A {kind_0} literal can't be prefixed by 'new {lexeme_0}'."
        )),
        correction_message: Some(Cow::Owned(format!("Try removing 'new' and '{lexeme_0}'"))),
    }
}

pub const literalWithNew: MessageCode = MessageCode {
    name: "LiteralWithNew",
    problem_message: "A literal can't be prefixed by 'new'.",
    correction_message: Some("Try removing 'new'"),
};

pub const memberWithSameNameAsClass: MessageCode = MessageCode {
    name: "MemberWithSameNameAsClass",
    problem_message: "A class member can't have the same name as the enclosing class.",
    correction_message: Some("Try renaming the member."),
};

pub const metadataSpaceBeforeParenthesis: MessageCode = MessageCode {
    name: "MetadataSpaceBeforeParenthesis",
    problem_message: "Annotations can't have spaces or comments before the parenthesis.",
    correction_message: Some("Remove any spaces or comments before the parenthesis."),
};

pub const metadataTypeArguments: MessageCode = MessageCode {
    name: "MetadataTypeArguments",
    problem_message: "An annotation can't use type arguments.",
    correction_message: None,
};

pub const metadataTypeArgumentsUninstantiated: MessageCode = MessageCode {
    name: "MetadataTypeArgumentsUninstantiated",
    problem_message: "An annotation with type arguments must be followed by an argument list.",
    correction_message: None,
};

pub const missingAssignableSelector: MessageCode = MessageCode {
    name: "MissingAssignableSelector",
    problem_message: "Missing selector such as '.identifier' or '[0]'.",
    correction_message: Some("Try adding a selector."),
};

pub const missingAssignmentInInitializer: MessageCode = MessageCode {
    name: "MissingAssignmentInInitializer",
    problem_message: "Expected an assignment after the field name.",
    correction_message: Some("To initialize a field, use the syntax 'name = value'."),
};

pub const missingConstFinalVarOrType: MessageCode = MessageCode {
    name: "MissingConstFinalVarOrType",
    problem_message: "Variables must be declared using the keywords 'const', 'final', 'var' or a type name.",
    correction_message: Some(
        "Try adding the name of the type of the variable or the keyword 'var'.",
    ),
};

pub const missingExponent: MessageCode = MessageCode {
    name: "MissingExponent",
    problem_message: "Numbers in exponential notation should always contain an exponent (an integer number with an optional sign).",
    correction_message: Some(
        "Make sure there is an exponent, and remove any whitespace before it.",
    ),
};

pub const missingExpressionInThrow: MessageCode = MessageCode {
    name: "MissingExpressionInThrow",
    problem_message: "Missing expression after 'throw'.",
    correction_message: Some(
        "Add an expression after 'throw' or use 'rethrow' to throw a caught exception",
    ),
};

pub const missingFunctionParameters: MessageCode = MessageCode {
    name: "MissingFunctionParameters",
    problem_message: "A function declaration needs an explicit list of parameters.",
    correction_message: Some("Try adding a parameter list to the function declaration."),
};

pub const missingMethodParameters: MessageCode = MessageCode {
    name: "MissingMethodParameters",
    problem_message: "A method declaration needs an explicit list of parameters.",
    correction_message: Some("Try adding a parameter list to the method declaration."),
};

pub const missingOperatorKeyword: MessageCode = MessageCode {
    name: "MissingOperatorKeyword",
    problem_message: "Operator declarations must be preceded by the keyword 'operator'.",
    correction_message: Some("Try adding the keyword 'operator'."),
};

pub const missingPrefixInDeferredImport: MessageCode = MessageCode {
    name: "MissingPrefixInDeferredImport",
    problem_message: "Deferred imports should have a prefix.",
    correction_message: Some("Try adding a prefix to the import by adding an 'as' clause."),
};

pub const missingPrimaryConstructor: MessageCode = MessageCode {
    name: "MissingPrimaryConstructor",
    problem_message: "An extension type declaration must have a primary constructor declaration.",
    correction_message: Some("Try adding a primary constructor to the extension type declaration."),
};

pub const missingPrimaryConstructorParameters: MessageCode = MessageCode {
    name: "MissingPrimaryConstructorParameters",
    problem_message: "A primary constructor declaration must have formal parameters.",
    correction_message: Some("Try adding formal parameters after the primary constructor name."),
};

pub const missingTypedefParameters: MessageCode = MessageCode {
    name: "MissingTypedefParameters",
    problem_message: "A typedef needs an explicit list of parameters.",
    correction_message: Some("Try adding a parameter list to the typedef."),
};

pub const mixinApplicationClassAugmentation: MessageCode = MessageCode {
    name: "MixinApplicationClassAugmentation",
    problem_message: "A mixin application class can't be augmented.",
    correction_message: None,
};

pub const mixinAugmentationHasOnClause: MessageCode = MessageCode {
    name: "MixinAugmentationHasOnClause",
    problem_message: "Mixin augmentations can't have 'on' clauses.",
    correction_message: Some("Try removing the 'on' clause."),
};

pub const mixinDeclaresConstructor: MessageCode = MessageCode {
    name: "MixinDeclaresConstructor",
    problem_message: "Mixins can't declare constructors.",
    correction_message: None,
};

pub const mixinPrimaryConstructor: MessageCode = MessageCode {
    name: "MixinPrimaryConstructor",
    problem_message: "Mixins can't have primary constructors.",
    correction_message: Some(
        "Try removing the primary constructor or changing the mixin to a class.",
    ),
};

pub const mixinWithClause: MessageCode = MessageCode {
    name: "MixinWithClause",
    problem_message: "A mixin can't have a with clause.",
    correction_message: None,
};

pub const modifierOutOfOrder: Template<fn(&str, &str) -> Message> = Template {
    name: "ModifierOutOfOrder",
    with_arguments: _withArgumentsModifierOutOfOrder,
};

fn _withArgumentsModifierOutOfOrder(modifier: &str, expected_later_modifier: &str) -> Message {
    let modifier_0 = conversions::validate_string(modifier);
    let expectedLaterModifier_0 = conversions::validate_string(expected_later_modifier);
    Message {
        code: Code {
            name: modifierOutOfOrder.name,
        },
        problem_message: Cow::Owned(format!(
            "The modifier '{modifier_0}' should be before the modifier '{expectedLaterModifier_0}'."
        )),
        correction_message: Some(Cow::Borrowed("Try re-ordering the modifiers.")),
    }
}

pub const multipleClauses: Template<fn(&str, &str) -> Message> = Template {
    name: "MultipleClauses",
    with_arguments: _withArgumentsMultipleClauses,
};

fn _withArgumentsMultipleClauses(definition_kind: &str, clause_kind: &str) -> Message {
    let definitionKind_0 = conversions::validate_string(definition_kind);
    let clauseKind_0 = conversions::validate_string(clause_kind);
    Message {
        code: Code {
            name: multipleClauses.name,
        },
        problem_message: Cow::Owned(format!(
            "Each '{definitionKind_0}' definition can have at most one '{clauseKind_0}' clause."
        )),
        correction_message: Some(Cow::Owned(format!(
            "Try combining all of the '{clauseKind_0}' clauses into a single clause."
        ))),
    }
}

pub const multipleCombinators: MessageCode = MessageCode {
    name: "MultipleCombinators",
    problem_message: "At most one 'show' or 'hide' combinator can be used on an import or export directive.",
    correction_message: Some("Try combining all of the combinators into a single combinator."),
};

pub const multipleExtends: MessageCode = MessageCode {
    name: "MultipleExtends",
    problem_message: "Each class definition can have at most one extends clause.",
    correction_message: Some(
        "Try choosing one superclass and define your class to implement (or mix in) the others.",
    ),
};

pub const multipleImplements: MessageCode = MessageCode {
    name: "MultipleImplements",
    problem_message: "Each class definition can have at most one implements clause.",
    correction_message: Some("Try combining all of the implements clauses into a single clause."),
};

pub const multipleLibraryDirectives: MessageCode = MessageCode {
    name: "MultipleLibraryDirectives",
    problem_message: "Only one library directive may be declared in a file.",
    correction_message: Some("Try removing all but one of the library directives."),
};

pub const multipleOnClauses: MessageCode = MessageCode {
    name: "MultipleOnClauses",
    problem_message: "Each mixin definition can have at most one on clause.",
    correction_message: Some("Try combining all of the on clauses into a single clause."),
};

pub const multiplePrimaryConstructorBodyDeclarations: MessageCode = MessageCode {
    name: "MultiplePrimaryConstructorBodyDeclarations",
    problem_message: "Only one primary constructor body declaration is allowed.",
    correction_message: Some(
        "Try removing all but one of the primary constructor body declarations.",
    ),
};

pub const multipleVarianceModifiers: MessageCode = MessageCode {
    name: "MultipleVarianceModifiers",
    problem_message: "Each type parameter can have at most one variance modifier.",
    correction_message: Some("Use at most one of the 'in', 'out', or 'inout' modifiers."),
};

pub const multipleWith: MessageCode = MessageCode {
    name: "MultipleWith",
    problem_message: "Each class definition can have at most one with clause.",
    correction_message: Some("Try combining all of the with clauses into a single clause."),
};

pub const namedFunctionExpression: MessageCode = MessageCode {
    name: "NamedFunctionExpression",
    problem_message: "A function expression can't have a name.",
    correction_message: None,
};

pub const nativeClauseShouldBeAnnotation: MessageCode = MessageCode {
    name: "NativeClauseShouldBeAnnotation",
    problem_message: "Native clause in this form is deprecated.",
    correction_message: Some(
        "Try removing this native clause and adding @native() or @native('native-name') before the declaration.",
    ),
};

pub const newConstructorDotName: MessageCode = MessageCode {
    name: "NewConstructorDotName",
    problem_message: "Constructors declared with the 'new' keyword can't use '.' before the constructor name.",
    correction_message: Some("Try replacing the '.' with a space."),
};

pub const newConstructorNewName: MessageCode = MessageCode {
    name: "NewConstructorNewName",
    problem_message: "Constructors declared with the 'new' keyword can't be named 'new'.",
    correction_message: Some("Try removing the second 'new' or changing it to a different name."),
};

pub const newConstructorQualifiedName: MessageCode = MessageCode {
    name: "NewConstructorQualifiedName",
    problem_message: "Constructors declared with the 'new' keyword can't have qualified names.",
    correction_message: Some(
        "Try removing the class name prefix from the qualified name or removing the 'new' keyword.",
    ),
};

pub const nonAsciiIdentifier: Template<fn(&str, i64) -> Message> = Template {
    name: "NonAsciiIdentifier",
    with_arguments: _withArgumentsNonAsciiIdentifier,
};

fn _withArgumentsNonAsciiIdentifier(character: &str, code_point: i64) -> Message {
    let character_0 = conversions::validate_character(character);
    let codePoint_0 = conversions::code_point_to_unicode(code_point);
    Message {
        code: Code {
            name: nonAsciiIdentifier.name,
        },
        problem_message: Cow::Owned(format!(
            "The non-ASCII character '{character_0}' ({codePoint_0}) can't be used in identifiers, only in strings and comments."
        )),
        correction_message: Some(Cow::Borrowed(
            "Try using an US-ASCII letter, a digit, '_' (an underscore), or '$' (a dollar sign).",
        )),
    }
}

pub const nonAsciiWhitespace: Template<fn(i64) -> Message> = Template {
    name: "NonAsciiWhitespace",
    with_arguments: _withArgumentsNonAsciiWhitespace,
};

fn _withArgumentsNonAsciiWhitespace(code_point: i64) -> Message {
    let codePoint_0 = conversions::code_point_to_unicode(code_point);
    Message {
        code: Code {
            name: nonAsciiWhitespace.name,
        },
        problem_message: Cow::Owned(format!(
            "The non-ASCII space character {codePoint_0} can only be used in strings and comments."
        )),
        correction_message: None,
    }
}

pub const nonPartOfDirectiveInPart: MessageCode = MessageCode {
    name: "NonPartOfDirectiveInPart",
    problem_message: "The part-of directive must be the only directive in a part.",
    correction_message: Some(
        "Try removing the other directives, or moving them to the library for which this is a part.",
    ),
};

pub const nonRedirectingGenerativeConstructorWithPrimary: MessageCode = MessageCode {
    name: "NonRedirectingGenerativeConstructorWithPrimary",
    problem_message: "Classes with primary constructors can't have non-redirecting generative constructors.",
    correction_message: Some(
        "Try making the constructor redirect to the primary constructor, or remove the primary constructor.",
    ),
};

pub const nullAwareCascadeOutOfOrder: MessageCode = MessageCode {
    name: "NullAwareCascadeOutOfOrder",
    problem_message: "The '?..' cascade operator must be first in the cascade sequence.",
    correction_message: Some(
        "Try moving the '?..' operator to be the first cascade operator in the sequence.",
    ),
};

pub const onlyTry: MessageCode = MessageCode {
    name: "OnlyTry",
    problem_message: "A try block must be followed by an 'on', 'catch', or 'finally' clause.",
    correction_message: Some(
        "Try adding either a catch or finally clause, or remove the try statement.",
    ),
};

pub const operatorWithTypeParameters: MessageCode = MessageCode {
    name: "OperatorWithTypeParameters",
    problem_message: "Types parameters aren't allowed when defining an operator.",
    correction_message: Some("Try removing the type parameters."),
};

pub const outOfOrderClauses: Template<fn(&str, &str) -> Message> = Template {
    name: "OutOfOrderClauses",
    with_arguments: _withArgumentsOutOfOrderClauses,
};

fn _withArgumentsOutOfOrderClauses(
    expected_earlier_clause: &str,
    expected_later_clause: &str,
) -> Message {
    let expectedEarlierClause_0 = conversions::validate_string(expected_earlier_clause);
    let expectedLaterClause_0 = conversions::validate_string(expected_later_clause);
    Message {
        code: Code {
            name: outOfOrderClauses.name,
        },
        problem_message: Cow::Owned(format!(
            "The '{expectedEarlierClause_0}' clause must come before the '{expectedLaterClause_0}' clause."
        )),
        correction_message: Some(Cow::Owned(format!(
            "Try moving the '{expectedEarlierClause_0}' clause before the '{expectedLaterClause_0}' clause."
        ))),
    }
}

pub const partOfTwice: MessageCode = MessageCode {
    name: "PartOfTwice",
    problem_message: "Only one part-of directive may be declared in a file.",
    correction_message: Some("Try removing all but one of the part-of directives."),
};

pub const patternAssignmentDeclaresVariable: Template<fn(&str) -> Message> = Template {
    name: "PatternAssignmentDeclaresVariable",
    with_arguments: _withArgumentsPatternAssignmentDeclaresVariable,
};

fn _withArgumentsPatternAssignmentDeclaresVariable(variable_name: &str) -> Message {
    let variableName_0 = conversions::validate_and_demangle_name(variable_name);
    Message {
        code: Code {
            name: patternAssignmentDeclaresVariable.name,
        },
        problem_message: Cow::Owned(format!(
            "Variable '{variableName_0}' can't be declared in a pattern assignment."
        )),
        correction_message: Some(Cow::Borrowed(
            "Try using a preexisting variable or changing the assignment to a pattern variable declaration.",
        )),
    }
}

pub const patternVariableDeclarationOutsideFunctionOrMethod: MessageCode = MessageCode {
    name: "PatternVariableDeclarationOutsideFunctionOrMethod",
    problem_message: "A pattern variable declaration may not appear outside a function or method.",
    correction_message: Some(
        "Try declaring ordinary variables and assigning from within a function or method.",
    ),
};

pub const positionalAfterNamedArgument: MessageCode = MessageCode {
    name: "PositionalAfterNamedArgument",
    problem_message: "Place positional arguments before named arguments.",
    correction_message: Some(
        "Try moving the positional argument before the named arguments, or add a name to the argument.",
    ),
};

pub const positionalParameterWithEquals: MessageCode = MessageCode {
    name: "PositionalParameterWithEquals",
    problem_message: "Positional optional parameters can't use ':' to specify a default value.",
    correction_message: Some("Try replacing ':' with '='."),
};

pub const prefixAfterCombinator: MessageCode = MessageCode {
    name: "PrefixAfterCombinator",
    problem_message: "The prefix ('as' clause) should come before any show/hide combinators.",
    correction_message: Some("Try moving the prefix before the combinators."),
};

pub const primaryConstructorBodyWithModifier: Template<fn(&str) -> Message> = Template {
    name: "PrimaryConstructorBodyWithModifier",
    with_arguments: _withArgumentsPrimaryConstructorBodyWithModifier,
};

fn _withArgumentsPrimaryConstructorBodyWithModifier(modifier: &str) -> Message {
    let modifier_0 = conversions::validate_string(modifier);
    Message {
        code: Code {
            name: primaryConstructorBodyWithModifier.name,
        },
        problem_message: Cow::Owned(format!(
            "A primary constructor body can't have the modifier '{modifier_0}'."
        )),
        correction_message: Some(Cow::Borrowed("Try removing the modifier.")),
    }
}

pub const primaryConstructorBodyWithoutDeclaration: MessageCode = MessageCode {
    name: "PrimaryConstructorBodyWithoutDeclaration",
    problem_message: "A primary constructor body requires a primary constructor declaration.",
    correction_message: Some("Try adding the primary constructor declaration."),
};

pub const privateNamedNonFieldParameter: MessageCode = MessageCode {
    name: "PrivateNamedNonFieldParameter",
    problem_message: "A named parameter that doesn't refer to an instance variable can't start with an underscore ('_').",
    correction_message: None,
};

pub const privateNamedParameter: MessageCode = MessageCode {
    name: "PrivateNamedParameter",
    problem_message: "A named parameter can't start with an underscore ('_').",
    correction_message: None,
};

pub const recordLiteralOnePositionalFieldNoTrailingComma: MessageCode = MessageCode {
    name: "RecordLiteralOnePositionalFieldNoTrailingComma",
    problem_message: "A record literal with exactly one positional field requires a trailing comma.",
    correction_message: Some("Try adding a trailing comma."),
};

pub const recordLiteralZeroFieldsWithTrailingComma: MessageCode = MessageCode {
    name: "RecordLiteralZeroFieldsWithTrailingComma",
    problem_message: "A record literal without fields can't have a trailing comma.",
    correction_message: Some("Try removing the trailing comma."),
};

pub const recordTypeOnePositionalFieldNoTrailingComma: MessageCode = MessageCode {
    name: "RecordTypeOnePositionalFieldNoTrailingComma",
    problem_message: "A record type with exactly one positional field requires a trailing comma.",
    correction_message: Some("Try adding a trailing comma."),
};

pub const recordTypeZeroFieldsButTrailingComma: MessageCode = MessageCode {
    name: "RecordTypeZeroFieldsButTrailingComma",
    problem_message: "A record type without fields can't have a trailing comma.",
    correction_message: Some("Try removing the trailing comma."),
};

pub const redirectGenerativeToNonGenerativeConstructor: MessageCode = MessageCode {
    name: "RedirectGenerativeToNonGenerativeConstructor",
    problem_message: "Generative constructors can't redirect to a factory constructor.",
    correction_message: Some("Try redirecting to a different constructor."),
};

pub const redirectingConstructorWithBody: MessageCode = MessageCode {
    name: "RedirectingConstructorWithBody",
    problem_message: "Redirecting constructors can't have a body.",
    correction_message: Some(
        "Try removing the body, or not making this a redirecting constructor.",
    ),
};

pub const redirectionInNonFactory: MessageCode = MessageCode {
    name: "RedirectionInNonFactory",
    problem_message: "Only factory constructor can specify '=' redirection.",
    correction_message: Some("Try making this a factory constructor, or remove the redirection."),
};

pub const requiredParameterWithDefault: MessageCode = MessageCode {
    name: "RequiredParameterWithDefault",
    problem_message: "Non-optional parameters can't have a default value.",
    correction_message: Some("Try removing the default value or making the parameter optional."),
};

pub const sealedEnum: MessageCode = MessageCode {
    name: "SealedEnum",
    problem_message: "Enums can't be declared to be 'sealed'.",
    correction_message: Some("Try removing the keyword 'sealed'."),
};

pub const sealedMixin: MessageCode = MessageCode {
    name: "SealedMixin",
    problem_message: "A mixin can't be declared 'sealed'.",
    correction_message: Some("Try removing the 'sealed' keyword."),
};

pub const sealedMixinClass: MessageCode = MessageCode {
    name: "SealedMixinClass",
    problem_message: "A mixin class can't be declared 'sealed'.",
    correction_message: Some("Try removing the 'sealed' keyword."),
};

pub const setOrMapLiteralTooManyTypeArguments: MessageCode = MessageCode {
    name: "SetOrMapLiteralTooManyTypeArguments",
    problem_message: "A set or map literal requires exactly one or two type arguments, respectively.",
    correction_message: None,
};

pub const setterConstructor: MessageCode = MessageCode {
    name: "SetterConstructor",
    problem_message: "Constructors can't be a setter.",
    correction_message: Some("Try removing 'set'."),
};

pub const setterNotSync: MessageCode = MessageCode {
    name: "SetterNotSync",
    problem_message: "Setters can't use 'async', 'async*', or 'sync*'.",
    correction_message: None,
};

pub const stackOverflow: MessageCode = MessageCode {
    name: "StackOverflow",
    problem_message: "The file has too many nested expressions or statements.",
    correction_message: Some("Try simplifying the code."),
};

pub const staticConstructor: MessageCode = MessageCode {
    name: "StaticConstructor",
    problem_message: "Constructors can't be static.",
    correction_message: Some("Try removing the keyword 'static'."),
};

pub const staticOperator: MessageCode = MessageCode {
    name: "StaticOperator",
    problem_message: "Operators can't be static.",
    correction_message: Some("Try removing the keyword 'static'."),
};

pub const superInitializingDeclaringParameter: MessageCode = MessageCode {
    name: "SuperInitializingDeclaringParameter",
    problem_message: "Declaring parameters can't be super parameters.",
    correction_message: Some(
        "Try removing the `super.` prefix or making the parameter non-declaring.",
    ),
};

pub const superNullAware: MessageCode = MessageCode {
    name: "SuperNullAware",
    problem_message: "The operator '?.' cannot be used with 'super' because 'super' cannot be null.",
    correction_message: Some("Try replacing '?.' with '.'"),
};

pub const switchHasCaseAfterDefault: MessageCode = MessageCode {
    name: "SwitchHasCaseAfterDefault",
    problem_message: "The default case should be the last case in a switch statement.",
    correction_message: Some("Try moving the default case after the other case clauses."),
};

pub const switchHasMultipleDefaults: MessageCode = MessageCode {
    name: "SwitchHasMultipleDefaults",
    problem_message: "The 'default' case can only be declared once.",
    correction_message: Some("Try removing all but one default case."),
};

pub const topLevelOperator: MessageCode = MessageCode {
    name: "TopLevelOperator",
    problem_message: "Operators must be declared within a class.",
    correction_message: Some(
        "Try removing the operator, moving it to a class, or converting it to be a function.",
    ),
};

pub const typeAfterVar: MessageCode = MessageCode {
    name: "TypeAfterVar",
    problem_message: "Variables can't be declared using both 'var' and a type name.",
    correction_message: Some("Try removing 'var.'"),
};

pub const typeArgumentsOnTypeVariable: Template<fn(&str) -> Message> = Template {
    name: "TypeArgumentsOnTypeVariable",
    with_arguments: _withArgumentsTypeArgumentsOnTypeVariable,
};

fn _withArgumentsTypeArgumentsOnTypeVariable(type_variable_name: &str) -> Message {
    let typeVariableName_0 = conversions::validate_and_demangle_name(type_variable_name);
    Message {
        code: Code {
            name: typeArgumentsOnTypeVariable.name,
        },
        problem_message: Cow::Owned(format!(
            "Can't use type arguments with type variable '{typeVariableName_0}'."
        )),
        correction_message: Some(Cow::Borrowed("Try removing the type arguments.")),
    }
}

pub const typeBeforeFactory: MessageCode = MessageCode {
    name: "TypeBeforeFactory",
    problem_message: "Factory constructors cannot have a return type.",
    correction_message: Some("Try removing the type appearing before 'factory'."),
};

pub const typedefAugmentation: MessageCode = MessageCode {
    name: "TypedefAugmentation",
    problem_message: "Type aliases can't be augmented.",
    correction_message: None,
};

pub const typedefInClass: MessageCode = MessageCode {
    name: "TypedefInClass",
    problem_message: "Typedefs can't be declared inside classes.",
    correction_message: Some("Try moving the typedef to the top-level."),
};

pub const unexpectedDollarInString: MessageCode = MessageCode {
    name: "UnexpectedDollarInString",
    problem_message: "A '$' has special meaning inside a string, and must be followed by an identifier or an expression in curly braces ({}).",
    correction_message: Some("Try adding a backslash (\\) to escape the '$'."),
};

pub const unexpectedSeparatorInNumber: MessageCode = MessageCode {
    name: "UnexpectedSeparatorInNumber",
    problem_message: "Digit separators ('_') in a number literal can only be placed between two digits.",
    correction_message: Some("Try removing the '_'."),
};

pub const unexpectedToken: Template<fn(&TokenStore, TokenId) -> Message> = Template {
    name: "UnexpectedToken",
    with_arguments: _withArgumentsUnexpectedToken,
};

fn _withArgumentsUnexpectedToken(tokens: &TokenStore, lexeme: TokenId) -> Message {
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: unexpectedToken.name,
        },
        problem_message: Cow::Owned(format!("Unexpected token '{lexeme_0}'.")),
        correction_message: None,
    }
}

pub const unexpectedTokens: MessageCode = MessageCode {
    name: "UnexpectedTokens",
    problem_message: "Unexpected tokens.",
    correction_message: None,
};

pub const unmatchedToken: Template<fn(&TokenStore, &str, TokenId) -> Message> = Template {
    name: "UnmatchedToken",
    with_arguments: _withArgumentsUnmatchedToken,
};

fn _withArgumentsUnmatchedToken(tokens: &TokenStore, expected: &str, lexeme: TokenId) -> Message {
    let expected_0 = conversions::validate_string(expected);
    let lexeme_0 = conversions::token_to_lexeme(tokens, lexeme);
    Message {
        code: Code {
            name: unmatchedToken.name,
        },
        problem_message: Cow::Owned(format!("Can't find '{expected_0}' to match '{lexeme_0}'.")),
        correction_message: None,
    }
}

pub const unspecified: Template<fn(&str) -> Message> = Template {
    name: "Unspecified",
    with_arguments: _withArgumentsUnspecified,
};

fn _withArgumentsUnspecified(message: &str) -> Message {
    let message_0 = conversions::validate_string(message);
    Message {
        code: Code {
            name: unspecified.name,
        },
        problem_message: Cow::Owned(message_0.to_string()),
        correction_message: None,
    }
}

pub const unsupportedOperator: Template<fn(&TokenStore, TokenId) -> Message> = Template {
    name: "UnsupportedOperator",
    with_arguments: _withArgumentsUnsupportedOperator,
};

fn _withArgumentsUnsupportedOperator(tokens: &TokenStore, operator: TokenId) -> Message {
    let operator_0 = conversions::token_to_lexeme(tokens, operator);
    Message {
        code: Code {
            name: unsupportedOperator.name,
        },
        problem_message: Cow::Owned(format!("The '{operator_0}' operator is not supported.")),
        correction_message: None,
    }
}

pub const unsupportedPrefixPlus: MessageCode = MessageCode {
    name: "UnsupportedPrefixPlus",
    problem_message: "'+' is not a prefix operator.",
    correction_message: Some("Try removing '+'."),
};

pub const unterminatedComment: MessageCode = MessageCode {
    name: "UnterminatedComment",
    problem_message: "Comment starting with '/*' must end with '*/'.",
    correction_message: None,
};

pub const unterminatedString: Template<fn(&str, &str) -> Message> = Template {
    name: "UnterminatedString",
    with_arguments: _withArgumentsUnterminatedString,
};

fn _withArgumentsUnterminatedString(open_quote: &str, expected_close_quote: &str) -> Message {
    let openQuote_0 = conversions::validate_string(open_quote);
    let expectedCloseQuote_0 = conversions::validate_string(expected_close_quote);
    Message {
        code: Code {
            name: unterminatedString.name,
        },
        problem_message: Cow::Owned(format!(
            "String starting with {openQuote_0} must end with {expectedCloseQuote_0}."
        )),
        correction_message: None,
    }
}

pub const varAsTypeName: MessageCode = MessageCode {
    name: "VarAsTypeName",
    problem_message: "The keyword 'var' can't be used as a type name.",
    correction_message: None,
};

pub const varReturnType: MessageCode = MessageCode {
    name: "VarReturnType",
    problem_message: "The return type can't be 'var'.",
    correction_message: Some(
        "Try removing the keyword 'var', or replacing it with the name of the return type.",
    ),
};

pub const variablePatternKeywordInDeclarationContext: MessageCode = MessageCode {
    name: "VariablePatternKeywordInDeclarationContext",
    problem_message: "Variable patterns in declaration context can't specify 'var' or 'final' keyword.",
    correction_message: Some("Try removing the keyword."),
};

pub const voidWithTypeArguments: MessageCode = MessageCode {
    name: "VoidWithTypeArguments",
    problem_message: "Type 'void' can't have type arguments.",
    correction_message: Some("Try removing the type arguments."),
};

pub const withBeforeExtends: MessageCode = MessageCode {
    name: "WithBeforeExtends",
    problem_message: "The extends clause must be before the with clause.",
    correction_message: Some("Try moving the extends clause before the with clause."),
};

pub const yieldAsIdentifier: MessageCode = MessageCode {
    name: "YieldAsIdentifier",
    problem_message: "'yield' can't be used as an identifier in 'async', 'async*', or 'sync*' methods.",
    correction_message: None,
};

pub const yieldNotGenerator: MessageCode = MessageCode {
    name: "YieldNotGenerator",
    problem_message: "'yield' can only be used in 'sync*' or 'async*' methods.",
    correction_message: None,
};
