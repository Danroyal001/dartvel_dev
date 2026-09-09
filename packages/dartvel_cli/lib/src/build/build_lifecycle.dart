/// Advances `DV.lifecycle.build` while `dartvel build` runs.
///
/// The signal, its enum and its setter all existed and the build never touched
/// one of them: `setBuild` was called by nothing but its own test. So an
/// application, Studio, or an external tool observing the build pipeline saw
/// `idle` for the whole of it and could not tell a build that was generating
/// from one that had failed from one that was never started — the specification
/// says those four observers share one canonical state, and they shared a
/// value that never moved.
///
/// A wrapper rather than a `setBuild` before each phase, because the failure
/// path is the half that gets forgotten. A build that dies while compiling has
/// to leave `failed` behind; leaving `compiling` reads as a build still
/// running, and a stuck pipeline and a crashed one look the same from outside.
library dartvel_cli.build.build_lifecycle;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart';

/// The build's stages, reported as they run.
class DVBuildStages {
  /// Reports into the process-wide registry by default, which is the one
  /// `DV.lifecycle` returns. A registry can be passed in for a test that wants
  /// its own.
  DVBuildStages({DVLifecycleRegistry? registry})
      : _registry = registry ?? dvLifecycle;

  final DVLifecycleRegistry _registry;

  /// Runs [body] as [stage], and reports `failed` if it throws.
  ///
  /// The exception is rethrown: this reports what happened, it does not decide
  /// what to do about it.
  Future<T> run<T>(DVBuildLifecycle stage, Future<T> Function() body) async {
    _registry.setBuild(stage);
    try {
      return await body();
    } on Object {
      _registry.setBuild(DVBuildLifecycle.failed);
      rethrow;
    }
  }

  /// The build finished and produced its artifact.
  void completed() => _registry.setBuild(DVBuildLifecycle.completed);

  /// The build stopped for a reason the pipeline caught itself — a refused
  /// capture, a validation failure — rather than an exception that unwound it.
  /// As failed as one that threw, and reported the same way.
  void failed() => _registry.setBuild(DVBuildLifecycle.failed);
}
