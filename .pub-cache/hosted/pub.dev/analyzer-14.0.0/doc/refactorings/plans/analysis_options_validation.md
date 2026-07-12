# Analysis Options Validation Entry Point

This document describes the current analysis-options parsing and validation model in analyzer, the problems caused by having several visible entry points, and a staged plan for moving to one file-based entry point that can be tested and reviewed incrementally.

The goal is to make analysis-options diagnostics behave as one coherent product feature:

```text
analysis options file + source resolution + context inputs
  -> effective AnalysisOptionsImpl + diagnostics for the initial file and included files
```

The proposed direction is to introduce a single entry point for the combined operation, for example:

```text
final class AnalysisOptionsParseSession {
  AnalysisOptionsParseResult parse({
    required SourceFactory sourceFactory,
    required Folder contextRoot,
    required File file,
    VersionConstraint? sdkVersionConstraint,
  });
}

final class AnalysisOptionsParseResult {
  final File file;
  final AnalysisOptionsFileContent? content;
  final AnalysisOptionsImpl analysisOptions;
  final List<Diagnostic> diagnostics;
}

final class AnalysisOptionsFileContent {
  final String text;
  final LineInfo lineInfo;
  final YamlMap? yamlMap;
}
```

Internally, this entry point owns the user-visible operation and delegates to smaller private implementation units for merged YAML construction, YAML section validation, and cross-file lint rule checks. The important distinction is that callers and most tests should not need to know which internal component owns each part of the operation.

The desired long-term split is:

- `AnalysisOptionsParseSession`: parse one or more initial files in one atomic operation into the effective `AnalysisOptionsImpl` and diagnostics, reusing internal caches for that operation.
- `_MergedOptionsYamlBuilder`: private lower-level helper for resolving includes and merging effective YAML while the parser implementation is being unified.
- `AnalysisOptionsValidator`: legacy lower-level helper for producing diagnostics while the parser implementation is being unified.
- `AnalysisOptionsImpl.fromYaml`: apply a merged `YamlMap` to actual analyzer behavior.

<a name="ultimate-goal"></a>
## Ultimate Goal

The final shape is not one large parser that knows every detail of every options section. The final shape is one obvious file-based entry point that owns the user-visible operation, with smaller validators and builders behind it.

`pkg/analyzer/lib/src/analysis_options/analysis_options_parser.dart` should own the complete operation "parse this analysis-options file and return both the effective options and the diagnostics users should see." That includes the initial file identity, reading the initial file content, YAML parsing, include traversal, missing and recursive include diagnostics, validation of included files, wrapping included-file diagnostics as `includedFileWarning`, diagnostic source ownership, SDK-version inputs, relative path rebasing, and the shared caches for one parse run.

`pkg/analyzer/lib/src/analysis_options/options_file_validator.dart` should remain a lower-level implementation unit for validating one already-parsed `YamlMap` in the current source/reporter context. It should compose the section validators for `analyzer`, `code-style`, `formatter`, `linter`, and `plugins`, but it should not parse files, read the initial file, walk includes, or decide how diagnostics from included files are reported to the user.

So the target flow is:

```text
AnalysisOptionsParseSession.parse(sourceFactory: ..., contextRoot: ..., file: ...)
  parse the initial YAML
  validate the initial parsed map with `_OptionsFileValidator`
  walk include directives for diagnostic validation
    resolve included source
    parse included YAML
    validate the included parsed map with `_OptionsFileValidator`
    report include errors or wrap included diagnostics at the original include
  merge effective options
  return AnalysisOptionsParseResult
```

In that shape, `_OptionsFileValidator` does not become redundant when `AnalysisOptionsParseSession` exists. It becomes the private map validator used by the top-level file parser. Deleting the abstraction is not the goal.

Most tests and production callers that need analysis-options behavior should enter through `AnalysisOptionsParseSession`. Direct tests of `_OptionsFileValidator`, `_LinterRuleOptionsValidator`, or smaller validators should remain only when they protect behavior that is intentionally independent from the full file operation.

During the transition, the private merged-YAML builder, `AnalysisOptionsValidator`, and `AnalysisOptionsImpl.fromYaml` stay as implementation pieces behind the combined parser. The merged-YAML builder answers "what merged YAML should be used?", the validator answers "what diagnostics should users see?", and `AnalysisOptionsImpl.fromYaml` answers "what runtime analyzer behavior follows from this YAML?" The goal is to hide that split from normal callers and eventually share one include walk.

## Table of Contents

- [Ultimate Goal](#ultimate-goal)
- [Current Model](#current-model)
  - [AnalysisOptionsFileKeys](#current-keys)
  - [Merged Options YAML Builder](#current-provider)
  - [OptionsValidator](#current-options-validator)
  - [_OptionsFileValidator](#current-options-file-validator)
  - [_AnalyzerOptionsValidator](#current-analyzer-options-validator)
  - [_LinterRuleOptionsValidator](#current-linter-rule-options-validator)
  - [AnalysisOptionsValidator And Walker](#current-analysis-options-validator)
  - [AnalysisOptionsImpl](#current-analysis-options-impl)
  - [AnalysisOptionsMap And Context Construction](#current-context-construction)
  - [Tests](#current-tests)
- [Current Data Flow](#current-data-flow)
  - [Production Options Application](#flow-production-application)
  - [Options Diagnostics](#flow-options-diagnostics)
  - [Lint Rule Cross-File Validation](#flow-lint-cross-file)
  - [Test Diagnostics](#flow-test-diagnostics)
- [Problems](#problems)
  - [No Single Validation Surface](#problem-no-single-surface)
  - [Analyzer Is A Misleading Name](#problem-analyzer-name)
  - [Tests Encode Internal Structure](#problem-tests-internals)
  - [Include Handling Is Split Across Components](#problem-include-split)
  - [Validation And Application Boundaries Are Blurry](#problem-validation-application)
  - [Public, Package-Private, And Private Boundaries Are Unclear](#problem-visibility)
  - [Test Organization Needs One Obvious Home](#problem-test-organization)
  - [Provider Documentation Does Not Match Current Behavior](#problem-provider-doc)
- [Design Goals](#design-goals)
- [Non-Goals](#non-goals)
- [Proposed Direction](#proposed-direction)
  - [Single Parse Entry Point](#proposed-entry-point)
  - [Internal Component Validators](#proposed-component-validators)
  - [Merged YAML Builder Stays Diagnostic-Free](#proposed-provider)
  - [Application Remains Separate](#proposed-application)
  - [Testing Through One Surface](#proposed-testing)
  - [Naming](#proposed-naming)
- [Proposed API Shape](#proposed-api-shape)
  - [Parse Inputs](#api-parse-inputs)
  - [Parse Method](#api-validation-methods)
  - [Result Type](#api-result-type)
  - [Test Helper Shape](#api-test-helper)
- [Migration Plan](#migration-plan)
  - [Stage 0: Document The Current Model](#stage-0)
  - [Stage 1: Tests Only - Introduce One Shared Test Harness](#stage-1)
  - [Stage 2: Tests Only - Move OptionsFileValidator Tests To The Harness](#stage-2)
  - [Stage 3: Tests Only - Move LinterRuleOptionsValidator Tests To The Harness](#stage-3)
  - [Stage 4: Tests Only - Normalize Include Diagnostic Tests](#stage-4)
  - [Stage 5: Implementation Only - Add AnalysisOptionsValidator As A Wrapper](#stage-5)
  - [Stage 6: Tests Only - Switch The Harness To AnalysisOptionsValidator](#stage-6)
  - [Stage 7: Implementation Only - Move Include Walking Behind The New Class](#stage-7)
  - [Stage 8: Implementation Only - Rename Or Retire AnalysisOptionsAnalyzer](#stage-8)
  - [Stage 9: Tests Only - Remove Redundant Direct Validator Tests](#stage-9)
  - [Stage 10: Implementation Only - Narrow Internal Visibility](#stage-10)
  - [Stage 11: Implementation Only - Clarify Provider Documentation](#stage-11)
  - [Stage 12: Optional Implementation - Enrich The Parse Result](#stage-12)
- [Review Strategy](#review-strategy)
- [Suggested CL Boundaries](#suggested-cl-boundaries)
- [Open Questions](#open-questions)

<a name="current-model"></a>
## Current Model

Analysis-options support is currently split across several files and classes. Some pieces are cleanly separated, but their boundaries are not obvious from tests or names.

<a name="current-keys"></a>
### AnalysisOptionsFileKeys

`pkg/analyzer/lib/src/analysis_options/analysis_options_file.dart` contains `AnalysisOptionsFileKeys`.

This class is the vocabulary for the options file. It defines top-level keys such as:

- `analyzer`
- `code-style`
- `formatter`
- `linter`
- `plugins`

It also defines nested keys such as:

- `include`
- `errors`
- `exclude`
- `language`
- `optional-checks`
- `enable-experiment`
- `rules`
- `page_width`
- `trailing_commas`

It is not a parser and not a validator. It is a centralized list of known key strings and small sets of supported option names or supported literal values.

<a name="current-provider"></a>
### Merged Options YAML Builder

`pkg/analyzer/lib/src/analysis_options/analysis_options_parser.dart` contains `_MergedOptionsYamlBuilder`.

The builder loads analysis-options YAML and produces the effective merged `YamlMap` used to create `AnalysisOptionsImpl`. Its main responsibilities are:

- parse content using `parseAnalysisOptionsYaml`,
- return an empty `YamlMap` for non-map YAML content,
- throw `OptionsFormatException` for malformed YAML in string parsing,
- resolve `include` directives through a `SourceFactory`,
- recursively load included files,
- cache merged `YamlMap`s during one `AnalysisOptionsParseSession`,
- merge included options with the including file,
- rewrite relative plugin path options from included files.

The important semantic point is that the builder is not a diagnostic validator. When an include cannot be resolved, or when an include would repeat a handled source, the builder returns the options it can compute. It does not report `includeFileNotFound`, `recursiveIncludeFile`, or `includedFileWarning`.

The provider's merge behavior is delegated to `Merger` in `pkg/analyzer/lib/src/util/yaml.dart`:

- maps merge recursively,
- lists merge without duplicates,
- list-of-string lint rules can be promoted to map-of-bool lint rules,
- an overriding scalar replaces a default scalar,
- a `null` overriding scalar leaves the default value in place.

This means `_MergedOptionsYamlBuilder` answers "what effective YAML should be used?" It does not answer "what diagnostics should be reported?"

<a name="current-options-validator"></a>
### OptionsValidator

`pkg/analyzer/lib/src/analysis_options/options_validator.dart` defines the small validator interface:

```text
abstract class OptionsValidator {
  void validate(DiagnosticReporter reporter, YamlMap options);
}
```

Several internal validators implement this shape. The interface is useful, but it is not itself the desired user-facing analysis-options validation entry point. It validates one already-parsed `YamlMap` using a caller-supplied `DiagnosticReporter`.

<a name="current-options-file-validator"></a>
### _OptionsFileValidator

`pkg/analyzer/lib/src/analysis_options/options_file_validator.dart` is a part of `analysis_options_validator.dart` and contains `_OptionsFileValidator`.

`_OptionsFileValidator` is a composite validator for one options YAML map. It does not own parsing and does not own include traversal. It owns a list of component validators:

- `_AnalyzerOptionsValidator`
- `_CodeStyleOptionsValidator`
- `_FormatterOptionsValidator`
- `_LinterTopLevelOptionsValidator`
- `_LinterRuleOptionsValidator`
- `_PluginsOptionsValidator`

It calls each component validator in order. It is a good internal abstraction: it hides the list of section validators behind one "validate this map" method.

It is now private to the analysis-options validation library. Tests should normally exercise it through `AnalysisOptionsValidator`.

<a name="current-analyzer-options-validator"></a>
### _AnalyzerOptionsValidator

`_AnalyzerOptionsValidator` is another composite validator, scoped to the `analyzer:` section. It delegates to smaller validators such as:

- `_AnalyzerTopLevelOptionsValidator`
- `_StrongModeOptionValueValidator`
- `_ErrorFilterOptionValidator`
- `_EnableExperimentsValidator`
- `_LanguageOptionValidator`
- `_OptionalChecksValueValidator`
- `_CannotIgnoreOptionValidator`

This is a reasonable internal split. The top-level validation facade owns file-level behavior, while this class owns only the `analyzer:` map shape and values.

<a name="current-linter-rule-options-validator"></a>
### _LinterRuleOptionsValidator

`pkg/analyzer/lib/src/analysis_options/linter_rule_options_validator.dart` contains `_LinterRuleOptionsValidator`.

This validator owns lint-rule semantics inside the `linter:` section:

- undefined lint names,
- supported lint values,
- duplicate enabled rules,
- incompatible rules in the same file,
- incompatible rules across included files,
- deprecated lints,
- deprecated lints with replacements,
- removed lints,
- replaced lints.

This validator is special because it participates in cross-file lint-rule semantics. The include walker collects effective lint-rule state from included files and then asks `_LinterRuleOptionsValidator` to compare included rules with current-file rules and with sibling includes.

That include reading is not the same responsibility as include diagnostic traversal. It is needed to answer lint-rule semantic questions such as "does this file enable a rule that is incompatible with a rule enabled in an included file?"

<a name="current-analysis-options-validator"></a>
### AnalysisOptionsValidator And Walker

`pkg/analyzer/lib/src/analysis_options/analysis_options_validator.dart` contains `AnalysisOptionsValidator` and the private `_AnalysisOptionsValidatorWalker`.

`AnalysisOptionsValidator` is the diagnostic entry point. `_AnalysisOptionsValidatorWalker` owns the mutable state for one validation request. Together they:

- accept an initial `File`,
- accept the initial content from `AnalysisOptionsParseSession`,
- parse the initial content,
- call `_OptionsFileValidator` for that file,
- find `include` directives,
- resolve included sources,
- report missing include diagnostics,
- report recursive include diagnostics,
- validate included files,
- wrap diagnostics from included files as `includedFileWarning` at the original include location,
- track the include chain while walking.

The public method is:

```text
List<Diagnostic> validate({required File file, required String content})
```

This is an internal validation surface behind `AnalysisOptionsParseSession`. The mutable traversal state stays in `_AnalysisOptionsValidatorWalker`, and tests that need inline diagnostic expectations write marker-free content to the initial file before calling the parser.

<a name="current-analysis-options-impl"></a>
### AnalysisOptionsImpl

`pkg/analyzer/lib/src/dart/analysis/analysis_options.dart` contains `AnalysisOptionsImpl` and `AnalysisOptionsBuilder`.

`AnalysisOptionsImpl.fromYaml` applies a merged `YamlMap` to the analyzer's runtime behavior. It computes fields such as:

- `errorProcessors`,
- enabled experiments,
- `excludePatterns`,
- language strictness flags,
- optional checks,
- legacy plugin names,
- new plugin configurations,
- linter rule configs and enabled lint rules,
- code-style options,
- formatter options,
- unignorable diagnostic code names.

This step is not diagnostic validation. It intentionally ignores malformed shapes in many places, because validation is expected to have happened through the diagnostic path.

<a name="current-context-construction"></a>
### AnalysisOptionsMap And Context Construction

`ContextBuilder` constructs analysis contexts by:

1. finding an options file for each relevant folder,
2. using `AnalysisOptionsParseSession.parse` to get the effective options and diagnostics,
3. storing the result in an `AnalysisOptionsMap`.

`ContextLocator` also uses `AnalysisOptionsParseSession` for tasks that need early knowledge of options, such as legacy plugin discovery and excluded glob discovery.

These paths rely on options loading and application. They do not necessarily produce user-facing diagnostics about the options file.

<a name="current-tests"></a>
### Tests

The analyzer analysis-options tests now live under one directory:

```text
pkg/analyzer/test/src/analysis_options/
```

`analysis_options_build_test.dart` contains the build-side coverage: file loading, include merging, `AnalysisOptionsImpl.fromYaml`, and effective runtime options built from a starting file.

`analysis_options_validation_test.dart` contains the diagnostic validation coverage that used to be split across direct validator tests and diagnostics tests. These tests use `AnalysisOptionsTestSupport` and enter through `AnalysisOptionsValidator`.

`analysis_options_test_support.dart` contains the shared inline-diagnostic helper for analysis-options validation tests.

The important test split is now behavioral rather than directory-based: build tests cover the effective options path from YAML/files to runtime options, and validation tests cover diagnostics through the single diagnostic entry point.

<a name="current-data-flow"></a>
## Current Data Flow

<a name="flow-production-application"></a>
### Production Options Application

Normal context construction applies options roughly as follows:

```text
ContextBuilder
  sourceFactory = workspace.createSourceFactory(...)
  parseSession = AnalysisOptionsParseSession()

  for each options file:
    result = parseSession.parse(
      sourceFactory: sourceFactory,
      contextRoot: contextRoot,
      file: file,
    )
    analysisOptionsMap[folder] = result.analysisOptions
```

This path needs a merged options map. It does not need to produce validation diagnostics while building `AnalysisOptionsImpl`.

<a name="flow-options-diagnostics"></a>
### Options Diagnostics

Diagnostics for an options file are produced roughly as follows:

```text
AnalysisOptionsValidator.validate(file: file, content: content)
  options = parseAnalysisOptionsYaml(content)
  _AnalysisOptionsValidatorWalker.validate(content)
    _OptionsFileValidator.validate(options, reporter)
      _AnalyzerOptionsValidator.validate(...)
      _CodeStyleOptionsValidator.validate(...)
      _FormatterOptionsValidator.validate(...)
      _LinterTopLevelOptionsValidator.validate(...)
      _LinterRuleOptionsValidator.validate(...)
      _PluginsOptionsValidator.validate(...)

    for each include:
      resolve included source
      report include diagnostics if needed
      parse included content
      temporarily switch reporter/listener/source
      _validate(includedOptions)
      wrap included diagnostics as includedFileWarning
```

This is the behavior now hidden behind the diagnostic entry point and, during the next phase, behind the combined parse entry point.

<a name="flow-lint-cross-file"></a>
### Lint Rule Cross-File Validation

Lint-rule validation has an additional internal include read:

```text
_AnalysisOptionsValidatorWalker._validate(options)
  rules = options['linter']['rules']
  includeNode = options['include']
  localRules = _OptionsFileValidator.validate(options).linterRules
  for each include:
    includedRules = _validateInclude(includeNode)
  _LinterRuleOptionsValidator.reportIncompatibleIncluded(...)
  _LinterRuleOptionsValidator.reportIncompatibleWithIncluded(...)
```

This is why simply saying "include traversal belongs in exactly one place" is too imprecise. There are two include-related questions:

- What files should be validated, and where should diagnostics be reported?
- What effective or included lint rules are relevant to this file's lint semantics?

The first belongs in the top-level file operation. The second can remain inside `_LinterRuleOptionsValidator`, but should be hidden behind the parser for callers and most tests.

<a name="flow-test-diagnostics"></a>
### Test Diagnostics

Inline diagnostic expectation tests now generally do this:

```text
test code with markers
  -> removeDiagnosticExpectations
  -> write marker-free files
  -> run one analyzer/validator path
  -> updateExpectedDiagnosticsForFiles
  -> compare regenerated code with original code
```

The good part is that expected diagnostics are now close to source text. Analysis-options validation tests share the same validator path before the expectation comparison.

<a name="problems"></a>
## Problems

These were the problems that motivated the staged refactoring. Several have been resolved by the completed stages, but keeping the list is useful context for reviewing the previous CLs.

<a name="problem-no-single-surface"></a>
### No Single Validation Surface

Before the refactoring there was no obvious class whose contract was:

```text
validate this analysis options file and return the diagnostics users should see
```

This is now the role of `AnalysisOptionsValidator`.

The risk this plan was designed to remove was that tests and future production callers could reasonably choose several different entry points:

- `AnalysisOptionsAnalyzer`
- `OptionsFileValidator`
- `LinterRuleOptionsValidator`
- direct provider parsing followed by a validator

This increases the chance that a test passes through a lower-level path while the real user-visible path has different include handling, source locations, or diagnostic wrapping.

<a name="problem-analyzer-name"></a>
### Analyzer Is A Misleading Name

`AnalysisOptionsAnalyzer` was doing validation, not Dart code analysis. The name also conflicted with the broader analyzer package, where "analysis" usually means a much larger operation involving contexts, drivers, files, libraries, and resolution.

The class has been retired in favor of `AnalysisOptionsValidator`. The old method name `walkIncludes` was also implementation-oriented: a caller wants to validate options, and include walking is one detail of how validation is implemented.

<a name="problem-tests-internals"></a>
### Tests Encode Internal Structure

Direct tests of `OptionsFileValidator` and `LinterRuleOptionsValidator` made the internal split sticky. If a future refactoring wanted to move lint-rule validation behind a different helper or merge it into another component, many tests had to change even if user-visible behavior stayed the same.

The test suite should primarily protect observable behavior:

- diagnostic code,
- diagnostic message,
- diagnostic source range,
- context messages,
- which file owns each diagnostic,
- include wrapping behavior.

Those are properties of the top-level validation operation, not of a particular private validator class.

<a name="problem-include-split"></a>
### Include Handling Is Split Across Components

Includes are currently involved in three places:

- `_MergedOptionsYamlBuilder` resolves and merges includes for effective YAML.
- `AnalysisOptionsValidator` walks includes to validate included files and report include diagnostics.
- `_LinterRuleOptionsValidator` compares included linter rule state collected by the include walker.

This split is understandable, but it is hard to explain from the current class names alone. It also makes it easy to test only one part of include behavior.

For example, a direct lint-rule validator test can check an incompatible included lint, but it does not necessarily exercise:

- malformed included YAML wrapping,
- missing include diagnostics,
- recursive include diagnostics,
- source span ownership through the first include in a chain,
- validation of non-linter sections in included files.

<a name="problem-validation-application"></a>
### Validation And Application Boundaries Are Blurry

`AnalysisOptionsParseSession`, its private merged-YAML builder, and `AnalysisOptionsImpl.fromYaml` are used in production context construction. `AnalysisOptionsValidator` and its component validators are used for diagnostics behind that parser facade. Tests can still cross these concerns if they are not named or grouped clearly.

This can obscure the intended contracts:

- loading and merging should be tolerant and diagnostic-free,
- validation should report malformed or unsupported options,
- application should compute runtime behavior from a `YamlMap`.

The single parser entry point makes this separation easier to state at call sites while still keeping merged-YAML construction, validation, and application logic separate internally.

<a name="problem-visibility"></a>
### Public, Package-Private, And Private Boundaries Are Unclear

Many validators are now private classes behind `AnalysisOptionsValidator`. The remaining design point is to keep that boundary from leaking back into tests or callers.

When internal validators become test fixtures or package-visible call sites again, it becomes harder to know which classes are intended extension points, stable internal seams, or implementation details.

The current visibility is much closer to the desired architecture: the validator facade is the narrow entry point, and the component validators are implementation details.

<a name="problem-test-organization"></a>
### Test Organization Needs One Obvious Home

There used to be tests under both:

- `test/src/options`
- `test/src/diagnostics/analysis_options`

The difference was not obvious. Some tests were about effective options, some were about validation diagnostics, and some were about include behavior. That directory split made it easy to confuse:

- provider tests,
- application tests,
- diagnostic tests,
- lower-level validator tests.

Analyzer analysis-options tests now live under `test/src/analysis_options`. The target state is to keep the one obvious home while preserving behavioral grouping inside it: loading and merge tests, application tests for runtime options, and validation tests through the shared diagnostic helper.

<a name="problem-provider-doc"></a>
### Merged Map Include Behavior Needs Clear Documentation

Older provider documentation said that merged options recursively merged included options and removed any `include` directive from the resulting options map. Current behavior can leave the including file's `include` key in the merged map.

This is not the main refactoring target, but it is a source of confusion when trying to understand which component owns include semantics.

Any cleanup should be staged separately from validation behavior changes.

<a name="design-goals"></a>
## Design Goals

- Provide one obvious analysis-options parse entry point that returns both effective options and diagnostics.
- Make the entry point start from an options file or file-like source identity, not from an already-parsed `YamlMap`.
- Keep parsing, include traversal, validation, and diagnostic source ownership inside that entry point.
- Keep section validators as internal implementation details.
- Preserve current diagnostic behavior unless a CL explicitly states and tests a behavior change.
- Make tests for analysis-options diagnostics and effective options enter through the same file-based parse surface when they exercise a full options-file scenario.
- Keep narrow merged-YAML tests separate only when they are intentionally testing raw merge semantics.
- Keep narrow `AnalysisOptionsImpl.fromYaml` application tests separate only when they are intentionally testing YAML-to-runtime mapping independent of file traversal.
- Allow Gerrit review to proceed in small CLs that mostly change either tests or implementation, not both.
- Make each migration CL have a simple safety story.

<a name="non-goals"></a>
## Non-Goals

- Do not redesign the analysis-options YAML format.
- Do not change merge semantics as part of the validation entry-point refactoring.
- Do not change diagnostic messages, locations, or wrapping behavior unless a dedicated CL explicitly does so.
- Do not remove internal validators just to reduce the number of classes. Private component validators are useful.
- Do not force all analysis-options tests into one physical Dart class if that makes the file too large. The important target is one test entry surface.
- Do not make `AnalysisOptionsImpl.fromYaml` report diagnostics.
- Do not make the merged-YAML builder report diagnostics.
- Do not make analyzer plugin option validation part of this refactoring beyond preserving the current `_PluginsOptionsValidator` behavior.

<a name="proposed-direction"></a>
## Proposed Direction

<a name="proposed-entry-point"></a>
### Single Parse Entry Point

Introduce a class whose name and API express the desired operation:

```text
final class AnalysisOptionsParseSession {
  AnalysisOptionsParseResult parse({
    required SourceFactory sourceFactory,
    required Folder contextRoot,
    required File file,
    VersionConstraint? sdkVersionConstraint,
  });
}
```

The exact names can change, but the class should be responsible for:

- initial YAML parsing,
- parse diagnostics for malformed initial YAML,
- section validation for the initial file,
- include resolution,
- missing include diagnostics,
- recursive include diagnostics,
- validation of included files,
- included-file warning wrapping,
- effective option merging and application,
- preserving current source ranges and context messages,
- sharing the internal caches used by parser components.

The staged migration introduced the diagnostic facade first, then moved include traversal behind it and retired the old `AnalysisOptionsAnalyzer` name. The next step is a parser facade that returns both the effective options and diagnostics while the implementation still delegates internally.

<a name="proposed-component-validators"></a>
### Internal Component Validators

Keep component validators for local complexity:

- analyzer section validator,
- formatter validator,
- code-style validator,
- linter top-level validator,
- lint-rule validator,
- plugins validator.

These validators should be internal. Tests should usually not instantiate them directly. Direct tests are appropriate only when a component owns behavior that is deliberately independent from the full validation operation and difficult to exercise through a file.

This preserves a deep module shape:

```text
public-ish interface:
  AnalysisOptionsParseSession.parse(sourceFactory: ..., contextRoot: ..., file: ...)

internal implementation:
  include traversal
  composite map validator
  section validators
  lint semantic validator
```

<a name="proposed-provider"></a>
### Merged YAML Builder Stays Diagnostic-Free

The private merged-YAML builder should remain focused on loading and merging:

```text
input:  file/source/content
output: YamlMap
```

It should not grow a diagnostic listener. That would mix tolerant loading with user-facing validation and would make production context construction more complicated.

If merged-map behavior is inaccurate or surprising, fix the documentation or behavior in a dedicated CL after the validation surface is clearer.

<a name="proposed-application"></a>
### Application Remains Separate

`AnalysisOptionsImpl.fromYaml` should remain the low-level application step:

```text
input:  merged YamlMap
output: AnalysisOptionsImpl
```

It should not call `AnalysisOptionsValidator`. The combined parser can call provider/application and validator, then later hide a single include walk behind the same result type.

This separation lets clients choose whether they are computing runtime behavior, reporting diagnostics, or both.

<a name="proposed-testing"></a>
### Testing Through One Surface

Analysis-options diagnostic tests should use one shared helper, for example:

```text
AnalysisOptionsImpl parseAnalysisOptionsFilesWithDiagnostics(
  Map<File, String> codeByFile, {
  VersionConstraint? sdkVersionConstraint,
});
```

That helper should:

1. strip inline diagnostic expectation markers,
2. write all marker-free files,
3. construct the same `SourceFactory` shape used by current tests,
4. call the single parse entry point,
5. regenerate inline expectations from actual diagnostics,
6. diff regenerated content against expected content.

The physical tests can remain split by feature:

- include diagnostics,
- analyzer section diagnostics,
- formatter diagnostics,
- code-style diagnostics,
- linter rule diagnostics,
- plugin diagnostics.

But all diagnostic tests should enter through the same helper.

Provider merge tests and `AnalysisOptionsImpl.fromYaml` tests should stay separate only when they intentionally test lower-level behavior without diagnostics.

<a name="proposed-naming"></a>
### Naming

The suggested names are:

- `AnalysisOptionsParseSession`: top-level file-based entry point for effective options plus diagnostics.
- `AnalysisOptionsParseResult`: result containing the effective `AnalysisOptionsImpl` and diagnostics.
- `AnalysisOptionsValidator`: top-level diagnostic entry point.
- `_AnalysisOptionsValidatorWalker` or private methods inside `AnalysisOptionsValidator`: include traversal implementation, if useful.
- `_OptionsFileValidator`: composite validator for one `YamlMap`, if direct external use is removed.
- `_AnalyzerOptionsValidator`: composite validator for `analyzer:`.
- `_LinterRuleOptionsValidator`: private lint-rule semantic validator.

The component validators are now private implementation details where current callers allow it.

<a name="proposed-api-shape"></a>
## Proposed API Shape

<a name="api-parse-inputs"></a>
### Parse Inputs

The parser needs the inputs required for parsing the initial file, resolving includes, producing diagnostics with the correct source ownership, building effective options, and sharing cache state across one parse run:

```text
final class AnalysisOptionsParseSession {
  AnalysisOptionsParseResult parse({
    required SourceFactory sourceFactory,
    required Folder contextRoot,
    required File file,
    VersionConstraint? sdkVersionConstraint,
  });
}
```

Input meanings:

- `sourceFactory`: resolves `include` URIs, including `package:` includes.
- `contextRoot`: used in diagnostics such as `includeFileNotFound` and in plugin-location validation.
- `file`: the initial options file to parse and use as the include base.
- `sdkVersionConstraint`: used by lint-rule lifecycle checks.

The session owns the caches. A caller that parses several options files as part of the same atomic task should reuse the same `AnalysisOptionsParseSession`; a one-shot caller can create a new session at the call site.

<a name="api-validation-methods"></a>
### Parse Method

The production-oriented method should parse a file:

```text
AnalysisOptionsParseResult parse({
  required SourceFactory sourceFactory,
  required Folder contextRoot,
  required File file,
  VersionConstraint? sdkVersionConstraint,
});
```

This method should read the file contents through the file/source path that matches existing behavior.

Tests that use inline expectations write the marker-free content to the initial file before parsing, so a separate content-based parse method is not necessary. This keeps the visible interface narrow and makes every caller use the same file-based path:

- use `file` as the source identity and base URI,
- read the initial file's content from `file`,
- resolve included files from the file/source identity,
- read included file contents normally.

<a name="api-result-type"></a>
### Result Type

Return a result containing the initial file view, runtime options, and diagnostics:

```text
final class AnalysisOptionsParseResult {
  final File file;
  final AnalysisOptionsFileContent? content;
  final AnalysisOptionsImpl analysisOptions;
  final List<Diagnostic> diagnostics;
}

final class AnalysisOptionsFileContent {
  final String text;
  final LineInfo lineInfo;
  final YamlMap? yamlMap;
}
```

Here `content` is `null` only when the initial file cannot be read. `content.yamlMap` is the parsed, unmerged YAML map from the initial file, and may be `null` when the file is readable but not a YAML map. It is distinct from `analysisOptions`, which is the effective merged analyzer configuration.

This also gives room for future metadata such as:

- parsed initial options,
- included file graph,
- files read,
- whether parsing was incomplete due to parse failure.

The first implementation can still delegate to the private merged-YAML builder and `AnalysisOptionsValidator` internally. The result type is the contract that lets callers and tests move before the internals are unified.

<a name="api-test-helper"></a>
### Test Helper Shape

The test helper should live close to existing analysis-options diagnostic test support. It should hide:

- marker stripping,
- file writes,
- source factory construction,
- parser construction,
- diagnostic-to-marker regeneration.

One possible shape:

```text
mixin AnalysisOptionsValidationTestSupport
    on ResourceProviderMixin, LintRegistrationMixin {
  late SourceFactory sourceFactory;

  File get analysisOptionsFile => getFile('/analysis_options.yaml');

  Future<void> assertAnalysisOptionsDiagnostics(
    String code, {
    VersionConstraint? sdkVersionConstraint,
  }) async {
    await assertAnalysisOptionsDiagnosticsInFiles({
      analysisOptionsFile: code,
    }, sdkVersionConstraint: sdkVersionConstraint);
  }

  Future<void> assertAnalysisOptionsDiagnosticsInFiles(
    Map<File, String> codeByFile, {
    File? initialFile,
    VersionConstraint? sdkVersionConstraint,
  }) async {
    ...
  }
}
```

The current `AnalysisOptionsDiagnosticExpectationMixin` can either be renamed or kept as the low-level expectation comparison helper.

<a name="migration-plan"></a>
## Migration Plan

The migration should be intentionally boring. Most CLs should change either tests or implementation, not both. When both must change, the implementation change should be a pure wrapper or mechanical relocation with unchanged expectations.

The stage descriptions below are intentionally kept even after individual stages are completed. Reviewers can use them as the safety story for earlier CLs, while the Ultimate Goal section above describes the destination that later CLs are still moving toward.

<a name="stage-0"></a>
### Stage 0: Document The Current Model

Type: documentation only.

Create this document.

Purpose:

- establish shared terminology before code movement,
- make clear that multiple internal validators are acceptable,
- define the target as one validation entry surface,
- give reviewers a staged plan.

Expected behavior change:

- none.

Review safety story:

- documentation only.

Possible CL title:

```text
Document analysis options validation refactoring plan
```

<a name="stage-1"></a>
### Stage 1: Tests Only - Introduce One Shared Test Harness

Type: tests only.

Add a shared helper for analysis-options diagnostic tests. Initially, this helper should delegate to the existing `AnalysisOptionsAnalyzer.walkIncludes`.

The helper should be capable of replacing the existing direct calls from:

- `test/src/diagnostics/analysis_options/analysis_options_test_support.dart`
- `test/src/options/options_file_validator_test.dart`
- `test/src/options/options_rule_validator_test.dart`

But this stage should add the helper without migrating many tests.

Detailed changes:

1. Add a helper method such as `assertAnalysisOptionsDiagnosticsInFiles`.
2. Keep the existing inline expectation comparison code.
3. Keep existing `AbstractAnalysisOptionsTest` methods as forwarding wrappers.
4. Add one or two small tests that use the new helper directly.
5. Do not change production code.

The helper should accept:

- a map from `File` to marked source text,
- an optional initial file,
- an optional SDK version constraint,
- optional package dependencies if needed by the existing test support.

Expected behavior change:

- none.

Review safety story:

- The helper calls the same current implementation.
- Existing tests still pass through their old helpers.
- New helper behavior is demonstrated by a small number of tests.

Possible CL title:

```text
Add shared analysis options diagnostic test harness
```

Rollback plan:

- Delete the new helper and the small tests using it.

<a name="stage-2"></a>
### Stage 2: Tests Only - Move OptionsFileValidator Tests To The Harness

Type: tests only.

Migrate diagnostic tests in `options_file_validator_test.dart` from direct `OptionsFileValidator.validate` calls to the shared helper.

This stage exercises the full validation path for section-level diagnostics. It is the first proof that general options-file diagnostics can be tested without directly instantiating `OptionsFileValidator`.

Detailed changes:

1. Replace helper methods named like `validate(...)` so that they call the shared analysis-options diagnostic helper.
2. Preserve existing inline expectations.
3. Preserve test names.
4. Preserve test file organization.
5. Adjust setup only where direct validator construction is no longer needed.
6. Keep any tests that truly require direct validator access temporarily, but mark them with a TODO explaining why.

Important review detail:

- If expected diagnostic locations or messages change, stop and investigate. This stage should not intentionally change expectations.

Expected behavior change:

- none.

Review safety story:

- No production code changes.
- Expected diagnostics are unchanged.
- Tests now cover more realistic include/source behavior because they enter through the top-level path.

Possible CL title:

```text
Run options file validator tests through analysis options harness
```

Rollback plan:

- Restore the old `validate(...)` helper body.

<a name="stage-3"></a>
### Stage 3: Tests Only - Move LinterRuleOptionsValidator Tests To The Harness

Type: tests only.

Migrate diagnostic tests in `options_rule_validator_test.dart` from direct `LinterRuleOptionsValidator.validate` calls to the shared helper.

This stage is more sensitive than Stage 2 because lint-rule validation has cross-file include behavior and SDK-version-dependent lifecycle checks.

Detailed changes:

1. Replace `assertDiagnostics` and `assertRuleDiagnosticsInFiles` helpers so they call the shared analysis-options diagnostic helper.
2. Preserve lint rule registration setup.
3. Preserve package dependency setup for `package:` include tests.
4. Preserve SDK version parameters.
5. Preserve all inline diagnostic expectations.
6. Keep test files physically organized by included-file, rule, and value cases if that remains readable.

If direct validator tests reveal expectations that differ from the full path, handle them deliberately:

- If the full path reports additional diagnostics that users really see, update tests in this stage and call it out in the CL description.
- If the additional diagnostics are noise caused by test setup, adjust setup to preserve existing behavior.
- If a lower-level behavior is intentionally different from full validation, keep a small direct unit test and document why.

Expected behavior change:

- none intended.

Review safety story:

- No production code changes.
- Lint-rule diagnostics are now verified through the user-visible path.
- Inline expectations make any source range or message drift obvious.

Possible CL title:

```text
Run linter options rule tests through analysis options harness
```

Rollback plan:

- Restore the old mixin methods that construct `LinterRuleOptionsValidator`.

<a name="stage-4"></a>
### Stage 4: Tests Only - Normalize Include Diagnostic Tests

Type: tests only.

The diagnostics tests under `test/src/diagnostics/analysis_options` already use `AnalysisOptionsAnalyzer`. This stage should make them use the same shared helper as the `test/src/options` diagnostics tests.

Detailed changes:

1. Update `AbstractAnalysisOptionsTest` to delegate to the shared helper.
2. Remove duplicate expectation-comparison code if it has moved.
3. Keep existing include tests in their current files unless there is an obvious low-risk consolidation.
4. Ensure tests still cover:
   - missing package include,
   - missing relative include,
   - self include,
   - include cycles,
   - diagnostics in included files wrapped as `includedFileWarning`,
   - multiple includes,
   - quoted and unquoted include values.

Expected behavior change:

- none.

Review safety story:

- No production code changes.
- Existing tests still exercise the same implementation.
- All analysis-options diagnostics now share one test surface.

Possible CL title:

```text
Share analysis options diagnostic harness across include tests
```

Rollback plan:

- Restore `AbstractAnalysisOptionsTest` to call `AnalysisOptionsAnalyzer` directly.

<a name="stage-5"></a>
### Stage 5: Implementation Only - Add AnalysisOptionsValidator As A Wrapper

Type: implementation only, with minimal tests if required by analyzer test coverage policy.

Add the new top-level validation class. Initially, it should be a thin wrapper around `AnalysisOptionsAnalyzer`.

Possible location:

```text
pkg/analyzer/lib/src/analysis_options/analysis_options_validator.dart
```

Possible implementation sketch:

```text
final class AnalysisOptionsValidator {
  final SourceFactory sourceFactory;
  final Folder contextRoot;
  final VersionConstraint? sdkVersionConstraint;
  final AnalysisOptionsValidationCache _validationCache;

  AnalysisOptionsValidator({
    required this.sourceFactory,
    required this.contextRoot,
    this.sdkVersionConstraint,
    required AnalysisOptionsValidationCache validationCache,
  }) : _validationCache = validationCache;

  List<Diagnostic> validate({required File file, required String content}) {
    return AnalysisOptionsAnalyzer(
      initialSource: FileSource(file),
      sourceFactory: sourceFactory,
      contextRoot: contextRoot,
      sdkVersionConstraint: sdkVersionConstraint,
      validationCache: _validationCache,
    ).walkIncludes(content: content);
  }
}
```

This stage should not move existing implementation logic. It should not rename `AnalysisOptionsAnalyzer`. It should not change tests to use the new class yet, except perhaps one narrow wrapper test.

Expected behavior change:

- none for existing callers.

Review safety story:

- New wrapper delegates to existing implementation.
- Existing tests keep exercising the old path.
- The CL creates the future API without moving behavior.

Possible CL title:

```text
Add AnalysisOptionsValidator wrapper entry point
```

Rollback plan:

- Delete the new file/class.

<a name="stage-6"></a>
### Stage 6: Tests Only - Switch The Harness To AnalysisOptionsValidator

Type: tests only.

Change the shared test harness from Stage 1 to construct and call `AnalysisOptionsValidator` instead of `AnalysisOptionsAnalyzer`.

Because Stages 2 through 4 moved diagnostic tests behind the shared helper, this should be a small change with broad coverage.

Detailed changes:

1. Update the helper's import.
2. Replace construction of `AnalysisOptionsAnalyzer` with `AnalysisOptionsValidator`.
3. Write marker-free content to the initial file and call `validate`.
4. Preserve all inline expectations.

Expected behavior change:

- none.

Review safety story:

- Production implementation is unchanged from Stage 5.
- The wrapper is now covered by the full analysis-options diagnostic suite.
- Any wrapper mismatch appears as inline expectation failures.

Possible CL title:

```text
Test analysis options diagnostics through AnalysisOptionsValidator
```

Rollback plan:

- Change the helper back to `AnalysisOptionsAnalyzer`.

<a name="stage-7"></a>
### Stage 7: Implementation Only - Move Include Walking Behind The New Class

Type: implementation only.

Move the include-walking implementation from `AnalysisOptionsAnalyzer` into `AnalysisOptionsValidator`, or into a private helper owned by `analysis_options_validator.dart`.

This is the first structural implementation refactor. It should preserve the same public wrapper methods introduced in Stage 5.

Detailed changes:

1. Copy or move the state currently in `AnalysisOptionsAnalyzer`:
   - initial diagnostic listener/reporter,
   - current diagnostic listener/reporter,
   - source factory,
   - context root,
   - SDK version constraint,
   - resource provider,
   - initial include span,
   - provider,
   - first plugin name,
   - include chain,
   - analysis options cache.
2. Preserve the validation algorithm.
3. Preserve `_IncludedDiagnosticListener` behavior.
4. Keep `AnalysisOptionsAnalyzer` temporarily as a compatibility shim, if needed:

```text @Deprecated('Use AnalysisOptionsValidator') class AnalysisOptionsAnalyzer {
     ...
} ```

Or keep it package-private until all internal callers move.
5. Do not change expected diagnostics.

Expected behavior change:

- none.

Review safety story:

- The test suite already enters through `AnalysisOptionsValidator`.
- This is a move/rename of code that is already covered by full-path tests.
- Inline expectations should remain unchanged.

Possible CL title:

```text
Move analysis options include validation into AnalysisOptionsValidator
```

Rollback plan:

- Restore wrapper delegation to `AnalysisOptionsAnalyzer`.

<a name="stage-8"></a>
### Stage 8: Implementation Only - Rename Or Retire AnalysisOptionsAnalyzer

Type: implementation only.

Remove the old `AnalysisOptionsAnalyzer` name if no callers remain. If removing it in one CL is too large, first make it private or deprecated, then delete it in a follow-up CL.

Detailed changes:

1. Search for remaining references to `AnalysisOptionsAnalyzer`.
2. Replace them with `AnalysisOptionsValidator`.
3. Delete the old class or convert it to a private implementation detail.
4. Move `_IncludedDiagnosticListener` near the new validation implementation.
5. Keep `OptionsFileValidator` in place as the internal composite validator.

Expected behavior change:

- none.

Review safety story:

- The class being removed has already been replaced by a wrapper and then by migrated tests.
- All diagnostics tests use the new entry point.

Possible CL title:

```text
Remove old AnalysisOptionsAnalyzer validation entry point
```

Rollback plan:

- Reintroduce the shim class delegating to `AnalysisOptionsValidator`.

<a name="stage-9"></a>
### Stage 9: Tests Only - Remove Redundant Direct Validator Tests

Type: tests only.

After tests enter through `AnalysisOptionsValidator`, audit any remaining direct tests of internal validators.

Keep direct tests only when they satisfy one of these conditions:

- They test a pure helper behavior that is intentionally independent from file validation.
- They are much smaller and clearer than the equivalent full-path test.
- They cover an internal invariant that should fail close to the component rather than through a broad integration test.

Remove or convert direct tests that merely duplicate full-path diagnostics.

Detailed changes:

1. Audit direct instantiations of `OptionsFileValidator`.
2. Audit direct instantiations of `LinterRuleOptionsValidator`.
3. Delete redundant test helpers.
4. Preserve test coverage for every diagnostic code currently covered.
5. Consider splitting large files by feature if readability suffers.

Expected behavior change:

- none.

Review safety story:

- No production code changes.
- Removed tests are redundant with full-path tests.
- The CL description should list which old direct test groups are now covered through the shared validation helper.

Possible CL title:

```text
Remove redundant direct analysis options validator tests
```

Rollback plan:

- Restore deleted direct tests.

<a name="stage-10"></a>
### Stage 10: Implementation Only - Narrow Internal Visibility

Type: implementation only.

Once tests no longer instantiate internal validators, narrow the implementation surface.

Possible changes:

- Rename `OptionsFileValidator` to `_OptionsFileValidator` if it has no package-external callers.
- Keep `OptionsValidator` package-visible only if it remains useful across files.
- Move or privatize section validators.
- Move `LinterRuleOptionsValidator` closer to the options validation implementation, or make it private if there are no legitimate external callers.

This stage may need to be split into multiple CLs if visibility changes touch many imports.

Expected behavior change:

- none.

Review safety story:

- Tests have already stopped depending on these internals.
- Public behavior is covered through `AnalysisOptionsValidator`.
- This CL makes code visibility match actual ownership.

Possible CL title:

```text
Hide analysis options component validators
```

Rollback plan:

- Restore class names/visibility without changing behavior.

<a name="stage-11"></a>
### Stage 11: Implementation Only - Clarify Provider Documentation

Type: implementation only, documentation/comments, possibly tests if behavior is corrected.

Clarify `AnalysisOptionsProvider` documentation around include handling.

There are two possible directions:

1. Update the comment to match current behavior:

   - includes are used to load and merge included options,
   - the returned map may still contain the including file's `include` key,
   - consumers should ignore `include` unless they intentionally need it.

2. Change provider behavior to remove `include` from returned maps, if that is the intended contract.

Direction 1 is safer and should be preferred unless there is a strong reason to change behavior.

Expected behavior change:

- none if documentation only.

Review safety story:

- This is separated from validation refactoring.
- It resolves a source of confusion without touching diagnostics.

Possible CL title:

```text
Clarify AnalysisOptionsProvider include merge documentation
```

Rollback plan:

- Restore old comments.

<a name="stage-12"></a>
### Stage 12: Optional Implementation - Enrich The Parse Result

Type: implementation, optional.

After the entry point is stable, consider adding metadata to the structured parse result:

```text
final class AnalysisOptionsParseResult {
  final File file;
  final AnalysisOptionsFileContent? content;
  final AnalysisOptionsImpl analysisOptions;
  final List<Diagnostic> diagnostics;
  // Future metadata, if useful.
}
```

This could later expose metadata useful for tooling or tests:

- included files visited,
- files with parse failures,
- whether validation stopped early,
- the initial parsed `YamlMap`,
- the include graph.

Extra metadata should not be part of the first parser CL because it increases API surface before there is a demonstrated need.

Expected behavior change:

- none if `diagnostics` remains identical.

Review safety story:

- Mechanical result-type enrichment after behavior is stable.
- Existing tests can compare the same diagnostics.

Possible CL title:

```text
Enrich analysis options parse result metadata
```

Rollback plan:

- Return `List<Diagnostic>` directly again.

<a name="review-strategy"></a>
## Review Strategy

Each CL should have one clear claim.

Test-only CLs should say:

```text
This CL changes only how tests reach existing diagnostics. Expected diagnostics
are unchanged.
```

Implementation-only wrapper CLs should say:

```text
This CL introduces a new entry point that delegates to the existing
implementation. Existing callers and tests are unchanged.
```

Implementation move/rename CLs should say:

```text
Tests were already migrated to the new entry point in earlier CLs. This CL
moves the implementation behind that entry point without changing expected
diagnostics.
```

If any CL changes expected diagnostics, it should be deliberately separated and described as a behavior fix, not hidden inside the refactoring.

Useful checks for each stage:

- Run the targeted analysis-options tests.
- Prefer running the whole relevant `test_all.dart` in a directory when that is faster than several individual files.
- Inspect diffs for generated inline diagnostic markers.
- Avoid whole-repository `git status` on the mounted checkout.

<a name="suggested-cl-boundaries"></a>
## Suggested CL Boundaries

The exact staging can change, but this CL sequence keeps review risk low. It starts with Stage 0 as the first CL, so the item numbers are not the same as the stage numbers.

1. Documentation only: add this plan.
2. Tests only: add shared diagnostic harness.
3. Tests only: migrate `options_file_validator_test.dart`.
4. Tests only: migrate `options_rule_validator_test.dart`.
5. Tests only: normalize `test/src/diagnostics/analysis_options` harness use.
6. Implementation only: add `AnalysisOptionsValidator` wrapper.
7. Tests only: switch shared harness to `AnalysisOptionsValidator`.
8. Implementation only: move include walking into `AnalysisOptionsValidator`.
9. Implementation only: retire `AnalysisOptionsAnalyzer`.
10. Tests only: remove redundant direct validator tests.
11. Implementation only: narrow validator visibility.
12. Implementation only: clarify provider include documentation.
13. Optional implementation: add a structured validation result.

It is acceptable to combine adjacent stages if a CL remains small and easy to review. In particular:

- Stages 1 and 4 might combine if the helper is already shared cleanly.
- Stages 5 and 6 can combine only if the implementation is a pure wrapper and the test diff is small.
- Stages 7 and 8 should probably remain separate if the move is non-trivial.

After the validation entry point and visibility work are in place, a test organization CL can move the analyzer analysis-options tests into `test/src/analysis_options` without changing behavior.

<a name="open-questions"></a>
## Open Questions

### Should `AnalysisOptionsParseSession` Be Public API?

The first version should probably live under `lib/src`. It can be promoted only after there is evidence that external clients need this combined parse entry point.

### Should A Content Parse Method Exist?

Tests can write marker-free content to files and call `parse`, so a content method is not strictly necessary. Keeping only the file-based method makes the source identity, include base, overlay behavior, and read path the same in tests and production.

It does not need to be added unless production callers need content-based parsing.

### Should Component Validators Become Private?

Yes. The current direction is to keep component validators private behind `AnalysisOptionsParseSession` and `AnalysisOptionsValidator`, with direct tests only for behavior that is intentionally independent from full file parsing.

### Should Diagnostic Tests Live In One File?

Not necessarily. The better target is one test home and one diagnostic test surface:

```text
test/src/analysis_options/* -> shared helper -> AnalysisOptionsParseSession
```

Files can remain grouped by production path: one build/effective-options file, one validation file, and separate support code when needed. The helper should use `AnalysisOptionsParseSession` for full-file scenarios that check both diagnostics and effective options.

### Should Merged YAML Remove `include` From Merged Maps?

Older provider documentation said includes are removed, but current behavior can leave them. Changing this could affect consumers, especially code that intentionally looks at include nodes.

Prefer documenting current behavior first. If removal is desired, do it as a separate behavior CL with focused tests.

### Should Lint Cross-File Rule Checks Use The Include Walker's Parsed Maps?

Today `_MergedOptionsYamlBuilder` and `_AnalysisOptionsValidatorWalker` both walk includes and parse included files for different reasons. That can duplicate work.

Long term, the validator could pass already parsed included options to the lint rule validator. This is not necessary for the entry-point refactoring and would make the initial migration riskier. Keep it as a possible later optimization.

### Should Parsing Produce Effective Options And Diagnostics Together?

Yes. The combined parser should return the effective `AnalysisOptionsImpl` and diagnostics for the same initial file. The first implementation may compose the existing provider/application and validator paths internally, but callers should be able to depend on one file-based operation.
