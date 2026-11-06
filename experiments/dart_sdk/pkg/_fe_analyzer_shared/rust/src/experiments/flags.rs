// Port of lib/src/experiments/flags.dart.
//
// Upstream generates this file from tools/experimental_features.yaml. The
// enum's values are Rust enum variants with their Dart names, and the fields
// are methods.
#![allow(non_camel_case_types)]

pub const defaultLanguageVersion: Version = Version::new(3, 15);

/// Enum for experimental flags shared between the CFE and the analyzer.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum ExperimentalFlag {
    anonymousMethods,
    augmentations,
    classModifiers,
    constFunctions,
    constantUpdate2018,
    constructorTearoffs,
    controlFlowCollections,
    dataAssets,
    digitSeparators,
    dotShorthands,
    enhancedEnums,
    enhancedParts,
    extensionMethods,
    genericMetadata,
    getterSetterError,
    inferenceUpdate1,
    inferenceUpdate2,
    inferenceUpdate3,
    inferenceUpdate4,
    inferenceUsingBounds,
    inlineClass,
    macros,
    namedArgumentsAnywhere,
    nativeAssets,
    nonNullable,
    nonfunctionTypeAliases,
    nullAwareElements,
    patterns,
    primaryConstructors,
    privateNamedParameters,
    promotionChainIntersectionJoin,
    receiverTypeInference,
    recordUse,
    records,
    sealedClass,
    setLiterals,
    singleCombinators,
    soundFlowAnalysis,
    spreadCollections,
    staticExtensions,
    superParameters,
    testExperiment,
    thisPromotion,
    tripleShift,
    unnamedLibraries,
    unquotedImports,
    variance,
    wildcardVariables,
}

struct FlagData {
    name: &'static str,
    is_enabled_by_default: bool,
    is_expired: bool,
    experiment_enabled_version: Version,
    experiment_released_version: Version,
}

impl ExperimentalFlag {
    pub const values: [ExperimentalFlag; NUMBER_OF_FLAGS] = [
        ExperimentalFlag::anonymousMethods,
        ExperimentalFlag::augmentations,
        ExperimentalFlag::classModifiers,
        ExperimentalFlag::constFunctions,
        ExperimentalFlag::constantUpdate2018,
        ExperimentalFlag::constructorTearoffs,
        ExperimentalFlag::controlFlowCollections,
        ExperimentalFlag::dataAssets,
        ExperimentalFlag::digitSeparators,
        ExperimentalFlag::dotShorthands,
        ExperimentalFlag::enhancedEnums,
        ExperimentalFlag::enhancedParts,
        ExperimentalFlag::extensionMethods,
        ExperimentalFlag::genericMetadata,
        ExperimentalFlag::getterSetterError,
        ExperimentalFlag::inferenceUpdate1,
        ExperimentalFlag::inferenceUpdate2,
        ExperimentalFlag::inferenceUpdate3,
        ExperimentalFlag::inferenceUpdate4,
        ExperimentalFlag::inferenceUsingBounds,
        ExperimentalFlag::inlineClass,
        ExperimentalFlag::macros,
        ExperimentalFlag::namedArgumentsAnywhere,
        ExperimentalFlag::nativeAssets,
        ExperimentalFlag::nonNullable,
        ExperimentalFlag::nonfunctionTypeAliases,
        ExperimentalFlag::nullAwareElements,
        ExperimentalFlag::patterns,
        ExperimentalFlag::primaryConstructors,
        ExperimentalFlag::privateNamedParameters,
        ExperimentalFlag::promotionChainIntersectionJoin,
        ExperimentalFlag::receiverTypeInference,
        ExperimentalFlag::recordUse,
        ExperimentalFlag::records,
        ExperimentalFlag::sealedClass,
        ExperimentalFlag::setLiterals,
        ExperimentalFlag::singleCombinators,
        ExperimentalFlag::soundFlowAnalysis,
        ExperimentalFlag::spreadCollections,
        ExperimentalFlag::staticExtensions,
        ExperimentalFlag::superParameters,
        ExperimentalFlag::testExperiment,
        ExperimentalFlag::thisPromotion,
        ExperimentalFlag::tripleShift,
        ExperimentalFlag::unnamedLibraries,
        ExperimentalFlag::unquotedImports,
        ExperimentalFlag::variance,
        ExperimentalFlag::wildcardVariables,
    ];

    fn data(self) -> &'static FlagData {
        &FLAGS[self as usize]
    }

    pub fn name(self) -> &'static str {
        self.data().name
    }

    pub fn is_enabled_by_default(self) -> bool {
        self.data().is_enabled_by_default
    }

    pub fn is_expired(self) -> bool {
        self.data().is_expired
    }

    pub fn experiment_enabled_version(self) -> Version {
        self.data().experiment_enabled_version
    }

    pub fn experiment_released_version(self) -> Version {
        self.data().experiment_released_version
    }

    /// The Dart enum value's name.
    pub fn enum_name(self) -> &'static str {
        match self {
            ExperimentalFlag::anonymousMethods => "anonymousMethods",
            ExperimentalFlag::augmentations => "augmentations",
            ExperimentalFlag::classModifiers => "classModifiers",
            ExperimentalFlag::constFunctions => "constFunctions",
            ExperimentalFlag::constantUpdate2018 => "constantUpdate2018",
            ExperimentalFlag::constructorTearoffs => "constructorTearoffs",
            ExperimentalFlag::controlFlowCollections => "controlFlowCollections",
            ExperimentalFlag::dataAssets => "dataAssets",
            ExperimentalFlag::digitSeparators => "digitSeparators",
            ExperimentalFlag::dotShorthands => "dotShorthands",
            ExperimentalFlag::enhancedEnums => "enhancedEnums",
            ExperimentalFlag::enhancedParts => "enhancedParts",
            ExperimentalFlag::extensionMethods => "extensionMethods",
            ExperimentalFlag::genericMetadata => "genericMetadata",
            ExperimentalFlag::getterSetterError => "getterSetterError",
            ExperimentalFlag::inferenceUpdate1 => "inferenceUpdate1",
            ExperimentalFlag::inferenceUpdate2 => "inferenceUpdate2",
            ExperimentalFlag::inferenceUpdate3 => "inferenceUpdate3",
            ExperimentalFlag::inferenceUpdate4 => "inferenceUpdate4",
            ExperimentalFlag::inferenceUsingBounds => "inferenceUsingBounds",
            ExperimentalFlag::inlineClass => "inlineClass",
            ExperimentalFlag::macros => "macros",
            ExperimentalFlag::namedArgumentsAnywhere => "namedArgumentsAnywhere",
            ExperimentalFlag::nativeAssets => "nativeAssets",
            ExperimentalFlag::nonNullable => "nonNullable",
            ExperimentalFlag::nonfunctionTypeAliases => "nonfunctionTypeAliases",
            ExperimentalFlag::nullAwareElements => "nullAwareElements",
            ExperimentalFlag::patterns => "patterns",
            ExperimentalFlag::primaryConstructors => "primaryConstructors",
            ExperimentalFlag::privateNamedParameters => "privateNamedParameters",
            ExperimentalFlag::promotionChainIntersectionJoin => "promotionChainIntersectionJoin",
            ExperimentalFlag::receiverTypeInference => "receiverTypeInference",
            ExperimentalFlag::recordUse => "recordUse",
            ExperimentalFlag::records => "records",
            ExperimentalFlag::sealedClass => "sealedClass",
            ExperimentalFlag::setLiterals => "setLiterals",
            ExperimentalFlag::singleCombinators => "singleCombinators",
            ExperimentalFlag::soundFlowAnalysis => "soundFlowAnalysis",
            ExperimentalFlag::spreadCollections => "spreadCollections",
            ExperimentalFlag::staticExtensions => "staticExtensions",
            ExperimentalFlag::superParameters => "superParameters",
            ExperimentalFlag::testExperiment => "testExperiment",
            ExperimentalFlag::thisPromotion => "thisPromotion",
            ExperimentalFlag::tripleShift => "tripleShift",
            ExperimentalFlag::unnamedLibraries => "unnamedLibraries",
            ExperimentalFlag::unquotedImports => "unquotedImports",
            ExperimentalFlag::variance => "variance",
            ExperimentalFlag::wildcardVariables => "wildcardVariables",
        }
    }
}

/// `toString()` of the Dart enum value.
impl std::fmt::Display for ExperimentalFlag {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "ExperimentalFlag.{}", self.enum_name())
    }
}

const NUMBER_OF_FLAGS: usize = 48;

const FLAGS: [FlagData; NUMBER_OF_FLAGS] = [
    FlagData {
        name: "anonymous-methods",
        is_enabled_by_default: false,
        is_expired: false,
        experiment_enabled_version: defaultLanguageVersion,
        experiment_released_version: defaultLanguageVersion,
    },
    FlagData {
        name: "augmentations",
        is_enabled_by_default: false,
        is_expired: false,
        experiment_enabled_version: defaultLanguageVersion,
        experiment_released_version: Version::new(3, 6),
    },
    FlagData {
        name: "class-modifiers",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(3, 0),
        experiment_released_version: Version::new(3, 0),
    },
    FlagData {
        name: "const-functions",
        is_enabled_by_default: false,
        is_expired: false,
        experiment_enabled_version: defaultLanguageVersion,
        experiment_released_version: defaultLanguageVersion,
    },
    FlagData {
        name: "constant-update-2018",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(2, 0),
        experiment_released_version: Version::new(2, 0),
    },
    FlagData {
        name: "constructor-tearoffs",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(2, 15),
        experiment_released_version: Version::new(2, 15),
    },
    FlagData {
        name: "control-flow-collections",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(2, 0),
        experiment_released_version: Version::new(2, 0),
    },
    FlagData {
        name: "data-assets",
        is_enabled_by_default: false,
        is_expired: false,
        experiment_enabled_version: defaultLanguageVersion,
        experiment_released_version: defaultLanguageVersion,
    },
    FlagData {
        name: "digit-separators",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(3, 6),
        experiment_released_version: Version::new(3, 6),
    },
    FlagData {
        name: "dot-shorthands",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(3, 10),
        experiment_released_version: Version::new(3, 9),
    },
    FlagData {
        name: "enhanced-enums",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(2, 17),
        experiment_released_version: Version::new(2, 17),
    },
    FlagData {
        name: "enhanced-parts",
        is_enabled_by_default: false,
        is_expired: false,
        experiment_enabled_version: defaultLanguageVersion,
        experiment_released_version: Version::new(3, 6),
    },
    FlagData {
        name: "extension-methods",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(2, 6),
        experiment_released_version: Version::new(2, 6),
    },
    FlagData {
        name: "generic-metadata",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(2, 14),
        experiment_released_version: Version::new(2, 14),
    },
    FlagData {
        name: "getter-setter-error",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(3, 9),
        experiment_released_version: Version::new(3, 9),
    },
    FlagData {
        name: "inference-update-1",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(2, 18),
        experiment_released_version: Version::new(2, 18),
    },
    FlagData {
        name: "inference-update-2",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(3, 2),
        experiment_released_version: Version::new(3, 2),
    },
    FlagData {
        name: "inference-update-3",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(3, 4),
        experiment_released_version: Version::new(3, 4),
    },
    FlagData {
        name: "inference-update-4",
        is_enabled_by_default: false,
        is_expired: false,
        experiment_enabled_version: defaultLanguageVersion,
        experiment_released_version: defaultLanguageVersion,
    },
    FlagData {
        name: "inference-using-bounds",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(3, 7),
        experiment_released_version: Version::new(3, 7),
    },
    FlagData {
        name: "inline-class",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(3, 3),
        experiment_released_version: Version::new(3, 3),
    },
    FlagData {
        name: "macros",
        is_enabled_by_default: false,
        is_expired: false,
        experiment_enabled_version: defaultLanguageVersion,
        experiment_released_version: Version::new(3, 3),
    },
    FlagData {
        name: "named-arguments-anywhere",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(2, 17),
        experiment_released_version: Version::new(2, 17),
    },
    FlagData {
        name: "native-assets",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(3, 10),
        experiment_released_version: Version::new(3, 9),
    },
    FlagData {
        name: "non-nullable",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(2, 12),
        experiment_released_version: Version::new(2, 10),
    },
    FlagData {
        name: "nonfunction-type-aliases",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(2, 13),
        experiment_released_version: Version::new(2, 13),
    },
    FlagData {
        name: "null-aware-elements",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(3, 8),
        experiment_released_version: Version::new(3, 8),
    },
    FlagData {
        name: "patterns",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(3, 0),
        experiment_released_version: Version::new(3, 0),
    },
    FlagData {
        name: "primary-constructors",
        is_enabled_by_default: true,
        is_expired: false,
        experiment_enabled_version: Version::new(3, 13),
        experiment_released_version: Version::new(3, 12),
    },
    FlagData {
        name: "private-named-parameters",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(3, 12),
        experiment_released_version: Version::new(3, 12),
    },
    FlagData {
        name: "promotion-chain-intersection-join",
        is_enabled_by_default: true,
        is_expired: false,
        experiment_enabled_version: Version::new(3, 15),
        experiment_released_version: Version::new(3, 15),
    },
    FlagData {
        name: "receiver-type-inference",
        is_enabled_by_default: false,
        is_expired: false,
        experiment_enabled_version: defaultLanguageVersion,
        experiment_released_version: defaultLanguageVersion,
    },
    FlagData {
        name: "record-use",
        is_enabled_by_default: true,
        is_expired: false,
        experiment_enabled_version: Version::new(3, 13),
        experiment_released_version: Version::new(3, 13),
    },
    FlagData {
        name: "records",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(3, 0),
        experiment_released_version: Version::new(3, 0),
    },
    FlagData {
        name: "sealed-class",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(3, 0),
        experiment_released_version: Version::new(3, 0),
    },
    FlagData {
        name: "set-literals",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(2, 0),
        experiment_released_version: Version::new(2, 0),
    },
    FlagData {
        name: "single-combinators",
        is_enabled_by_default: false,
        is_expired: false,
        experiment_enabled_version: defaultLanguageVersion,
        experiment_released_version: defaultLanguageVersion,
    },
    FlagData {
        name: "sound-flow-analysis",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(3, 9),
        experiment_released_version: Version::new(3, 9),
    },
    FlagData {
        name: "spread-collections",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(2, 0),
        experiment_released_version: Version::new(2, 0),
    },
    FlagData {
        name: "static-extensions",
        is_enabled_by_default: false,
        is_expired: false,
        experiment_enabled_version: defaultLanguageVersion,
        experiment_released_version: defaultLanguageVersion,
    },
    FlagData {
        name: "super-parameters",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(2, 17),
        experiment_released_version: Version::new(2, 17),
    },
    FlagData {
        name: "test-experiment",
        is_enabled_by_default: false,
        is_expired: false,
        experiment_enabled_version: defaultLanguageVersion,
        experiment_released_version: defaultLanguageVersion,
    },
    FlagData {
        name: "this-promotion",
        is_enabled_by_default: true,
        is_expired: false,
        experiment_enabled_version: Version::new(3, 15),
        experiment_released_version: Version::new(3, 15),
    },
    FlagData {
        name: "triple-shift",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(2, 14),
        experiment_released_version: Version::new(2, 14),
    },
    FlagData {
        name: "unnamed-libraries",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(2, 19),
        experiment_released_version: Version::new(2, 19),
    },
    FlagData {
        name: "unquoted-imports",
        is_enabled_by_default: false,
        is_expired: false,
        experiment_enabled_version: defaultLanguageVersion,
        experiment_released_version: defaultLanguageVersion,
    },
    FlagData {
        name: "variance",
        is_enabled_by_default: false,
        is_expired: false,
        experiment_enabled_version: defaultLanguageVersion,
        experiment_released_version: defaultLanguageVersion,
    },
    FlagData {
        name: "wildcard-variables",
        is_enabled_by_default: true,
        is_expired: true,
        experiment_enabled_version: Version::new(3, 7),
        experiment_released_version: Version::new(3, 7),
    },
];

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Version {
    pub major: i32,
    pub minor: i32,
}

impl Version {
    pub const fn new(major: i32, minor: i32) -> Version {
        Version { major, minor }
    }

    pub fn to_text(&self) -> String {
        format!("{}.{}", self.major, self.minor)
    }
}

impl std::fmt::Display for Version {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.to_text())
    }
}
