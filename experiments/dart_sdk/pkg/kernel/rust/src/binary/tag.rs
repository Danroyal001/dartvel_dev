// Port of lib/binary/tag.dart: the node tags of the kernel binary format.
#![allow(non_upper_case_globals)]

/// `class Tag`.
pub mod Tag {
    pub const Nothing: u32 = 0;
    pub const Something: u32 = 1;
    pub const Class: u32 = 2;
    pub const Extension: u32 = 115;
    pub const ExtensionTypeDeclaration: u32 = 85;
    pub const FunctionNode: u32 = 3;
    pub const Field: u32 = 4;
    pub const Constructor: u32 = 5;
    pub const Procedure: u32 = 6;
    pub const InvalidInitializer: u32 = 7;
    pub const FieldInitializer: u32 = 8;
    pub const SuperInitializer: u32 = 9;
    pub const RedirectingInitializer: u32 = 10;
    pub const LocalInitializer: u32 = 11;
    pub const AssertInitializer: u32 = 12;
    pub const CheckLibraryIsLoaded: u32 = 13;
    pub const LoadLibrary: u32 = 14;
    pub const EqualsNull: u32 = 15;
    pub const EqualsCall: u32 = 16;
    pub const StaticTearOff: u32 = 17;
    pub const ConstStaticInvocation: u32 = 18;
    pub const InvalidExpression: u32 = 19;
    pub const VariableGet: u32 = 20;
    pub const VariableSet: u32 = 21;
    pub const AbstractSuperPropertyGet: u32 = 22;
    pub const AbstractSuperPropertySet: u32 = 23;
    pub const SuperPropertyGet: u32 = 24;
    pub const SuperPropertySet: u32 = 25;
    pub const StaticGet: u32 = 26;
    pub const StaticSet: u32 = 27;
    pub const AbstractSuperMethodInvocation: u32 = 28;
    pub const SuperMethodInvocation: u32 = 29;
    pub const StaticInvocation: u32 = 30;
    pub const ConstructorInvocation: u32 = 31;
    pub const ConstConstructorInvocation: u32 = 32;
    pub const Not: u32 = 33;
    pub const LogicalExpression: u32 = 34;
    pub const ConditionalExpression: u32 = 35;
    pub const StringConcatenation: u32 = 36;
    pub const IsExpression: u32 = 37;
    pub const AsExpression: u32 = 38;
    pub const StringLiteral: u32 = 39;
    pub const DoubleLiteral: u32 = 40;
    pub const TrueLiteral: u32 = 41;
    pub const FalseLiteral: u32 = 42;
    pub const NullLiteral: u32 = 43;
    pub const SymbolLiteral: u32 = 44;
    pub const TypeLiteral: u32 = 45;
    pub const ThisExpression: u32 = 46;
    pub const Rethrow: u32 = 47;
    pub const Throw: u32 = 48;
    pub const ListLiteral: u32 = 49;
    pub const MapLiteral: u32 = 50;
    pub const AwaitExpression: u32 = 51;
    pub const FunctionExpression: u32 = 52;
    pub const Let: u32 = 53;
    pub const Instantiation: u32 = 54;
    pub const PositiveIntLiteral: u32 = 55;
    pub const NegativeIntLiteral: u32 = 56;
    pub const BigIntLiteral: u32 = 57;
    pub const ConstListLiteral: u32 = 58;
    pub const ConstMapLiteral: u32 = 59;
    pub const ConstructorTearOff: u32 = 60;
    pub const BlockExpression: u32 = 82;
    pub const TypedefTearOff: u32 = 83;
    pub const RedirectingFactoryTearOff: u32 = 84;
    pub const RecordIndexGet: u32 = 101;
    pub const RecordNameGet: u32 = 102;
    pub const RecordLiteral: u32 = 104;
    pub const ConstRecordLiteral: u32 = 105;
    pub const ConstantExpression: u32 = 106;
    pub const FileUriConstantExpression: u32 = 108;
    pub const SetLiteral: u32 = 109;
    pub const ConstSetLiteral: u32 = 110;
    pub const ListConcatenation: u32 = 111;
    pub const SetConcatenation: u32 = 112;
    pub const MapConcatenation: u32 = 113;
    pub const InstanceCreation: u32 = 114;
    pub const FileUriExpression: u32 = 116;
    pub const NullCheck: u32 = 117;
    pub const InstanceGet: u32 = 118;
    pub const InstanceSet: u32 = 119;
    pub const InstanceInvocation: u32 = 120;
    pub const InstanceGetterInvocation: u32 = 89;
    pub const InstanceTearOff: u32 = 121;
    pub const DynamicGet: u32 = 122;
    pub const DynamicSet: u32 = 123;
    pub const DynamicInvocation: u32 = 124;
    pub const FunctionInvocation: u32 = 125;
    pub const FunctionTearOff: u32 = 126;
    pub const LocalFunctionInvocation: u32 = 127;
    pub const RedirectingFactoryInvocation: u32 = 153;
    pub const ExpressionStatement: u32 = 61;
    pub const Block: u32 = 62;
    pub const EmptyStatement: u32 = 63;
    pub const AssertStatement: u32 = 64;
    pub const LabeledStatement: u32 = 65;
    pub const BreakStatement: u32 = 66;
    pub const WhileStatement: u32 = 67;
    pub const DoStatement: u32 = 68;
    pub const ForStatement: u32 = 69;
    pub const ForInStatement: u32 = 70;
    pub const SwitchStatement: u32 = 71;
    pub const ContinueSwitchStatement: u32 = 72;
    pub const IfStatement: u32 = 73;
    pub const ReturnStatement: u32 = 74;
    pub const TryCatch: u32 = 75;
    pub const TryFinally: u32 = 76;
    pub const YieldStatement: u32 = 77;
    pub const VariableStatement: u32 = 78;
    pub const FunctionDeclaration: u32 = 79;
    pub const AsyncForInStatement: u32 = 80;
    pub const AssertBlock: u32 = 81;
    pub const TypedefType: u32 = 87;
    pub const InvalidType: u32 = 90;
    pub const DynamicType: u32 = 91;
    pub const VoidType: u32 = 92;
    pub const InterfaceType: u32 = 93;
    pub const FunctionType: u32 = 94;
    pub const TypeParameterType: u32 = 95;
    pub const SimpleInterfaceType: u32 = 96;
    pub const SimpleFunctionType: u32 = 97;
    pub const NeverType: u32 = 98;
    pub const IntersectionType: u32 = 99;
    pub const RecordType: u32 = 100;
    pub const ExtensionType: u32 = 103;
    pub const FutureOrType: u32 = 107;
    pub const AndPattern: u32 = 128;
    pub const AssignedVariablePattern: u32 = 129;
    pub const CastPattern: u32 = 130;
    pub const ConstantPattern: u32 = 131;
    pub const InvalidPattern: u32 = 132;
    pub const ListPattern: u32 = 133;
    pub const MapPattern: u32 = 134;
    pub const NamedPattern: u32 = 135;
    pub const NullAssertPattern: u32 = 136;
    pub const NullCheckPattern: u32 = 137;
    pub const ObjectPattern: u32 = 138;
    pub const OrPattern: u32 = 139;
    pub const RecordPattern: u32 = 140;
    pub const RelationalPattern: u32 = 141;
    pub const RestPattern: u32 = 142;
    pub const VariablePattern: u32 = 143;
    pub const WildcardPattern: u32 = 144;
    pub const MapPatternEntry: u32 = 145;
    pub const MapPatternRestEntry: u32 = 146;
    pub const PatternSwitchStatement: u32 = 147;
    pub const SwitchExpression: u32 = 148;
    pub const IfCaseStatement: u32 = 149;
    pub const PatternAssignment: u32 = 150;
    pub const PatternVariableDeclaration: u32 = 151;
    pub const NullType: u32 = 152;
    pub const VariableDeclaration: u32 = 154;
    pub const LocalVariable: u32 = 155;
    pub const LateVariable: u32 = 156;
    pub const SyntheticVariable: u32 = 157;
    pub const CatchVariable: u32 = 158;
    pub const PositionalParameter: u32 = 159;
    pub const NamedParameter: u32 = 160;
    pub const ThisVariable: u32 = 161;
    pub const LocalFunctionVariable: u32 = 162;
    pub const ConstVariable: u32 = 163;
    pub const SpecializedTagHighBits: u32 = 0xE0;
    pub const SpecializedTagMask: u32 = 0xF8;
    pub const SpecializedPayloadMask: u32 = 0x7;
    pub const SpecializedVariableGet: u32 = 224;
    pub const SpecializedVariableSet: u32 = 232;
    pub const SpecializedIntLiteral: u32 = 240;
    pub const SpecializedIntLiteralBias: u32 = 3;
    pub const ComponentFile: u32 = 0x90ABCDEF;
    pub const BinaryFormatVersion: u32 = 141;
}

/// `abstract class ConstantTag`.
pub mod ConstantTag {
    pub const NullConstant: u32 = 0;
    pub const BoolConstant: u32 = 1;
    pub const IntConstant: u32 = 2;
    pub const DoubleConstant: u32 = 3;
    pub const StringConstant: u32 = 4;
    pub const SymbolConstant: u32 = 5;
    pub const MapConstant: u32 = 6;
    pub const ListConstant: u32 = 7;
    pub const SetConstant: u32 = 13;
    pub const InstanceConstant: u32 = 8;
    pub const InstantiationConstant: u32 = 9;
    pub const StaticTearOffConstant: u32 = 10;
    pub const TypeLiteralConstant: u32 = 11;
    pub const UnevaluatedConstant: u32 = 12;
    pub const TypedefTearOffConstant: u32 = 14;
    pub const ConstructorTearOffConstant: u32 = 15;
    pub const RedirectingFactoryTearOffConstant: u32 = 16;
    pub const RecordConstant: u32 = 17;
}

/// `sdkHashLength`: bytes, a Git "short hash".
pub const sdkHashLength: usize = 10;
/// `sdkHashNull`.
pub const sdkHashNull: &str = "0000000000";

/// `expectedSdkHash`. Upstream reads `-Dsdk_hash`; run from source (as the
/// oracle is) it is [sdkHashNull], which is what this returns unless
/// `DART_SDK_HASH` is set at build time.
pub fn expectedSdkHash() -> &'static str {
    match option_env!("DART_SDK_HASH") {
        Some(hash) => {
            assert!(
                hash.len() == sdkHashLength,
                "-Dsdk_hash=<hash> must be a 10 byte string!"
            );
            hash
        }
        None => sdkHashNull,
    }
}

/// `isValidSdkHash`.
pub fn isValidSdkHash(sdkHash: &[u8]) -> bool {
    sdkHash == sdkHashNull.as_bytes()
        || expectedSdkHash() == sdkHashNull
        || sdkHash == expectedSdkHash().as_bytes()
}

/// `fixedFieldsBeforeLibraries`; these should match what is written in
/// `BinaryPrinter.writeComponentIndex`.
pub const fixedFieldsBeforeLibraries: usize = 9;
/// `fixedFieldsAfterLibraries`.
pub const fixedFieldsAfterLibraries: usize = 2;

/// `numberOfFixedFields`.
pub fn numberOfFixedFields(numberOfLibraries: usize) -> usize {
    fixedFieldsBeforeLibraries + numberOfLibraries + 1 + fixedFieldsAfterLibraries
}
