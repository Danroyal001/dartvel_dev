/// What a foreign error becomes when it crosses a binding.
///
/// Every call a generated module carries across a foreign boundary -- FFI,
/// JNI, the browser, WebAssembly or Node -- runs through [dvBindingCall],
/// [dvBindingFuture] or [dvBindingStream], so whatever the foreign side
/// throws reaches the application as a [DVBindingError] naming the module,
/// the operation and the binding kind, with the original error and its stack
/// trace kept. An error that crosses a boundary and loses its origin is one a
/// developer debugs twice.
library;

import 'dart:async';

import 'module_outcome.dart' show DVModuleUnavailable;
import 'module_rpc.dart' show DVModuleRpcRefused;

/// A foreign error, with where it crossed.
class DVBindingError implements Exception {
  const DVBindingError(
    this.module,
    this.operation,
    this.binding,
    this.error, [
    this.stackTrace,
  ]);

  /// The module id: what the application calls `DV.Modules.<id>`.
  final String module;

  /// The operation that was called.
  final String operation;

  /// The binding kind the call crossed: `DVFfiBinding`, `DVJniBinding`,
  /// `DVWebBinding`, `DVWasmBinding` or `DVNodeJsBinding`.
  final String binding;

  /// What the foreign side threw, unchanged.
  final Object error;

  /// Where it was thrown, when the foreign side said.
  final StackTrace? stackTrace;

  @override
  String toString() =>
      'DVBindingError: $module.$operation failed across $binding: $error';
}

/// Dartvel's own exceptions already say where they came from.
bool _passesThrough(Object error) =>
    error is DVBindingError ||
    error is DVModuleUnavailable ||
    error is DVModuleRpcRefused;

Object _convert(String module, String operation, String binding,
        Object error, StackTrace? stackTrace) =>
    _passesThrough(error)
        ? error
        : DVBindingError(module, operation, binding, error, stackTrace);

/// Runs a synchronous foreign call.
T dvBindingCall<T>(
    String module, String operation, String binding, T Function() call) {
  try {
    return call();
  } catch (error, stackTrace) {
    if (_passesThrough(error)) rethrow;
    Error.throwWithStackTrace(
        DVBindingError(module, operation, binding, error, stackTrace),
        stackTrace);
  }
}

/// Runs a foreign call that answers once.
Future<T> dvBindingFuture<T>(String module, String operation, String binding,
    Future<T> Function() call) async {
  try {
    return await call();
  } catch (error, stackTrace) {
    if (_passesThrough(error)) rethrow;
    Error.throwWithStackTrace(
        DVBindingError(module, operation, binding, error, stackTrace),
        stackTrace);
  }
}

/// Runs a foreign call that answers more than once.
Stream<T> dvBindingStream<T>(String module, String operation, String binding,
    Stream<T> Function() call) {
  final Stream<T> source;
  try {
    source = call();
  } catch (error, stackTrace) {
    return Stream<T>.error(
        _convert(module, operation, binding, error, stackTrace), stackTrace);
  }
  return source.transform(StreamTransformer<T, T>.fromHandlers(
    handleError: (Object error, StackTrace stackTrace, EventSink<T> sink) =>
        sink.addError(
            _convert(module, operation, binding, error, stackTrace),
            stackTrace),
  ));
}
