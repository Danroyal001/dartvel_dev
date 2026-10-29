/// The rows of the proposal's Part 2 table, as data.
///
/// `docs/proposals/2026-10-29-dart-flutter-rust-stack.md` measured these by
/// hand; this list is what lets the next measurement count the same things.
/// Paths are relative to each upstream checkout.
library;

import 'line_count.dart';

/// The upstream repositories, keyed as [Component.checkout] names them.
const checkouts = {
  'sdk': 'https://github.com/dart-lang/sdk',
  'flutter': 'https://github.com/flutter/flutter',
  'pub': 'https://github.com/dart-lang/pub',
  'dart_style': 'https://github.com/dart-lang/dart_style',
};

/// The commits Part 2 was measured at.
const proposalPins = {'sdk': 'ceea75dd2b82', 'flutter': 'c3f5b027df2b'};

const _engine = 'engine/src/flutter';
const _native = {Language.cpp, Language.objc};

const part2Components = <Component>[
  // Ported.
  Component(name: 'Dart VM', roots: ['runtime/vm'], languages: {Language.cpp}),
  Component(
    name: 'VM compiler back ends',
    roots: ['runtime/vm/compiler'],
    languages: {Language.cpp},
    partOf: 'Dart VM',
  ),
  Component(
    name: 'dart:io embedder and natives',
    roots: ['runtime/bin', 'runtime/lib', 'runtime/platform'],
    languages: {Language.cpp},
  ),
  Component(name: 'Compiler front end', roots: ['pkg/front_end']),
  Component(name: 'Kernel and VM transforms', roots: ['pkg/kernel', 'pkg/vm']),
  Component(name: 'Shared front-end layer', roots: ['pkg/_fe_analyzer_shared']),
  Component(name: 'frontend_server', roots: ['pkg/frontend_server']),
  Component(name: 'Analyzer', roots: ['pkg/analyzer']),
  Component(name: 'Analysis server', roots: ['pkg/analysis_server']),
  Component(name: 'Linter', roots: ['pkg/linter']),
  Component(name: 'Formatter', checkout: 'dart_style', roots: ['.']),
  Component(name: 'dart2js', roots: ['pkg/compiler']),
  Component(name: 'dart2wasm', roots: ['pkg/dart2wasm']),
  Component(name: 'DDC', roots: ['pkg/dev_compiler']),
  Component(
    name: 'dart CLI, DDS and vm_service',
    roots: ['pkg/dartdev', 'pkg/dds', 'pkg/vm_service'],
  ),
  Component(name: 'pub', checkout: 'pub', roots: ['.']),
  Component(
    name: 'Flutter engine',
    checkout: 'flutter',
    roots: [
      '$_engine/fml',
      '$_engine/runtime',
      '$_engine/shell',
      '$_engine/lib/ui',
      '$_engine/flow',
      '$_engine/display_list',
      '$_engine/impeller',
      '$_engine/txt',
      '$_engine/vulkan',
      '$_engine/skwasm',
      '$_engine/third_party/tonic',
      '$_engine/third_party/accessibility',
    ],
    languages: _native,
  ),
  Component(
    name: 'flutter CLI',
    checkout: 'flutter',
    roots: ['packages/flutter_tools'],
    // Its templates carry the C++ and Objective-C of a new app's runner,
    // which is generated for the app, not ported with the tool.
    languages: {Language.dart},
  ),
  // Kept as API surface.
  Component(
    name: 'dart:* library sources',
    roots: ['sdk/lib'],
    languages: {Language.dart},
    ported: false,
  ),
  Component(
    name: 'Flutter framework',
    checkout: 'flutter',
    roots: ['packages/flutter'],
    languages: {Language.dart},
    ported: false,
  ),
  Component(
    name: 'Flutter web engine',
    checkout: 'flutter',
    roots: ['$_engine/lib/web_ui'],
    languages: {Language.dart},
    ported: false,
  ),
];
