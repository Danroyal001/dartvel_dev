// Port of lib/src/dart/element/element.dart: the element and fragment
// classes that building a library from its declarations creates.
//
// Upstream's element model is a graph of objects: a fragment per
// declaration in code, and an element per declared thing, whose fragments
// are chained (`previousFragment`, `nextFragment`) when augmentations add to
// it. Here fragments and elements live in an `ElementStore` addressed by
// 32-bit ids, as nodes live in an `AstStore`; `NO_FRAGMENT` and `NO_ELEMENT`
// are null. A fragment class is a `FragmentKind` and an element class an
// `ElementKind` (`ElementKind.name` is `ElementKind::name`); the members of
// the classes are the fields of `FragmentImpl` and `ElementImpl` that apply
// to the kind. Library elements and library fragments, which carry more,
// are `LibraryElementImpl` and `LibraryFragmentImpl`, addressed by index.
//
// The storage flags of fragments (upstream's generated `_FragmentStorageFlag`
// bits) are the bits of `FragmentImpl::flags`, named as `flagsForTesting`
// names them.
//
// Types, metadata, documentation, code ranges and the members that read
// resolution are not ported yet: they come with resolving the declared types.

#![allow(non_camel_case_types)]

use std::rc::Rc;

use crate::src::generated::utilities_dart::ParameterKind;

pub type FragmentId = u32;
pub type ElementId = u32;
pub type LibraryId = u32;
pub type UnitId = u32;

pub const NO_FRAGMENT: FragmentId = u32::MAX;
pub const NO_ELEMENT: ElementId = u32::MAX;
pub const NO_LIBRARY: LibraryId = u32::MAX;

/// The class of a fragment.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum FragmentKind {
    /// `LibraryFragmentImpl` (its data is a `LibraryFragmentImpl` of the
    /// store's `units`).
    Library,
    Class,
    Enum,
    Extension,
    ExtensionType,
    Mixin,
    TypeAlias,
    TopLevelFunction,
    TopLevelVariable,
    Field,
    Getter,
    Setter,
    Method,
    Constructor,
    FormalParameter,
    FieldFormalParameter,
    SuperFormalParameter,
    TypeParameter,
    GenericFunctionType,
    Dynamic,
    Never,
}

impl FragmentKind {
    pub fn is_instance(self) -> bool {
        matches!(
            self,
            FragmentKind::Class
                | FragmentKind::Enum
                | FragmentKind::Extension
                | FragmentKind::ExtensionType
                | FragmentKind::Mixin
        )
    }

    pub fn is_interface(self) -> bool {
        matches!(
            self,
            FragmentKind::Class | FragmentKind::Enum | FragmentKind::ExtensionType | FragmentKind::Mixin
        )
    }

    pub fn is_formal_parameter(self) -> bool {
        matches!(
            self,
            FragmentKind::FormalParameter
                | FragmentKind::FieldFormalParameter
                | FragmentKind::SuperFormalParameter
        )
    }

    pub fn is_executable(self) -> bool {
        matches!(
            self,
            FragmentKind::TopLevelFunction
                | FragmentKind::Getter
                | FragmentKind::Setter
                | FragmentKind::Method
                | FragmentKind::Constructor
        )
    }
}

/// `ElementKind`, the values the element classes built here return.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ElementKind {
    CLASS,
    CONSTRUCTOR,
    DYNAMIC,
    ENUM,
    EXTENSION,
    EXTENSION_TYPE,
    FIELD,
    FUNCTION,
    GENERIC_FUNCTION_TYPE,
    GETTER,
    METHOD,
    MIXIN,
    NEVER,
    PARAMETER,
    SETTER,
    TOP_LEVEL_VARIABLE,
    TYPE_ALIAS,
    TYPE_PARAMETER,
}

impl ElementKind {
    /// `ElementKind.name`.
    pub fn name(self) -> &'static str {
        match self {
            ElementKind::CLASS => "CLASS",
            ElementKind::CONSTRUCTOR => "CONSTRUCTOR",
            ElementKind::DYNAMIC => "DYNAMIC",
            ElementKind::ENUM => "ENUM",
            ElementKind::EXTENSION => "EXTENSION",
            ElementKind::EXTENSION_TYPE => "EXTENSION_TYPE",
            ElementKind::FIELD => "FIELD",
            ElementKind::FUNCTION => "FUNCTION",
            ElementKind::GENERIC_FUNCTION_TYPE => "GENERIC_FUNCTION_TYPE",
            ElementKind::GETTER => "GETTER",
            ElementKind::METHOD => "METHOD",
            ElementKind::MIXIN => "MIXIN",
            ElementKind::NEVER => "NEVER",
            ElementKind::PARAMETER => "PARAMETER",
            ElementKind::SETTER => "SETTER",
            ElementKind::TOP_LEVEL_VARIABLE => "TOP_LEVEL_VARIABLE",
            ElementKind::TYPE_ALIAS => "TYPE_ALIAS",
            ElementKind::TYPE_PARAMETER => "TYPE_PARAMETER",
        }
    }
}

/// `_FragmentStorageFlag`: each bit with the name `flagsForTesting` gives it.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(u8)]
pub enum FragmentFlag {
    classFragment_hasExtendsClause,
    classFragment_isAbstract,
    classFragment_isBase,
    classFragment_isFinal,
    classFragment_isInterface,
    classFragment_isMixinApplication,
    classFragment_isMixinClass,
    classFragment_isSealed,
    constructorFragment_isConst,
    constructorFragment_isFactory,
    constructorFragment_isOriginDeclaration,
    constructorFragment_isOriginExtensionTypeRecovery,
    constructorFragment_isOriginImplicitDefault,
    constructorFragment_isOriginMixinApplication,
    constructorFragment_isPrimary,
    constructorFragment_isRedirecting,
    executableFragment_hasImplicitReturnType,
    executableFragment_invokesSuperSelf,
    executableFragment_isAbstract,
    executableFragment_isAsynchronous,
    executableFragment_isExternal,
    executableFragment_isGenerator,
    executableFragment_isStatic,
    fieldFormalParameterFragment_isDeclaring,
    fieldFragment_isEnumConstant,
    fieldFragment_isExplicitlyCovariant,
    fieldFragment_isOriginDeclaringFormalParameter,
    fieldFragment_isOriginEnumValues,
    fieldFragment_isOriginExtensionTypeRecoveryRepresentation,
    fieldFragment_isPromotable,
    formalParameterFragment_isExplicitlyCovariant,
    formalParameterFragment_isOriginDeclaration,
    formalParameterFragment_isOriginMixinApplicationClassConstructor,
    formalParameterFragment_isOriginOtherFragmentOfEnclosing,
    fragment_isAugmentation,
    fragment_isComplete,
    libraryFragment_isOriginNotExistingFile,
    methodFragment_isOriginDeclaration,
    methodFragment_isOriginInterface,
    mixinFragment_isBase,
    nonParameterVariableFragment_hasInitializer,
    propertyAccessorFragment_isOriginDeclaration,
    propertyAccessorFragment_isOriginInterface,
    propertyAccessorFragment_isOriginVariable,
    propertyInducingFragment_isOriginDeclaration,
    propertyInducingFragment_isOriginGetterSetter,
    topLevelFunctionFragment_isOriginDeclaration,
    topLevelFunctionFragment_isOriginLoadLibrary,
    typeParameterFragment_isOriginOtherFragmentOfEnclosing,
    variableFragment_hasImplicitType,
    variableFragment_isAbstract,
    variableFragment_isConst,
    variableFragment_isExternal,
    variableFragment_isFinal,
    variableFragment_isLate,
    variableFragment_isStatic,
}

/// Every flag, in declaration order.
pub const FRAGMENT_FLAGS: [FragmentFlag; 56] = {
    use FragmentFlag::*;
    [
        classFragment_hasExtendsClause,
        classFragment_isAbstract,
        classFragment_isBase,
        classFragment_isFinal,
        classFragment_isInterface,
        classFragment_isMixinApplication,
        classFragment_isMixinClass,
        classFragment_isSealed,
        constructorFragment_isConst,
        constructorFragment_isFactory,
        constructorFragment_isOriginDeclaration,
        constructorFragment_isOriginExtensionTypeRecovery,
        constructorFragment_isOriginImplicitDefault,
        constructorFragment_isOriginMixinApplication,
        constructorFragment_isPrimary,
        constructorFragment_isRedirecting,
        executableFragment_hasImplicitReturnType,
        executableFragment_invokesSuperSelf,
        executableFragment_isAbstract,
        executableFragment_isAsynchronous,
        executableFragment_isExternal,
        executableFragment_isGenerator,
        executableFragment_isStatic,
        fieldFormalParameterFragment_isDeclaring,
        fieldFragment_isEnumConstant,
        fieldFragment_isExplicitlyCovariant,
        fieldFragment_isOriginDeclaringFormalParameter,
        fieldFragment_isOriginEnumValues,
        fieldFragment_isOriginExtensionTypeRecoveryRepresentation,
        fieldFragment_isPromotable,
        formalParameterFragment_isExplicitlyCovariant,
        formalParameterFragment_isOriginDeclaration,
        formalParameterFragment_isOriginMixinApplicationClassConstructor,
        formalParameterFragment_isOriginOtherFragmentOfEnclosing,
        fragment_isAugmentation,
        fragment_isComplete,
        libraryFragment_isOriginNotExistingFile,
        methodFragment_isOriginDeclaration,
        methodFragment_isOriginInterface,
        mixinFragment_isBase,
        nonParameterVariableFragment_hasInitializer,
        propertyAccessorFragment_isOriginDeclaration,
        propertyAccessorFragment_isOriginInterface,
        propertyAccessorFragment_isOriginVariable,
        propertyInducingFragment_isOriginDeclaration,
        propertyInducingFragment_isOriginGetterSetter,
        topLevelFunctionFragment_isOriginDeclaration,
        topLevelFunctionFragment_isOriginLoadLibrary,
        typeParameterFragment_isOriginOtherFragmentOfEnclosing,
        variableFragment_hasImplicitType,
        variableFragment_isAbstract,
        variableFragment_isConst,
        variableFragment_isExternal,
        variableFragment_isFinal,
        variableFragment_isLate,
        variableFragment_isStatic,
    ]
};

impl FragmentFlag {
    /// The key of this flag in `flagsForTesting`: its name without the
    /// class prefix.
    pub fn testing_name(self) -> &'static str {
        let name = self.full_name();
        &name[name.find('_').unwrap() + 1..]
    }

    fn full_name(self) -> &'static str {
        use FragmentFlag::*;
        match self {
            classFragment_hasExtendsClause => "classFragment_hasExtendsClause",
            classFragment_isAbstract => "classFragment_isAbstract",
            classFragment_isBase => "classFragment_isBase",
            classFragment_isFinal => "classFragment_isFinal",
            classFragment_isInterface => "classFragment_isInterface",
            classFragment_isMixinApplication => "classFragment_isMixinApplication",
            classFragment_isMixinClass => "classFragment_isMixinClass",
            classFragment_isSealed => "classFragment_isSealed",
            constructorFragment_isConst => "constructorFragment_isConst",
            constructorFragment_isFactory => "constructorFragment_isFactory",
            constructorFragment_isOriginDeclaration => "constructorFragment_isOriginDeclaration",
            constructorFragment_isOriginExtensionTypeRecovery => {
                "constructorFragment_isOriginExtensionTypeRecovery"
            }
            constructorFragment_isOriginImplicitDefault => {
                "constructorFragment_isOriginImplicitDefault"
            }
            constructorFragment_isOriginMixinApplication => {
                "constructorFragment_isOriginMixinApplication"
            }
            constructorFragment_isPrimary => "constructorFragment_isPrimary",
            constructorFragment_isRedirecting => "constructorFragment_isRedirecting",
            executableFragment_hasImplicitReturnType => "executableFragment_hasImplicitReturnType",
            executableFragment_invokesSuperSelf => "executableFragment_invokesSuperSelf",
            executableFragment_isAbstract => "executableFragment_isAbstract",
            executableFragment_isAsynchronous => "executableFragment_isAsynchronous",
            executableFragment_isExternal => "executableFragment_isExternal",
            executableFragment_isGenerator => "executableFragment_isGenerator",
            executableFragment_isStatic => "executableFragment_isStatic",
            fieldFormalParameterFragment_isDeclaring => "fieldFormalParameterFragment_isDeclaring",
            fieldFragment_isEnumConstant => "fieldFragment_isEnumConstant",
            fieldFragment_isExplicitlyCovariant => "fieldFragment_isExplicitlyCovariant",
            fieldFragment_isOriginDeclaringFormalParameter => {
                "fieldFragment_isOriginDeclaringFormalParameter"
            }
            fieldFragment_isOriginEnumValues => "fieldFragment_isOriginEnumValues",
            fieldFragment_isOriginExtensionTypeRecoveryRepresentation => {
                "fieldFragment_isOriginExtensionTypeRecoveryRepresentation"
            }
            fieldFragment_isPromotable => "fieldFragment_isPromotable",
            formalParameterFragment_isExplicitlyCovariant => {
                "formalParameterFragment_isExplicitlyCovariant"
            }
            formalParameterFragment_isOriginDeclaration => {
                "formalParameterFragment_isOriginDeclaration"
            }
            formalParameterFragment_isOriginMixinApplicationClassConstructor => {
                "formalParameterFragment_isOriginMixinApplicationClassConstructor"
            }
            formalParameterFragment_isOriginOtherFragmentOfEnclosing => {
                "formalParameterFragment_isOriginOtherFragmentOfEnclosing"
            }
            fragment_isAugmentation => "fragment_isAugmentation",
            fragment_isComplete => "fragment_isComplete",
            libraryFragment_isOriginNotExistingFile => "libraryFragment_isOriginNotExistingFile",
            methodFragment_isOriginDeclaration => "methodFragment_isOriginDeclaration",
            methodFragment_isOriginInterface => "methodFragment_isOriginInterface",
            mixinFragment_isBase => "mixinFragment_isBase",
            nonParameterVariableFragment_hasInitializer => {
                "nonParameterVariableFragment_hasInitializer"
            }
            propertyAccessorFragment_isOriginDeclaration => {
                "propertyAccessorFragment_isOriginDeclaration"
            }
            propertyAccessorFragment_isOriginInterface => "propertyAccessorFragment_isOriginInterface",
            propertyAccessorFragment_isOriginVariable => "propertyAccessorFragment_isOriginVariable",
            propertyInducingFragment_isOriginDeclaration => {
                "propertyInducingFragment_isOriginDeclaration"
            }
            propertyInducingFragment_isOriginGetterSetter => {
                "propertyInducingFragment_isOriginGetterSetter"
            }
            topLevelFunctionFragment_isOriginDeclaration => {
                "topLevelFunctionFragment_isOriginDeclaration"
            }
            topLevelFunctionFragment_isOriginLoadLibrary => {
                "topLevelFunctionFragment_isOriginLoadLibrary"
            }
            typeParameterFragment_isOriginOtherFragmentOfEnclosing => {
                "typeParameterFragment_isOriginOtherFragmentOfEnclosing"
            }
            variableFragment_hasImplicitType => "variableFragment_hasImplicitType",
            variableFragment_isAbstract => "variableFragment_isAbstract",
            variableFragment_isConst => "variableFragment_isConst",
            variableFragment_isExternal => "variableFragment_isExternal",
            variableFragment_isFinal => "variableFragment_isFinal",
            variableFragment_isLate => "variableFragment_isLate",
            variableFragment_isStatic => "variableFragment_isStatic",
        }
    }
}

/// `FragmentImpl` and its subclasses (but `LibraryFragmentImpl`'s own
/// members, which are in `LibraryFragmentImpl`).
#[derive(Clone, Debug)]
pub struct FragmentImpl {
    pub kind: FragmentKind,
    pub name: Option<Rc<str>>,
    /// `firstTokenOffset`.
    pub first_token_offset: Option<u32>,
    /// `nameOffset`.
    pub name_offset: Option<u32>,
    /// The `_FragmentStorageFlag` bits.
    pub flags: u64,
    /// `enclosingFragment`; `NO_FRAGMENT` for a library fragment and for
    /// `dynamic` and `Never`.
    pub enclosing_fragment: FragmentId,
    /// The library fragment this fragment is in (`libraryFragment`), as an
    /// index of the store's `units`.
    pub unit: UnitId,
    pub element: ElementId,
    pub previous_fragment: FragmentId,
    pub next_fragment: FragmentId,
    /// `typeParameters` of a type-parameterized fragment.
    pub type_parameters: Vec<FragmentId>,
    /// `formalParameters` of an executable fragment.
    pub formal_parameters: Vec<FragmentId>,
    /// `parameterKind` of a formal parameter.
    pub parameter_kind: ParameterKind,
    /// `privateName` of a field formal parameter.
    pub private_name: Option<Rc<str>>,
    /// `typeName` of a constructor.
    pub type_name: Option<Rc<str>>,
    /// `constantInitializer2?.toSource()`: the default value of a formal
    /// parameter, as `FormalParameterElementImpl.defaultValueCode` gives it.
    pub default_value_code: Option<Rc<str>>,
    /// `inducedGetter` and `inducedSetter` of a property inducing fragment.
    pub induced_getter: FragmentId,
    pub induced_setter: FragmentId,
    /// The members of an instance fragment (`InstanceFragmentImpl`).
    pub members: Option<Box<InstanceFragmentMembers>>,
}

/// The member lists of `InstanceFragmentImpl` and `InterfaceFragmentImpl`.
#[derive(Clone, Debug, Default)]
pub struct InstanceFragmentMembers {
    pub fields: Vec<FragmentId>,
    pub getters: Vec<FragmentId>,
    pub setters: Vec<FragmentId>,
    pub methods: Vec<FragmentId>,
    pub constructors: Vec<FragmentId>,
}

impl FragmentImpl {
    pub fn new(kind: FragmentKind, name: Option<Rc<str>>) -> FragmentImpl {
        FragmentImpl {
            kind,
            name,
            first_token_offset: None,
            name_offset: None,
            flags: 0,
            enclosing_fragment: NO_FRAGMENT,
            unit: u32::MAX,
            element: NO_ELEMENT,
            previous_fragment: NO_FRAGMENT,
            next_fragment: NO_FRAGMENT,
            type_parameters: Vec::new(),
            formal_parameters: Vec::new(),
            parameter_kind: ParameterKind::REQUIRED,
            private_name: None,
            type_name: None,
            default_value_code: None,
            induced_getter: NO_FRAGMENT,
            induced_setter: NO_FRAGMENT,
            members: if kind.is_instance() {
                Some(Box::default())
            } else {
                None
            },
        }
    }

    pub fn has_flag(&self, flag: FragmentFlag) -> bool {
        self.flags & (1u64 << flag as u8) != 0
    }

    pub fn set_flag(&mut self, flag: FragmentFlag, value: bool) {
        if value {
            self.flags |= 1u64 << flag as u8;
        } else {
            self.flags &= !(1u64 << flag as u8);
        }
    }

    /// The flags that are set, with the names `flagsForTesting` gives them.
    pub fn set_flag_names(&self) -> Vec<&'static str> {
        FRAGMENT_FLAGS
            .iter()
            .filter(|f| self.has_flag(**f))
            .map(|f| f.testing_name())
            .collect()
    }

    pub fn members(&self) -> &InstanceFragmentMembers {
        self.members.as_deref().unwrap()
    }

    pub fn members_mut(&mut self) -> &mut InstanceFragmentMembers {
        self.members.as_deref_mut().unwrap()
    }

    pub fn is_augmentation(&self) -> bool {
        self.has_flag(FragmentFlag::fragment_isAugmentation)
    }

    /// `isStatic` of a field, getter, setter or method fragment.
    pub fn is_static(&self) -> bool {
        match self.kind {
            FragmentKind::Field | FragmentKind::TopLevelVariable => {
                self.has_flag(FragmentFlag::variableFragment_isStatic)
            }
            _ => self.has_flag(FragmentFlag::executableFragment_isStatic),
        }
    }

    /// `VariableFragmentImpl.isConst`, `isFinal`, `isLate`, ...
    pub fn is_const(&self) -> bool {
        self.has_flag(FragmentFlag::variableFragment_isConst)
    }
    pub fn is_final(&self) -> bool {
        self.has_flag(FragmentFlag::variableFragment_isFinal)
    }
    pub fn is_late(&self) -> bool {
        self.has_flag(FragmentFlag::variableFragment_isLate)
    }
    pub fn is_abstract_variable(&self) -> bool {
        self.has_flag(FragmentFlag::variableFragment_isAbstract)
    }
    pub fn is_external_variable(&self) -> bool {
        self.has_flag(FragmentFlag::variableFragment_isExternal)
    }
    pub fn has_initializer(&self) -> bool {
        self.has_flag(FragmentFlag::nonParameterVariableFragment_hasInitializer)
    }

    /// `PropertyInducingFragmentImpl.hasSetter`: whether this variable
    /// needs the setter.
    pub fn has_setter(&self) -> bool {
        if self.is_const() {
            return false;
        }
        if self.is_late() {
            return !self.is_final() || !self.has_initializer();
        }
        !self.is_final()
    }

    /// `ConstructorFragmentImpl.isGenerative`.
    pub fn is_generative(&self) -> bool {
        !self.has_flag(FragmentFlag::constructorFragment_isFactory)
    }

    /// `FormalParameterFragmentImpl.isPositional`.
    pub fn is_positional(&self) -> bool {
        matches!(self.parameter_kind, ParameterKind::REQUIRED | ParameterKind::POSITIONAL)
    }

    /// `MethodFragmentImpl.lookupName`.
    pub fn method_lookup_name(&self) -> Option<Rc<str>> {
        if self.name.as_deref() == Some("-") && self.formal_parameters.is_empty() {
            return Some(Rc::from("unary-"));
        }
        self.name.clone()
    }
}

/// `ElementImpl` and its subclasses (but `LibraryElementImpl`).
#[derive(Clone, Debug)]
pub struct ElementImpl {
    pub kind: ElementKind,
    pub name: Option<Rc<str>>,
    /// `firstFragment`.
    pub first_fragment: FragmentId,
    /// The library this element is declared in; `NO_LIBRARY` for `dynamic`
    /// and `Never`.
    pub library: LibraryId,
    /// `PropertyAccessorElementImpl.variable`.
    pub variable: ElementId,
    /// `PropertyInducingElementImpl.getter` and `setter`.
    pub getter: ElementId,
    pub setter: ElementId,
    /// `ExecutableElementImpl.isExtensionTypeMember`.
    pub is_extension_type_member: bool,
    /// `previousFragmentOfDifferentKind`.
    pub previous_fragment_of_different_kind: FragmentId,
    /// The members of an instance element.
    pub members: Option<Box<InstanceElementMembers>>,
}

/// The member lists of `InstanceElementImpl` and `InterfaceElementImpl`.
#[derive(Clone, Debug, Default)]
pub struct InstanceElementMembers {
    pub fields: Vec<ElementId>,
    pub getters: Vec<ElementId>,
    pub setters: Vec<ElementId>,
    pub methods: Vec<ElementId>,
    pub constructors: Vec<ElementId>,
}

impl ElementImpl {
    pub fn members(&self) -> &InstanceElementMembers {
        self.members.as_deref().unwrap()
    }

    pub fn members_mut(&mut self) -> &mut InstanceElementMembers {
        self.members.as_deref_mut().unwrap()
    }
}

/// A `DirectiveUri` of an import, export or part include: the runtime
/// class and what it carries.
#[derive(Clone, Debug)]
pub enum DirectiveUri {
    /// `DirectiveUriImpl`: no URI string.
    None,
    /// `DirectiveUriWithRelativeUriStringImpl`: a string that is not a URI.
    WithRelativeUriString { relative_uri_string: Rc<str> },
    /// `DirectiveUriWithRelativeUriImpl`: a URI no file has.
    WithRelativeUri { relative_uri_string: Rc<str>, relative_uri: Rc<str> },
    /// `DirectiveUriWithSourceImpl`: a file that is not what the directive
    /// needs (a part imported as a library, a library included as a part).
    WithSource { relative_uri_string: Rc<str>, source_uri: Rc<str> },
    /// `DirectiveUriWithLibraryImpl`.
    WithLibrary { relative_uri_string: Rc<str>, library: LibraryId },
    /// `DirectiveUriWithUnitImpl`.
    WithUnit { relative_uri_string: Rc<str>, unit: UnitId },
}

/// `ShowElementCombinatorImpl` and `HideElementCombinatorImpl`.
#[derive(Clone, Debug)]
pub struct NamespaceCombinator {
    pub is_show: bool,
    pub offset: i32,
    pub end: i32,
    pub names: Vec<Rc<str>>,
}

/// `PrefixFragmentImpl`.
#[derive(Clone, Debug)]
pub struct PrefixFragmentImpl {
    pub name: Option<Rc<str>>,
    pub name_offset: Option<u32>,
    pub offset: i32,
    pub is_deferred: bool,
}

/// `LibraryImportImpl`.
#[derive(Clone, Debug)]
pub struct LibraryImportImpl {
    pub is_synthetic: bool,
    pub combinators: Vec<NamespaceCombinator>,
    pub import_keyword_offset: i32,
    pub prefix: Option<PrefixFragmentImpl>,
    pub uri: DirectiveUri,
}

/// `LibraryExportImpl`.
#[derive(Clone, Debug)]
pub struct LibraryExportImpl {
    pub combinators: Vec<NamespaceCombinator>,
    pub export_keyword_offset: i32,
    pub uri: DirectiveUri,
}

/// `PartIncludeImpl`.
#[derive(Clone, Debug)]
pub struct PartIncludeImpl {
    pub part_keyword_offset: i32,
    pub uri: DirectiveUri,
}

/// `LibraryFragmentImpl`'s own members.
#[derive(Clone, Debug)]
pub struct LibraryFragmentImpl {
    pub library: LibraryId,
    /// `source.uri`.
    pub source_uri: Rc<str>,
    pub is_origin_not_existing_file: bool,
    pub library_imports: Vec<LibraryImportImpl>,
    pub library_exports: Vec<LibraryExportImpl>,
    pub parts: Vec<PartIncludeImpl>,
    pub classes: Vec<FragmentId>,
    pub enums: Vec<FragmentId>,
    pub extensions: Vec<FragmentId>,
    pub extension_types: Vec<FragmentId>,
    pub mixins: Vec<FragmentId>,
    pub type_aliases: Vec<FragmentId>,
    pub functions: Vec<FragmentId>,
    pub top_level_variables: Vec<FragmentId>,
    pub getters: Vec<FragmentId>,
    pub setters: Vec<FragmentId>,
}

impl LibraryFragmentImpl {
    pub fn new(library: LibraryId, source_uri: Rc<str>) -> LibraryFragmentImpl {
        LibraryFragmentImpl {
            library,
            source_uri,
            is_origin_not_existing_file: false,
            library_imports: Vec::new(),
            library_exports: Vec::new(),
            parts: Vec::new(),
            classes: Vec::new(),
            enums: Vec::new(),
            extensions: Vec::new(),
            extension_types: Vec::new(),
            mixins: Vec::new(),
            type_aliases: Vec::new(),
            functions: Vec::new(),
            top_level_variables: Vec::new(),
            getters: Vec::new(),
            setters: Vec::new(),
        }
    }
}

/// `LibraryElementImpl`.
#[derive(Clone, Debug)]
pub struct LibraryElementImpl {
    pub uri: Rc<str>,
    pub name: Rc<str>,
    pub name_offset: i32,
    pub name_length: i32,
    pub is_synthetic: bool,
    /// `internal.fragments`: the defining unit, then the parts in the order
    /// they are included.
    pub fragments: Vec<UnitId>,
    pub classes: Vec<ElementId>,
    pub enums: Vec<ElementId>,
    pub extensions: Vec<ElementId>,
    pub extension_types: Vec<ElementId>,
    pub mixins: Vec<ElementId>,
    pub type_aliases: Vec<ElementId>,
    pub top_level_functions: Vec<ElementId>,
    pub top_level_variables: Vec<ElementId>,
    pub getters: Vec<ElementId>,
    pub setters: Vec<ElementId>,
    /// `exportNamespace.definedNames2`, in the order the export scope holds
    /// them.
    pub export_namespace: Vec<(Rc<str>, ElementId)>,
}

impl LibraryElementImpl {
    pub fn new(uri: Rc<str>, name: Rc<str>, name_offset: i32, name_length: i32) -> LibraryElementImpl {
        LibraryElementImpl {
            uri,
            name,
            name_offset,
            name_length,
            is_synthetic: false,
            fragments: Vec::new(),
            classes: Vec::new(),
            enums: Vec::new(),
            extensions: Vec::new(),
            extension_types: Vec::new(),
            mixins: Vec::new(),
            type_aliases: Vec::new(),
            top_level_functions: Vec::new(),
            top_level_variables: Vec::new(),
            getters: Vec::new(),
            setters: Vec::new(),
            export_namespace: Vec::new(),
        }
    }

    /// `isDartCore`.
    pub fn is_dart_core(&self) -> bool {
        &*self.uri == "dart:core"
    }
}

/// The fragments, elements, library fragments and libraries of a linking
/// session.
#[derive(Debug)]
pub struct ElementStore {
    pub fragments: Vec<FragmentImpl>,
    pub elements: Vec<ElementImpl>,
    pub units: Vec<LibraryFragmentImpl>,
    pub libraries: Vec<LibraryElementImpl>,
}

/// `DynamicElementImpl.instance`.
pub const DYNAMIC_ELEMENT: ElementId = 0;

/// `NeverElementImpl.instance`.
pub const NEVER_ELEMENT: ElementId = 1;

impl ElementStore {
    /// A store holding `dynamic` and `Never`.
    pub fn new() -> ElementStore {
        let mut store = ElementStore {
            fragments: Vec::new(),
            elements: Vec::new(),
            units: Vec::new(),
            libraries: Vec::new(),
        };
        for (fragment_kind, kind, name) in [
            (FragmentKind::Dynamic, ElementKind::DYNAMIC, "dynamic"),
            (FragmentKind::Never, ElementKind::NEVER, "Never"),
        ] {
            let fragment = store.add_fragment(FragmentImpl::new(fragment_kind, Some(Rc::from(name))));
            store.add_element(kind, fragment, NO_LIBRARY);
        }
        store
    }

    pub fn add_fragment(&mut self, fragment: FragmentImpl) -> FragmentId {
        let id = self.fragments.len() as FragmentId;
        self.fragments.push(fragment);
        id
    }

    /// Creates the element of [kind] whose first fragment is [fragment],
    /// named as the fragment is.
    pub fn add_element(&mut self, kind: ElementKind, fragment: FragmentId, library: LibraryId) -> ElementId {
        let id = self.elements.len() as ElementId;
        let is_instance = self.fragments[fragment as usize].kind.is_instance();
        self.elements.push(ElementImpl {
            kind,
            name: self.fragments[fragment as usize].name.clone(),
            first_fragment: fragment,
            library,
            variable: NO_ELEMENT,
            getter: NO_ELEMENT,
            setter: NO_ELEMENT,
            is_extension_type_member: false,
            previous_fragment_of_different_kind: NO_FRAGMENT,
            members: if is_instance { Some(Box::default()) } else { None },
        });
        self.fragments[fragment as usize].element = id;
        id
    }

    pub fn fragment(&self, id: FragmentId) -> &FragmentImpl {
        &self.fragments[id as usize]
    }

    pub fn fragment_mut(&mut self, id: FragmentId) -> &mut FragmentImpl {
        &mut self.fragments[id as usize]
    }

    pub fn element(&self, id: ElementId) -> &ElementImpl {
        &self.elements[id as usize]
    }

    pub fn element_mut(&mut self, id: ElementId) -> &mut ElementImpl {
        &mut self.elements[id as usize]
    }

    /// `Element.fragments`: the first fragment and the ones that follow it.
    pub fn element_fragments(&self, id: ElementId) -> Vec<FragmentId> {
        let mut result = Vec::new();
        let mut current = self.element(id).first_fragment;
        while current != NO_FRAGMENT {
            result.push(current);
            current = self.fragment(current).next_fragment;
        }
        result
    }

    /// `lastFragment`.
    pub fn last_fragment(&self, id: ElementId) -> FragmentId {
        let mut current = self.element(id).first_fragment;
        loop {
            let next = self.fragment(current).next_fragment;
            if next == NO_FRAGMENT {
                return current;
            }
            current = next;
        }
    }

    /// `addFragment` of the fragment classes: chains [fragment] after
    /// [previous], as a fragment of the same element.
    pub fn add_fragment_to_chain(&mut self, previous: FragmentId, fragment: FragmentId) {
        let element = self.fragment(previous).element;
        let f = self.fragment_mut(fragment);
        f.element = element;
        f.previous_fragment = previous;
        self.fragment_mut(previous).next_fragment = fragment;
    }

    /// `Element.lookupName`.
    pub fn lookup_name(&self, id: ElementId) -> Option<Rc<str>> {
        let element = self.element(id);
        match element.kind {
            ElementKind::SETTER => element.name.as_ref().map(|n| Rc::from(format!("{n}="))),
            ElementKind::METHOD => self.fragment(element.first_fragment).method_lookup_name(),
            _ => element.name.clone(),
        }
    }

    /// `Element.typeParameters`: the elements of the first fragment's type
    /// parameters.
    pub fn type_parameters(&self, id: ElementId) -> Vec<ElementId> {
        let first = self.element(id).first_fragment;
        self.fragment(first)
            .type_parameters
            .iter()
            .map(|f| self.fragment(*f).element)
            .collect()
    }

    /// `ExecutableElement.formalParameters`.
    pub fn formal_parameters(&self, id: ElementId) -> Vec<ElementId> {
        let first = self.element(id).first_fragment;
        self.fragment(first)
            .formal_parameters
            .iter()
            .map(|f| self.fragment(*f).element)
            .collect()
    }

    /// `FormalParameterFragmentImpl.initElement`: the element of the chain
    /// starting at [first], whose class is the first field formal or super
    /// formal fragment's, if any.
    pub fn init_formal_parameter_element(&mut self, first: FragmentId, library: LibraryId) -> ElementId {
        let id = self.add_element(ElementKind::PARAMETER, first, library);
        let mut current = self.fragment(first).next_fragment;
        while current != NO_FRAGMENT {
            self.fragment_mut(current).element = id;
            current = self.fragment(current).next_fragment;
        }
        id
    }

    /// The class of a formal parameter element: `FieldFormalParameter`,
    /// `SuperFormalParameter` (as the first such fragment in its chain is)
    /// or `FormalParameter`.
    pub fn formal_parameter_element_class(&self, id: ElementId) -> FragmentKind {
        let mut current = self.element(id).first_fragment;
        while current != NO_FRAGMENT {
            match self.fragment(current).kind {
                FragmentKind::FieldFormalParameter => return FragmentKind::FieldFormalParameter,
                FragmentKind::SuperFormalParameter => return FragmentKind::SuperFormalParameter,
                _ => {}
            }
            current = self.fragment(current).next_fragment;
        }
        FragmentKind::FormalParameter
    }
}

impl Default for ElementStore {
    fn default() -> Self {
        ElementStore::new()
    }
}
