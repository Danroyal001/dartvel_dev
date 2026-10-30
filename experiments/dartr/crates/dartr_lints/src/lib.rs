// Dart source: pkg/analyzer/lib/src/analysis_rule/analysis_rule.dart
// Dart source: pkg/analyzer/lib/src/analysis_rule/rule_context.dart
// Dart source: pkg/analyzer/lib/src/lint/linter_visitor.dart
// Dart source: pkg/analyzer/lib/src/dart/analysis/library_analyzer.dart (_computeLints)

use dartr_ast::{Ast, NodeId, NodeKind};
use dartr_ast_builder::ParsedUnit;
use dartr_diagnostics::{Diagnostic, DiagnosticCode};
use dartr_syntax::TokenId;
use indexmap::{IndexMap, IndexSet};

mod analysis_rule_timers;
pub mod constants;
mod ignore_info;
pub mod rules;
pub use analysis_rule_timers::{AnalysisRuleTimers, RuleTimer};
pub use ignore_info::IgnoreInfo;
mod registry;
mod rule_metadata;
mod subscriptions;
pub use dartr_parser::experimental_flags::ExperimentalFlag;
pub use registry::*;
pub use rule_metadata::ALL_RULES;
pub type LintDiagnostic = Diagnostic;

#[derive(Clone, Debug, Default)]
pub struct PubspecDeps {
    pub name: String,
    pub dependencies: Vec<String>,
    pub dev_dependencies: Vec<String>,
}

/// Package and pubspec metadata for a library's defining unit, computed
/// once per package in an analysis context instead of via process-wide
/// static caches.
#[derive(Clone, Debug, Default)]
pub struct LintPackageInfo {
    /// Nearest ancestor directory of the defining unit with a `pubspec.yaml`.
    pub package_root: Option<std::path::PathBuf>,
    /// Whether `.dart_tool/package_config.json` exists at or above `package_root`.
    pub is_pub_package: bool,
    /// `AvoidWebLibrariesInFlutter.hasFlutterDep` for `package_root/pubspec.yaml`.
    pub has_flutter_dep: bool,
    /// `RemoveDeprecationsInBreakingVersion` for `package_root/pubspec.yaml` (when `is_pub_package`).
    pub has_breaking_version: bool,
    /// `DependOnReferencedPackages` dependencies for `package_root/pubspec.yaml` (when `is_pub_package`).
    pub pubspec_deps: Option<std::sync::Arc<PubspecDeps>>,
}

impl LintPackageInfo {
    /// Computes package and pubspec metadata for the defining unit at [path].
    pub fn for_defining_path(path: &str) -> Self {
        let Some(parent) = std::path::Path::new(path).parent() else {
            return Self::default();
        };
        let package_root = parent
            .ancestors()
            .find(|root| {
                root.join("pubspec.yaml")
                    .to_str()
                    .is_some_and(dartr_project::fs::file_exists)
            })
            .map(std::path::Path::to_path_buf);
        Self::from_package_root(package_root)
    }

    pub fn from_package_root(package_root: Option<std::path::PathBuf>) -> Self {
        let Some(root) = package_root else {
            return Self::default();
        };
        let is_pub_package = root.ancestors().any(|dir| {
            dir.join(".dart_tool/package_config.json")
                .to_str()
                .is_some_and(dartr_project::fs::file_exists)
        });
        let pubspec_path = root.join("pubspec.yaml");
        let (has_flutter_dep, has_breaking_version, pubspec_deps) =
            parse_lint_pubspec(&pubspec_path, is_pub_package);
        Self {
            package_root: Some(root),
            is_pub_package,
            has_flutter_dep,
            has_breaking_version,
            pubspec_deps,
        }
    }
}

/// Per-analysis-pass cache for [`LintPackageInfo`] keyed by parent directory
/// and package root. Scoped to a single analysis run so overlays are always
/// respected without global locks or `has_overlays()` checks.
#[derive(Default)]
pub struct LintPackageCache {
    by_dir: std::collections::HashMap<std::path::PathBuf, std::sync::Arc<LintPackageInfo>>,
    by_root: std::collections::HashMap<Option<std::path::PathBuf>, std::sync::Arc<LintPackageInfo>>,
}

impl LintPackageCache {
    pub fn for_defining_path(&mut self, path: &str) -> std::sync::Arc<LintPackageInfo> {
        let Some(parent) = std::path::Path::new(path).parent() else {
            return std::sync::Arc::new(LintPackageInfo::default());
        };
        if let Some(cached) = self.by_dir.get(parent) {
            return cached.clone();
        }
        let mut package_root = None;
        for anc in parent.ancestors() {
            if let Some(cached) = self.by_dir.get(anc) {
                let info = cached.clone();
                self.by_dir.insert(parent.to_path_buf(), info.clone());
                return info;
            }
            if anc
                .join("pubspec.yaml")
                .to_str()
                .is_some_and(dartr_project::fs::file_exists)
            {
                package_root = Some(anc.to_path_buf());
                break;
            }
        }
        let info = self
            .by_root
            .entry(package_root.clone())
            .or_insert_with(|| {
                std::sync::Arc::new(LintPackageInfo::from_package_root(package_root))
            })
            .clone();
        self.by_dir.insert(parent.to_path_buf(), info.clone());
        info
    }
}

fn parse_lint_pubspec(
    pubspec_path: &std::path::Path,
    is_pub_package: bool,
) -> (bool, bool, Option<std::sync::Arc<PubspecDeps>>) {
    use dartr_project::yaml::{NodeKind as YamlNodeKind, Scalar, YamlNode};

    fn scalar_text(node: &YamlNode) -> Option<String> {
        match &node.kind {
            YamlNodeKind::Scalar(Scalar::Null) => None,
            YamlNodeKind::Scalar(s) => Some(s.to_dart_string()),
            _ => None,
        }
    }

    fn process_dependencies(node: &YamlNode) -> Option<Vec<String>> {
        let YamlNodeKind::Map(entries) = &node.kind else {
            return None;
        };
        Some(entries.iter().filter_map(|(k, _)| scalar_text(k)).collect())
    }

    let Some(content) = pubspec_path
        .to_str()
        .and_then(dartr_project::fs::read_string_strict)
    else {
        return (false, false, None);
    };
    let Ok(yaml) = dartr_project::yaml::load_yaml_node(&content) else {
        return (false, false, None);
    };
    let YamlNodeKind::Map(entries) = &yaml.kind else {
        return (false, false, None);
    };

    let has_flutter_dep = yaml.value_at("dependencies").is_some_and(|deps| {
        matches!(deps.kind, YamlNodeKind::Map(_)) && deps.value_at("flutter").is_some()
    }) && !yaml
        .value_at("flutter")
        .and_then(|n| n.value_at("plugin"))
        .and_then(|n| n.value_at("platforms"))
        .and_then(|n| n.value_at("web"))
        .is_some_and(|w| !w.is_null_scalar());

    if !is_pub_package {
        return (has_flutter_dep, false, None);
    }

    let mut name: Option<String> = None;
    let mut dependencies: Option<Vec<String>> = None;
    let mut dev_dependencies: Option<Vec<String>> = None;
    let mut version_text: Option<String> = None;
    for (k, v) in entries {
        let Some(key) = scalar_text(k) else {
            continue;
        };
        match key.as_str() {
            "name" => name = scalar_text(v),
            "dependencies" => dependencies = process_dependencies(v),
            "dev_dependencies" => dev_dependencies = process_dependencies(v),
            "version" => version_text = scalar_text(v),
            _ => {}
        }
    }

    let has_breaking_version = version_text.as_deref().is_some_and(is_breaking_version_str);

    let pubspec_deps = name.map(|name| {
        std::sync::Arc::new(PubspecDeps {
            name,
            dependencies: dependencies.unwrap_or_default(),
            dev_dependencies: dev_dependencies.unwrap_or_default(),
        })
    });

    (has_flutter_dep, has_breaking_version, pubspec_deps)
}

/// Dart `Version.parse` + `RemoveDeprecationsInBreakingVersion.isBreakingVersion`.
fn is_breaking_version_str(version: &str) -> bool {
    let numeric_end = version
        .find(|c: char| !c.is_ascii_digit() && c != '.')
        .unwrap_or(version.len());
    let suffix = &version[numeric_end..];
    let valid_identifiers = |text: &str| {
        !text.is_empty()
            && text.split('.').all(|identifier| {
                !identifier.is_empty()
                    && identifier
                        .chars()
                        .all(|c| c.is_ascii_alphanumeric() || c == '-')
            })
    };
    let has_build = if let Some(rest) = suffix.strip_prefix('-') {
        if let Some((pre, build)) = rest.split_once('+') {
            if !valid_identifiers(pre) || !valid_identifiers(build) || build.contains('+') {
                return false;
            }
            true
        } else {
            if !valid_identifiers(rest) {
                return false;
            }
            false
        }
    } else if let Some(build) = suffix.strip_prefix('+') {
        if !valid_identifiers(build) || build.contains('+') {
            return false;
        }
        true
    } else if suffix.is_empty() {
        false
    } else {
        return false;
    };
    if has_build {
        return false;
    }
    let parts: Vec<_> = version[..numeric_end].split('.').collect();
    if parts.len() != 3 || parts.iter().any(|part| part.is_empty()) {
        return false;
    }
    let (Ok(major), Ok(minor), Ok(patch)) = (
        parts[0].parse::<u64>(),
        parts[1].parse::<u64>(),
        parts[2].parse::<u64>(),
    ) else {
        return false;
    };
    (minor == 0 && patch == 0) || (major == 0 && patch == 0)
}

#[derive(Clone, Copy)]
pub struct RuleContextUnit<'a> {
    pub parsed: &'a ParsedUnit,
    pub source: &'a str,
    pub path: &'a str,
    pub source_uri: Option<&'a str>,
    pub package_info: Option<&'a LintPackageInfo>,
}
/// Semantic results of the visited unit. Its local arena must remain alive.
#[derive(Clone, Copy)]
pub struct ResolvedLintContext<'a> {
    pub ctx: dartr_element::Ctx<'a>,
    pub tables: &'a dartr_element::ResolutionTables,
    /// Resolver `LocalVariableInfo.potentiallyMutatedInScope` facts.
    pub potentially_mutated_in_scope: &'a IndexSet<dartr_element::ElementId>,
    /// Resolver `corresponding_parameter_type`: argument expression → Dart
    /// `correspondingParameter.type`.
    pub corresponding_parameter_type: &'a dartr_ast::NodeMap<dartr_element::TypeId>,
    /// Resolver `FunctionBodyImpl.bodyContext` of the function bodies.
    pub body_context: &'a dartr_ast::NodeMap<BodyContext>,
    /// Resolver `this_scope_lookup`: the getter and the setter that the
    /// name of `this.name` resolves to in the scope of the `ThisExpression`
    /// (the linter `resolveNameInScope`).
    pub this_scope_lookup: &'a dartr_ast::NodeMap<(
        Option<dartr_element::ElementId>,
        Option<dartr_element::ElementId>,
    )>,
    /// Dart `node.accept(ExitDetector())` of a node of the unit (the
    /// resolved exit detector of the analyzer).
    pub exits: Option<&'a dyn Fn(NodeId) -> bool>,
    pub library: dartr_element::EId<dartr_element::LibraryElement>,
    /// Dart `Element.metadata` of elements of any library, with the
    /// annotation values (`None`: no metadata access).
    pub metadata: Option<&'a dyn ElementMetadata>,
}

/// Dart `BodyInferenceContext` facts of a function body
/// (`FunctionBodyImpl.bodyContext`).
#[derive(Clone, Copy, Debug)]
pub struct BodyContext {
    /// Dart `imposedType`.
    pub imposed_type: Option<dartr_element::TypeId>,
    /// Dart `mayCompleteNormally`.
    pub may_complete_normally: bool,
}

/// An `Annotation` node of a resolved unit of the analyzed library or of
/// another library (an opaque reference for [`ElementMetadata`]).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct AnnotationRef {
    pub unit: u32,
    pub node: NodeId,
}

/// Dart `Element.metadata`: the annotations of an element, their elements
/// (`ElementAnnotation.element`) and values
/// (`ElementAnnotation.computeConstantValue()`).
pub trait ElementMetadata {
    /// Dart `element.metadata.annotations`.
    fn annotations(&self, element: dartr_element::ElementId) -> Vec<AnnotationRef>;
    /// Dart `ElementAnnotation.element`, as a base element.
    fn annotation_element(&self, annotation: AnnotationRef) -> Option<dartr_element::ElementId>;
    /// Dart `ElementAnnotation.computeConstantValue()`.
    fn annotation_value(&self, annotation: AnnotationRef)
    -> Option<dartr_constant::DartObjectImpl>;
    /// Dart `VariableElement.computeConstantValue()` (also the default value
    /// of a formal parameter).
    fn element_constant_value(
        &self,
        element: dartr_element::ElementId,
    ) -> Option<dartr_constant::DartObjectImpl>;
    /// Dart `Expression.computeConstantValue()?.value` of [node] in the unit
    /// with the index [unit] of the analyzed library.
    fn expression_constant_value(
        &self,
        unit: u32,
        node: NodeId,
    ) -> Option<dartr_constant::DartObjectImpl>;
    /// Dart `AstNodeExtension.hasConstantVerifierError` of [node] in the unit
    /// with the index [unit].
    fn has_constant_verifier_error(&self, unit: u32, node: NodeId) -> bool;
    /// Dart `hasConstantError(node)` (linter `ast.dart`) of [node] in the
    /// unit with the index [unit].
    fn expression_has_constant_error(&self, unit: u32, node: NodeId) -> bool;
    /// Dart `canBeConst` of [node] (an instance creation, a typed or record
    /// literal, a dot shorthand constructor invocation or a constructor
    /// declaration) in the unit with the index [unit].
    fn can_be_const(&self, unit: u32, node: NodeId) -> bool;
    /// Dart `FormalParameterElement.defaultValueCode`: the source of the
    /// constant initializer of [element].
    fn default_value_code(&self, _element: dartr_element::ElementId) -> Option<String> {
        None
    }
    /// Fast path for `Metadata.hasImmutable` when implemented by the driver.
    fn has_immutable(&self, _element: dartr_element::ElementId) -> Option<bool> {
        None
    }
    /// Fast path for `ElementAnnotationImpl._isTopGetter(libraryName:, name:)`.
    fn has_top_getter_annotation(
        &self,
        _element: dartr_element::ElementId,
        _library_name: &str,
        _name: &str,
    ) -> Option<bool> {
        None
    }
    /// Fast path for `ElementAnnotationImpl._isConstructor(libraryName:, className:)`.
    fn has_constructor_annotation(
        &self,
        _element: dartr_element::ElementId,
        _library_name: &str,
        _class_name: &str,
    ) -> Option<bool> {
        None
    }
}
/// A resolved AST and its original parse metadata. Resolution can rewrite nodes.
#[derive(Clone, Copy)]
pub struct ResolvedRuleContextUnit<'a> {
    pub parsed: &'a ParsedUnit,
    pub ast: &'a Ast,
    pub unit: NodeId,
    pub source: &'a str,
    pub path: &'a str,
    pub source_uri: Option<&'a str>,
    pub package_info: Option<&'a LintPackageInfo>,
    pub resolved: Option<ResolvedLintContext<'a>>,
}
#[derive(Clone, Copy)]
pub struct LinterContext<'a> {
    pub parsed: &'a ParsedUnit,
    pub ast: &'a Ast,
    pub source: &'a str,
    pub path: &'a str,
    pub all_units: &'a [RuleContextUnit<'a>],
    pub current_unit: usize,
    pub resolved: Option<ResolvedLintContext<'a>>,
    pub resolved_units: &'a [ResolvedRuleContextUnit<'a>],
    pub package_info: Option<&'a LintPackageInfo>,
    pub lazy_package_info: Option<&'a std::cell::OnceCell<LintPackageInfo>>,
}
pub type RuleContext<'a> = LinterContext<'a>;
impl<'a> LinterContext<'a> {
    /// The same library context, using the selected unit's AST and local arena.
    pub fn resolved_unit(&self, index: usize) -> Option<Self> {
        let unit = self.resolved_units.get(index)?;
        Some(Self {
            parsed: unit.parsed,
            ast: unit.ast,
            source: unit.source,
            path: unit.path,
            current_unit: index,
            resolved: unit.resolved,
            ..*self
        })
    }
    pub fn constant_value(
        &self,
        node: impl Into<NodeId>,
    ) -> Option<dartr_constant::DartObjectImpl> {
        constants::constant_value(self, node.into())
    }
    pub fn default_value(
        &self,
        parameter: dartr_element::ElemRef,
    ) -> Option<dartr_constant::DartObjectImpl> {
        constants::default_value(self, parameter)
    }
    pub fn constant_type_system(&self) -> Option<constants::ConstantTypeSystem<'a>> {
        Some(constants::ConstantTypeSystem(self.resolved?.ctx))
    }
    /// The texts of `DartType` diagnostic arguments: Dart `convertTypeNames`
    /// (`getDisplayString(preferTypeAlias: true)`, disambiguated when two
    /// types have the same display string).
    pub fn type_argument_texts(&self, types: &[dartr_element::TypeId]) -> Vec<String> {
        let Some(resolved) = self.resolved else {
            return Vec::new();
        };
        let arguments: Vec<dartr_diagnostics::DiagnosticArg> = types
            .iter()
            .map(|&ty| {
                dartr_diagnostics::DiagnosticArg::Type(dartr_element::diagnostics::type_arg(
                    &resolved.ctx,
                    ty,
                ))
            })
            .collect();
        dartr_diagnostics::convert_type_names(&arguments).0
    }
    /// The text of one `DartType` diagnostic argument.
    pub fn type_argument_text(&self, ty: dartr_element::TypeId) -> String {
        self.type_argument_texts(&[ty]).pop().unwrap_or_default()
    }
    /// Dart `writeOrReadElement` of an identifier (`_writeElement(node) ??
    /// element`, analyzer `ast/extensions.dart`).
    pub fn write_or_read_element(&self, node: impl Into<NodeId>) -> Option<dartr_element::ElemRef> {
        fn write_element(c: &LinterContext<'_>, node: NodeId) -> Option<dartr_element::ElemRef> {
            use dartr_ast::*;
            let parent = c.ast.parent(node)?;
            let tables = c.resolved?.tables;
            let is = |child: NodeId| child == node;
            match c.ast.kind(parent) {
                NodeKind::AssignmentExpression
                    if is(c.ast[Id::<AssignmentExpression>::from_raw(parent)]
                        .left_hand_side
                        .raw()) =>
                {
                    tables.write_element.get(parent).copied()
                }
                NodeKind::PostfixExpression
                    if is(c.ast[Id::<PostfixExpression>::from_raw(parent)]
                        .operand
                        .raw()) =>
                {
                    tables.write_element.get(parent).copied()
                }
                NodeKind::PrefixExpression
                    if is(c.ast[Id::<PrefixExpression>::from_raw(parent)]
                        .operand
                        .raw()) =>
                {
                    tables.write_element.get(parent).copied()
                }
                NodeKind::PrefixedIdentifier
                    if is(c.ast[Id::<PrefixedIdentifier>::from_raw(parent)]
                        .identifier
                        .raw()) =>
                {
                    write_element(c, parent)
                }
                NodeKind::PropertyAccess
                    if is(c.ast[Id::<PropertyAccess>::from_raw(parent)]
                        .property_name
                        .raw()) =>
                {
                    write_element(c, parent)
                }
                _ => None,
            }
        }
        let node = node.into();
        write_element(self, node).or_else(|| self.element(node))
    }
    /// Dart `canonicalElementsAreEqual` (linter `util/dart_type_utilities.dart`):
    /// `element1?.canonicalElement2 == element2?.canonicalElement2`.
    ///
    /// A member of a generic type (`ElemRef::Member`) is a fresh
    /// `Substituted*ElementImpl` for each reference, and its
    /// `canonicalElement2` is the member itself or, for a property accessor,
    /// a fresh `SubstitutedFieldElementImpl`
    /// (`SubstitutedPropertyAccessorElementImpl.variable`,
    /// `pkg/analyzer/lib/src/dart/element/member.dart`); none of them
    /// overrides `==`, so such a reference is equal to nothing. Two missing
    /// elements are equal (`null == null`).
    pub fn canonical_elements_are_equal(
        &self,
        element1: Option<dartr_element::ElemRef>,
        element2: Option<dartr_element::ElemRef>,
    ) -> bool {
        use dartr_element::ElemRef;
        match (element1, element2) {
            (None, None) => true,
            (Some(ElemRef::Member(_)), _) | (_, Some(ElemRef::Member(_))) => false,
            (Some(a), Some(b)) => self.canonical_element2(a) == self.canonical_element2(b),
            _ => false,
        }
    }
    /// Dart `ElementExtension.canonicalElement2` of the base element:
    /// a property accessor is replaced with its variable.
    pub fn canonical_element2(
        &self,
        element: dartr_element::ElemRef,
    ) -> Option<dartr_element::ElementId> {
        let resolved = self.resolved?;
        let base = dartr_typesystem::member::base_element(&resolved.ctx, element);
        Some(match base.tag() {
            dartr_element::Tag::Getter | dartr_element::Tag::Setter => resolved
                .ctx
                .property_accessor(dartr_element::EId::from_raw(base))
                .variable
                .get()
                .map(|v| v.raw())
                .unwrap_or(base),
            _ => base,
        })
    }
    /// Whether an annotation of [element] (its `ElementAnnotation.element`,
    /// a base element) satisfies [predicate].
    pub fn has_annotation_where(
        &self,
        element: dartr_element::ElementId,
        mut predicate: impl FnMut(&dartr_element::Ctx<'a>, dartr_element::ElementId) -> bool,
    ) -> bool {
        let Some(resolved) = self.resolved else {
            return false;
        };
        let Some(metadata) = resolved.metadata else {
            return false;
        };
        metadata.annotations(element).into_iter().any(|annotation| {
            metadata
                .annotation_element(annotation)
                .is_some_and(|a| predicate(&resolved.ctx, a))
        })
    }
    /// Dart `ElementAnnotationImpl._isConstructor(libraryName:, className:)`
    /// for an annotation of [element].
    pub fn has_constructor_annotation(
        &self,
        element: dartr_element::ElementId,
        library_name: &str,
        class_name: &str,
    ) -> bool {
        if let Some(resolved) = self.resolved
            && let Some(metadata) = resolved.metadata
            && let Some(found) =
                metadata.has_constructor_annotation(element, library_name, class_name)
        {
            return found;
        }
        use dartr_typesystem::TypeExt;
        self.has_annotation_where(element, |ctx, a| {
            a.tag() == dartr_element::Tag::Constructor
                && ctx
                    .element_data(a)
                    .and_then(|d| d.enclosing)
                    .and_then(|e| ctx.element_name(e))
                    == Some(class_name)
                && dartr_typesystem::member::library(ctx, dartr_element::ElemRef::Base(a))
                    .is_some_and(|library| ctx.element_name(library.raw()) == Some(library_name))
        })
    }
    /// Dart `Metadata.hasImmutable` (`isImmutable`: the `immutable` getter or
    /// the `Immutable` constructor of package:meta).
    pub fn has_immutable(&self, element: dartr_element::ElementId) -> bool {
        if let Some(resolved) = self.resolved
            && let Some(metadata) = resolved.metadata
            && let Some(found) = metadata.has_immutable(element)
        {
            return found;
        }
        self.has_package_meta_getter(element, "immutable")
            || self.has_constructor_annotation(element, "meta", "Immutable")
    }
    /// Dart `element.metadata.annotations.any((a) => a._isPackageMetaGetter(name))`
    /// (`hasAwaitNotRequired`, `hasOptionalTypeArgs`, ...).
    pub fn has_package_meta_getter(&self, element: dartr_element::ElementId, name: &str) -> bool {
        self.has_top_getter_annotation(element, "meta", name)
    }
    /// Dart `ElementAnnotationImpl._isTopGetter(libraryName:, name:)` for an
    /// annotation of [element]: the top-level getter [name] of the library
    /// named [library_name] (`hasOverride`: `dart.core`, `override`).
    pub fn has_top_getter_annotation(
        &self,
        element: dartr_element::ElementId,
        library_name: &str,
        name: &str,
    ) -> bool {
        use dartr_typesystem::TypeExt;
        let Some(resolved) = self.resolved else {
            return false;
        };
        let Some(metadata) = resolved.metadata else {
            return false;
        };
        if let Some(found) = metadata.has_top_getter_annotation(element, library_name, name) {
            return found;
        }
        let ctx = &resolved.ctx;
        metadata.annotations(element).into_iter().any(|annotation| {
            metadata.annotation_element(annotation).is_some_and(|a| {
                a.tag() == dartr_element::Tag::Getter
                    && ctx.element_name(a) == Some(name)
                    && dartr_typesystem::member::library(ctx, dartr_element::ElemRef::Base(a))
                        .is_some_and(|library| {
                            ctx.element_name(library.raw()) == Some(library_name)
                        })
            })
        })
    }
    /// Dart `FormalParameterElement.defaultValueCode`.
    pub fn default_value_code(&self, element: dartr_element::ElementId) -> Option<String> {
        self.resolved?.metadata?.default_value_code(element)
    }
    /// Dart `canBeConst` (`analyzer/src/lint/constants.dart`, `ast.dart`).
    pub fn can_be_const(&self, node: impl Into<NodeId>) -> bool {
        self.resolved
            .and_then(|r| r.metadata)
            .is_some_and(|m| m.can_be_const(self.current_unit as u32, node.into()))
    }
    /// Dart `hasConstantError(node)` of the linter `ast.dart`.
    pub fn has_constant_error(&self, node: impl Into<NodeId>) -> bool {
        self.resolved
            .and_then(|r| r.metadata)
            .is_none_or(|m| m.expression_has_constant_error(self.current_unit as u32, node.into()))
    }
    /// Dart `AstNodeExtension.hasConstantVerifierError`.
    pub fn has_constant_verifier_error(&self, node: impl Into<NodeId>) -> bool {
        self.resolved
            .and_then(|r| r.metadata)
            .is_some_and(|m| m.has_constant_verifier_error(self.current_unit as u32, node.into()))
    }
    pub fn static_type(&self, node: impl Into<NodeId>) -> Option<dartr_element::TypeId> {
        self.resolved?.tables.static_type.get(node.into()).copied()
    }
    pub fn element(&self, node: impl Into<NodeId>) -> Option<dartr_element::ElemRef> {
        self.resolved?.tables.element.get(node.into()).copied()
    }
    pub fn corresponding_parameter(
        &self,
        node: impl Into<NodeId>,
    ) -> Option<dartr_element::ElemRef> {
        let node = node.into();
        let tables = self.resolved?.tables;
        tables.param_element.get(node).copied().or_else(|| {
            let named = self.ast.cast::<dartr_ast::NamedArgument>(node)?;
            tables
                .param_element
                .get(self.ast[named].argument_expression.raw())
                .copied()
        })
    }
    /// Dart `correspondingParameter?.type` of an argument (the expression,
    /// or a `NamedArgument`).
    pub fn corresponding_parameter_type(
        &self,
        node: impl Into<NodeId>,
    ) -> Option<dartr_element::TypeId> {
        let node = node.into();
        let types = self.resolved?.corresponding_parameter_type;
        types.get(node).copied().or_else(|| {
            let named = self.ast.cast::<dartr_ast::NamedArgument>(node)?;
            types
                .get(self.ast[named].argument_expression.raw())
                .copied()
        })
    }
    pub fn declared_element(&self, node: impl Into<NodeId>) -> Option<dartr_element::ElementId> {
        let resolved = self.resolved?;
        let fragment = *resolved.tables.declared_fragment.get(node.into())?;
        resolved
            .ctx
            .fragment_data(fragment)?
            .element
            .try_get()
            .copied()
    }
    pub fn type_system(&self) -> Option<dartr_typesystem::TypeSystem<'a>> {
        Some(dartr_typesystem::TypeSystem::new(self.resolved?.ctx))
    }
    /// The library's defining unit, including when a processor visits a part.
    pub fn defining_unit(&self) -> &RuleContextUnit<'a> {
        &self.all_units[0]
    }
    pub fn package_info(&self) -> Option<&LintPackageInfo> {
        if let Some(info) = self.package_info {
            return Some(info);
        }
        if let Some(info) = self.all_units.first().and_then(|u| u.package_info) {
            return Some(info);
        }
        let cell = self.lazy_package_info?;
        let path = self.all_units.first()?.path;
        Some(cell.get_or_init(|| LintPackageInfo::for_defining_path(path)))
    }
    /// Workspace package root for the defining unit, if a pubspec exists.
    pub fn package_root(&self) -> Option<std::path::PathBuf> {
        self.package_info()?.package_root.clone()
    }
    /// Package root when the Dart workspace package is a `PubPackage`: the
    /// analyzer builds a pub workspace only when a
    /// `.dart_tool/package_config.json` exists at or above the package.
    pub fn pub_package_root(&self) -> Option<std::path::PathBuf> {
        let info = self.package_info()?;
        info.is_pub_package
            .then(|| info.package_root.clone())
            .flatten()
    }
    pub fn has_flutter_dep(&self) -> bool {
        self.package_info().is_some_and(|info| info.has_flutter_dep)
    }
    pub fn has_breaking_version(&self) -> bool {
        self.package_info()
            .is_some_and(|info| info.has_breaking_version)
    }
    pub fn pubspec_deps(&self) -> Option<&std::sync::Arc<PubspecDeps>> {
        self.package_info()?.pubspec_deps.as_ref()
    }
    pub fn is_in_lib_dir(&self) -> bool {
        self.package_info()
            .and_then(|info| info.package_root.as_deref())
            .is_some_and(|root| {
                std::path::Path::new(self.all_units[0].path).starts_with(root.join("lib"))
            })
    }
    pub fn is_in_public_dir(&self) -> bool {
        self.package_info()
            .and_then(|info| info.package_root.as_deref())
            .is_some_and(|root| {
                let cu_path = std::path::Path::new(self.all_units[0].path);
                let hook = root.join("hook");
                cu_path.starts_with(root.join("lib"))
                    || cu_path.starts_with(root.join("bin"))
                    || cu_path == hook.join("build.dart")
                    || cu_path == hook.join("link.dart")
            })
    }
    pub fn is_in_test_directory(&self) -> bool {
        self.package_info()
            .and_then(|info| info.package_root.as_deref())
            .is_some_and(|root| {
                std::path::Path::new(self.all_units[0].path).starts_with(root.join("test"))
            })
    }
    pub fn is_feature_enabled(&self, feature: ExperimentalFlag) -> bool {
        self.defining_unit()
            .parsed
            .feature_set
            .is_experiment_enabled(feature)
    }
    /// The visited unit's source URI. The analyzer uses a
    /// package URI for files mapped by package_config, and a file URI otherwise.
    pub fn source_uri(&self) -> String {
        if let Some(uri) = self
            .all_units
            .get(self.current_unit)
            .and_then(|u| u.source_uri)
        {
            return uri.to_owned();
        }
        compute_source_uri(self.path)
    }
    pub fn report_node(
        &self,
        out: &mut Vec<Diagnostic>,
        code: &'static DiagnosticCode,
        node: impl Into<NodeId>,
        args: &[&str],
    ) {
        let node = node.into();
        if !self.is_synthetic(node) {
            self.report_offset(
                out,
                code,
                self.ast.offset(node) as usize,
                self.ast.length(node) as usize,
                args,
            );
        }
    }
    pub fn report_token(
        &self,
        out: &mut Vec<Diagnostic>,
        code: &'static DiagnosticCode,
        token: TokenId,
        args: &[&str],
    ) {
        let token = self.ast.tokens.get(token);
        if !token.is_synthetic() {
            self.report_offset(
                out,
                code,
                token.offset as usize,
                token.length as usize,
                args,
            );
        }
    }
    pub fn report_offset(
        &self,
        out: &mut Vec<Diagnostic>,
        code: &'static DiagnosticCode,
        offset: usize,
        length: usize,
        args: &[&str],
    ) {
        out.push(Diagnostic::new(code, offset, length, args, vec![]));
    }
    pub fn is_synthetic(&self, node: impl Into<NodeId>) -> bool {
        use dartr_ast::{ExpressionStatement, Id, NamedType};
        let node = node.into();
        match self.ast.kind(node) {
            NodeKind::BooleanLiteral
            | NodeKind::SimpleIdentifier
            | NodeKind::SimpleStringLiteral
            | NodeKind::EmptyStatement => self
                .ast
                .tokens
                .get(self.ast.begin_token(node))
                .is_synthetic(),
            NodeKind::NamedType => {
                let n = &self.ast[Id::<NamedType>::from_raw(node)];
                self.ast.tokens.get(n.name).is_synthetic() && n.type_arguments.is_none()
            }
            NodeKind::ExpressionStatement => {
                let n = &self.ast[Id::<ExpressionStatement>::from_raw(node)];
                self.is_synthetic(n.expression)
                    && n.semicolon
                        .is_none_or(|token| self.ast.tokens.get(token).is_synthetic())
            }
            _ => false,
        }
    }
    pub fn text(&self, node: impl Into<NodeId>) -> String {
        let node = node.into();
        if self.ast.kind(node) == NodeKind::CompilationUnit {
            return self.source.to_owned();
        }
        let start = self.ast.tokens.byte_range(self.ast.begin_token(node)).start;
        let end = self.ast.tokens.byte_range(self.ast.end_token(node)).end;
        if let Some(text) = self.source.get(start..end) {
            return text.to_owned();
        }
        String::from_utf16_lossy(
            &self
                .source
                .encode_utf16()
                .skip(self.ast.offset(node) as usize)
                .take(self.ast.length(node) as usize)
                .collect::<Vec<_>>(),
        )
    }
}

fn compute_source_uri(path: &str) -> String {
    let file = std::path::Path::new(path);
    if let Some(dir) = file.parent() {
        for root in dir.ancestors() {
            let config = root.join(".dart_tool/package_config.json");
            let Ok(content) = std::fs::read_to_string(&config) else {
                continue;
            };
            if let Ok(config_value) = serde_json::from_str::<serde_json::Value>(&content)
                && let Some(packages) = config_value["packages"].as_array()
            {
                for package in packages {
                    let (Some(name), Some(root_uri)) =
                        (package["name"].as_str(), package["rootUri"].as_str())
                    else {
                        continue;
                    };
                    let package_root = if let Some(p) = root_uri.strip_prefix("file://") {
                        std::path::PathBuf::from(p)
                    } else if root_uri.contains(':') {
                        continue;
                    } else {
                        config.parent().unwrap().join(root_uri)
                    };
                    let package_dir =
                        package_root.join(package["packageUri"].as_str().unwrap_or(""));
                    if let Ok(package_dir) = package_dir.canonicalize()
                        && let Ok(relative) = file.strip_prefix(&package_dir)
                    {
                        return format!(
                            "package:{name}/{}",
                            relative.to_string_lossy().replace('\\', "/")
                        );
                    }
                }
            }
            break;
        }
    }
    if file.is_absolute() {
        format!("file://{}", path.replace('\\', "/"))
    } else {
        path.replace('\\', "/")
    }
}

pub type NodeProcessor = fn(&LinterContext<'_>, NodeId, &mut Vec<Diagnostic>);
pub type AfterLibraryProcessor = fn(&LinterContext<'_>, &mut Vec<Diagnostic>);
#[derive(Default)]
pub struct RuleVisitorRegistry {
    pub enable_timing: bool,
    pub timers: std::cell::RefCell<AnalysisRuleTimers>,
    subscriptions: IndexMap<NodeKind, Vec<(&'static str, NodeProcessor)>>,
    after_library: Vec<(&'static str, AfterLibraryProcessor)>,
}
pub type NodeLintRegistry = RuleVisitorRegistry;
impl RuleVisitorRegistry {
    pub fn with_timing(enable_timing: bool) -> Self {
        Self {
            enable_timing,
            ..Self::default()
        }
    }
    pub fn add(&mut self, kind: NodeKind, rule: &'static str, processor: NodeProcessor) {
        self.subscriptions
            .entry(kind)
            .or_default()
            .push((rule, processor));
    }
    pub fn add_after_library(&mut self, rule: &'static str, processor: AfterLibraryProcessor) {
        self.after_library.push((rule, processor));
    }
}
pub fn lint(parsed: &ParsedUnit, source: &str, path: &str, enabled: &[&str]) -> Vec<Diagnostic> {
    lint_library(
        &[RuleContextUnit {
            parsed,
            source,
            path,
            source_uri: None,
            package_info: None,
        }],
        enabled,
    )
    .remove(0)
}

/// Register once per library, visit each unit in source order, then run callbacks.
/// The first unit is the defining unit. All units must exist and be parsed.
pub fn lint_library(units: &[RuleContextUnit<'_>], enabled: &[&str]) -> Vec<Vec<Diagnostic>> {
    let mut out = lint_library_unfiltered(units, enabled);
    let lazy_package_info = std::cell::OnceCell::new();
    let package_info = units.first().and_then(|u| u.package_info);
    for (index, diagnostics) in out.iter_mut().enumerate() {
        let ctx = LinterContext {
            parsed: units[index].parsed,
            ast: &units[index].parsed.ast,
            source: units[index].source,
            path: units[index].path,
            all_units: units,
            current_unit: index,
            resolved: None,
            resolved_units: &[],
            package_info,
            lazy_package_info: Some(&lazy_package_info),
        };
        let ignores = IgnoreInfo::for_dart(&ctx);
        diagnostics.retain(|diagnostic| !ignores.ignored(&ctx, diagnostic));
    }
    out
}

/// Like [lint_library], without the ignore-comment filtering. The analyzer
/// filters all diagnostics of a unit together, with the `cannot-ignore`
/// codes of the analysis options: callers that do that use this function.
pub fn lint_library_unfiltered(
    units: &[RuleContextUnit<'_>],
    enabled: &[&str],
) -> Vec<Vec<Diagnostic>> {
    let Some(first) = units.first() else {
        return vec![];
    };
    let lazy_package_info = std::cell::OnceCell::new();
    let package_info = first.package_info;
    let context = |index: usize| {
        let unit = &units[index];
        LinterContext {
            parsed: unit.parsed,
            ast: &unit.parsed.ast,
            source: unit.source,
            path: unit.path,
            all_units: units,
            current_unit: index,
            resolved: None,
            resolved_units: &[],
            package_info,
            lazy_package_info: Some(&lazy_package_info),
        }
    };
    let mut registry = RuleVisitorRegistry::default();
    let enabled: IndexSet<_> = enabled.iter().map(|s| s.to_ascii_lowercase()).collect();
    let defining_context = context(0);
    for rule in ALL_RULES {
        if enabled.contains(rule.name) {
            rules::register(rule.name, &mut registry, &defining_context);
        }
    }
    let visitor = AnalysisRuleVisitor::new(&registry);
    let mut out = Vec::with_capacity(units.len());
    for (index, unit) in units.iter().enumerate() {
        let ctx = context(index);
        let mut diagnostics = vec![];
        visitor.visit(&ctx, unit.parsed.unit.raw(), &mut diagnostics);
        out.push(diagnostics);
    }
    let last_index = units.len() - 1;
    visitor.after_library(&context(last_index), &mut out[last_index]);
    deduplicate_diagnostics(&mut out);
    out
}

/// Run rules after body resolution; retain defining-unit metadata for parts.
/// Callers can defer ignore filtering until all analyzer diagnostics are available.
pub fn lint_resolved_library_unfiltered(
    units: &[ResolvedRuleContextUnit<'_>],
    enabled: &[&str],
) -> Vec<Vec<Diagnostic>> {
    if units.is_empty() {
        return vec![];
    }
    let lazy_package_info = std::cell::OnceCell::new();
    let package_info = units[0].package_info;
    let parsed_units: Vec<_> = units
        .iter()
        .map(|unit| RuleContextUnit {
            parsed: unit.parsed,
            source: unit.source,
            path: unit.path,
            source_uri: unit.source_uri,
            package_info: unit.package_info,
        })
        .collect();
    let context = |index: usize| {
        let unit = &units[index];
        LinterContext {
            parsed: unit.parsed,
            ast: unit.ast,
            source: unit.source,
            path: unit.path,
            all_units: &parsed_units,
            current_unit: index,
            resolved: unit.resolved,
            resolved_units: units,
            package_info,
            lazy_package_info: Some(&lazy_package_info),
        }
    };
    let mut registry = RuleVisitorRegistry::default();
    let enabled: IndexSet<_> = enabled.iter().map(|s| s.to_ascii_lowercase()).collect();
    for rule in ALL_RULES {
        if enabled.contains(rule.name) {
            rules::register(rule.name, &mut registry, &context(0));
        }
    }
    let visitor = AnalysisRuleVisitor::new(&registry);
    let mut out = vec![vec![]; units.len()];
    for (index, unit) in units.iter().enumerate() {
        visitor.visit(&context(index), unit.unit, &mut out[index]);
    }
    let last = units.len() - 1;
    visitor.after_library(&context(last), &mut out[last]);
    deduplicate_diagnostics(&mut out);
    out
}

// Dart source: pkg/analyzer/lib/error/listener.dart (RecordingDiagnosticListener)
fn deduplicate_diagnostics(units: &mut [Vec<Diagnostic>]) {
    for diagnostics in units {
        let mut seen = IndexSet::new();
        diagnostics.retain(|diagnostic| {
            seen.insert((
                diagnostic.code.unique_name,
                diagnostic.offset,
                diagnostic.length,
                diagnostic.message.clone(),
            ))
        });
    }
}

/// Resolved counterpart of [lint_library], including ignore comments.
pub fn lint_resolved_library(
    units: &[ResolvedRuleContextUnit<'_>],
    enabled: &[&str],
) -> Vec<Vec<Diagnostic>> {
    let mut out = lint_resolved_library_unfiltered(units, enabled);
    let lazy_package_info = std::cell::OnceCell::new();
    let package_info = units.first().and_then(|u| u.package_info);
    let parsed_units: Vec<_> = units
        .iter()
        .map(|unit| RuleContextUnit {
            parsed: unit.parsed,
            source: unit.source,
            path: unit.path,
            source_uri: unit.source_uri,
            package_info: unit.package_info,
        })
        .collect();
    for (index, diagnostics) in out.iter_mut().enumerate() {
        let unit = &units[index];
        let ctx = LinterContext {
            parsed: unit.parsed,
            ast: unit.ast,
            source: unit.source,
            path: unit.path,
            all_units: &parsed_units,
            current_unit: index,
            resolved: unit.resolved,
            resolved_units: units,
            package_info,
            lazy_package_info: Some(&lazy_package_info),
        };
        let ignores = IgnoreInfo::for_dart(&ctx);
        diagnostics.retain(|diagnostic| !ignores.ignored(&ctx, diagnostic));
    }
    out
}

/// A lint rule that panicked, or a lint computation that panicked outside
/// the rules. Dart's `AnalysisRuleVisitor._logException` catches the
/// exception of one rule on one node, logs it and goes on with the other
/// rules and nodes; dartr does the same, and keeps the error here so that the
/// caller can report it: diagnostics are missing, and that must not go
/// unnoticed (`dartr analyze` prints these and exits with 4).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LintInternalError {
    /// The rule that panicked; `None` when the lint computation of the
    /// library panicked outside a rule.
    pub rule: Option<String>,
    /// The file whose unit was being linted.
    pub path: String,
    /// The kind of the node the rule visited; `None` for an after-library
    /// callback.
    pub node: Option<String>,
    /// The panic message of the first panic.
    pub message: String,
    /// How many callbacks of this rule panicked in this file.
    pub count: usize,
}

impl std::fmt::Display for LintInternalError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match (&self.rule, &self.node) {
            (Some(rule), Some(node)) => write!(
                f,
                "internal error: the lint rule '{rule}' panicked while visiting a {node} in {}",
                self.path
            )?,
            (Some(rule), None) => write!(
                f,
                "internal error: the lint rule '{rule}' panicked after visiting the library of {}",
                self.path
            )?,
            (None, _) => write!(
                f,
                "internal error: computing the lints of {} panicked",
                self.path
            )?,
        }
        if self.count > 1 {
            write!(f, " ({} times)", self.count)?;
        }
        write!(f, ": {}", self.message)
    }
}

static INTERNAL_ERRORS: std::sync::Mutex<Vec<LintInternalError>> =
    std::sync::Mutex::new(Vec::new());

/// Records [error]; a second panic of the same rule in the same file counts.
pub fn report_internal_error(error: LintInternalError) {
    let mut errors = INTERNAL_ERRORS
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if let Some(existing) = errors
        .iter_mut()
        .find(|e| e.rule == error.rule && e.path == error.path)
    {
        existing.count += error.count;
    } else {
        errors.push(error);
    }
}

/// The internal errors recorded since the last call, in the order they
/// happened.
pub fn take_internal_errors() -> Vec<LintInternalError> {
    std::mem::take(
        &mut *INTERNAL_ERRORS
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner),
    )
}

/// The message of a caught panic.
pub fn panic_message(payload: &(dyn std::any::Any + Send)) -> String {
    payload
        .downcast_ref::<String>()
        .cloned()
        .or_else(|| payload.downcast_ref::<&str>().map(|s| s.to_string()))
        .unwrap_or_else(|| "panic".to_string())
}

/// The rule named by `DARTR_LINT_PANIC_FOR_TESTING`, which panics instead of
/// running: the tests of the internal-error reporting use it to make a real
/// rule fail inside the real `dartr analyze`.
fn panic_injected_for(rule: &str) -> bool {
    static INJECTED: std::sync::LazyLock<Option<String>> =
        std::sync::LazyLock::new(|| std::env::var("DARTR_LINT_PANIC_FOR_TESTING").ok());
    INJECTED.as_deref() == Some(rule)
}

/// Runs one callback of [rule] under its own `catch_unwind` (Dart
/// `_runSubscriptions`), recording a panic as a [LintInternalError].
fn run_rule_callback(rule: &str, path: &str, node: Option<NodeKind>, callback: impl FnOnce()) {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if panic_injected_for(rule) {
            panic!("panic injected into the lint rule '{rule}' by DARTR_LINT_PANIC_FOR_TESTING");
        }
        callback();
    }));
    if let Err(payload) = result {
        report_internal_error(LintInternalError {
            rule: Some(rule.to_string()),
            path: path.to_string(),
            node: node.map(|kind| format!("{kind:?}")),
            message: panic_message(&*payload),
            count: 1,
        });
    }
}

/// The generated Dart visitor runs each node's subscriptions before children.
/// Each callback runs under its own `catch_unwind`, like Dart's
/// `_runSubscriptions` catches the exception of one subscription: a rule that
/// panics loses its own diagnostic for that node, the other rules and nodes
/// still run, and the panic is recorded (see [take_internal_errors]).
pub struct AnalysisRuleVisitor<'a> {
    registry: &'a RuleVisitorRegistry,
}
impl<'a> AnalysisRuleVisitor<'a> {
    pub fn new(registry: &'a RuleVisitorRegistry) -> Self {
        Self { registry }
    }
    pub fn visit(&self, ctx: &LinterContext<'_>, root: NodeId, out: &mut Vec<Diagnostic>) {
        let mut pending = vec![root];
        while let Some(node) = pending.pop() {
            let kind = ctx.ast.kind(node);
            if let Some(subscriptions) = self.registry.subscriptions.get(&kind) {
                for (rule, processor) in subscriptions {
                    if self.registry.enable_timing {
                        self.registry.timers.borrow_mut().get_timer(rule).start();
                    }
                    run_rule_callback(rule, ctx.path, Some(kind), || processor(ctx, node, out));
                    if self.registry.enable_timing {
                        self.registry.timers.borrow_mut().get_timer(rule).stop();
                    }
                }
            }
            pending.extend(ctx.ast.children(node).into_iter().rev());
        }
    }
    pub fn after_library(&self, ctx: &LinterContext<'_>, out: &mut Vec<Diagnostic>) {
        for (rule, callback) in &self.registry.after_library {
            if self.registry.enable_timing {
                self.registry.timers.borrow_mut().get_timer(rule).start();
            }
            run_rule_callback(rule, ctx.path, None, || callback(ctx, out));
            if self.registry.enable_timing {
                self.registry.timers.borrow_mut().get_timer(rule).stop();
            }
        }
    }
}

/// Run enabled AST rules using the parsed unit's source text.
/// File-sensitive rules should use `lint` with the actual file path.
pub fn run_lints(parsed: &ParsedUnit, enabled: &[&str]) -> Vec<Diagnostic> {
    lint(parsed, &parsed.ast.tokens.source, "", enabled)
}

/// Apply explicitly enabled configurations and severity overrides.
pub fn lint_with_config(
    parsed: &ParsedUnit,
    source: &str,
    path: &str,
    configs: &IndexMap<String, RuleConfig>,
) -> Vec<Diagnostic> {
    let registry = Registry::builtin();
    let enabled: Vec<_> = registry.enabled(configs).map(|rule| rule.name).collect();
    let mut diagnostics = lint(parsed, source, path, &enabled);
    for diagnostic in &mut diagnostics {
        if let Some(config) = configs.get(diagnostic.code.name)
            && let Some(severity) = config.diagnostic_severity()
        {
            diagnostic.severity = severity;
        }
    }
    diagnostics
}

#[cfg(test)]
mod internal_error_tests {
    use super::*;

    fn panicking(_: &LinterContext<'_>, _: NodeId, _: &mut Vec<Diagnostic>) {
        panic!("boom");
    }

    fn reporting(c: &LinterContext<'_>, node: NodeId, out: &mut Vec<Diagnostic>) {
        c.report_node(out, &dartr_diagnostics::diag::EMPTY_STATEMENTS, node, &[]);
    }

    fn panicking_after_library(_: &LinterContext<'_>, _: &mut Vec<Diagnostic>) {
        panic!("boom after library");
    }

    /// A rule that panics on every node does not stop the rule after it on
    /// the same node, nor the visit of the later nodes; each panic is
    /// recorded once per rule and file, with a count.
    #[test]
    fn a_panicking_rule_is_recorded_and_the_others_still_report() {
        let path = "/internal_error_tests/a.dart";
        let source = "void f() { ; ; ; }\n";
        let parsed = dartr_ast_builder::parse_string(source, path);
        let units = [RuleContextUnit {
            parsed: &parsed,
            source,
            path,
            source_uri: None,
            package_info: None,
        }];
        let ctx = LinterContext {
            parsed: &parsed,
            ast: &parsed.ast,
            source,
            path,
            all_units: &units,
            current_unit: 0,
            resolved: None,
            resolved_units: &[],
            package_info: None,
            lazy_package_info: None,
        };
        let mut registry = RuleVisitorRegistry::default();
        registry.add(NodeKind::EmptyStatement, "panicking_rule", panicking);
        registry.add(NodeKind::EmptyStatement, "reporting_rule", reporting);
        registry.add_after_library("panicking_after_library", panicking_after_library);
        let visitor = AnalysisRuleVisitor::new(&registry);
        let mut out = vec![];
        visitor.visit(&ctx, parsed.unit.raw(), &mut out);
        visitor.after_library(&ctx, &mut out);
        assert_eq!(out.len(), 3, "the reporting rule runs on all three nodes");
        let errors: Vec<_> = take_internal_errors()
            .into_iter()
            .filter(|e| e.path == path)
            .collect();
        assert_eq!(
            errors,
            vec![
                LintInternalError {
                    rule: Some("panicking_rule".to_string()),
                    path: path.to_string(),
                    node: Some("EmptyStatement".to_string()),
                    message: "boom".to_string(),
                    count: 3,
                },
                LintInternalError {
                    rule: Some("panicking_after_library".to_string()),
                    path: path.to_string(),
                    node: None,
                    message: "boom after library".to_string(),
                    count: 1,
                },
            ]
        );
        assert_eq!(
            errors[0].to_string(),
            "internal error: the lint rule 'panicking_rule' panicked while visiting a \
             EmptyStatement in /internal_error_tests/a.dart (3 times): boom"
        );
    }
}
