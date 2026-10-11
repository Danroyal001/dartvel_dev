/// Reading a crash report with the symbols of the release that crashed.
///
/// A report from a release build arrives in the compiler's names: R8's
/// `a.a.a.b` for a Java frame, `_kDartIsolateSnapshotInstructions+0x11234`
/// for a Dart one. [DVRepositoryCrashSymbolicator] turns both back into
/// names a developer can act on, using the bundle `dartvel symbols upload`
/// stored for exactly that release -- and, because grouping is by name, it
/// recomputes the group id afterwards. A group id taken from obfuscated
/// names would be different in every release for the same bug, which is
/// what makes "this regressed in 1.4.0" unanswerable.
library;

import 'dart:convert';

import 'crash_report.dart';
import 'proguard_mapping.dart';
import 'symbols.dart';

/// Turns a report's frames back into the original names.
abstract class DVCrashSymbolicator {
  /// [report], read with its release's symbols. Never throws: a report that
  /// cannot be read is returned as it was, with [DVCrashReport.symbolicated]
  /// false when it needed symbols and had none.
  Future<DVCrashReport> symbolicate(DVCrashReport report);
}

/// Decodes a Dart stack trace printed by an AOT build made with
/// `--split-debug-info`.
///
/// An interface here because the implementation reads ELF and DWARF through
/// `dart:io` and a package that does not belong in a library that also runs in
/// a browser; `dartvel_shelf` supplies one for the server.
abstract class DVDartStackDecoder {
  /// The decoded stack for [stack], exactly as the VM printed it, using
  /// [symbolFiles] (the bytes of the matching `.symbols` files). Null when
  /// the stack cannot be decoded with them.
  Future<String?> decode(
    String stack, {
    required List<List<int>> symbolFiles,
  });
}

/// A symbolicator over a [DVSymbolRepository].
class DVRepositoryCrashSymbolicator implements DVCrashSymbolicator {
  DVRepositoryCrashSymbolicator({
    required this.repository,
    this.dartDecoder,
    this.parsedMappings = 4,
  });

  final DVSymbolRepository repository;
  final DVDartStackDecoder? dartDecoder;

  /// How many parsed mappings are kept. A release's mapping is tens of
  /// megabytes of text and every report from it needs the same one.
  final int parsedMappings;

  final Map<String, DVProguardMapping> _mappings = <String, DVProguardMapping>{};

  static const String _jvm = 'jvm:';
  static final RegExp _buildId = RegExp(r"build_id:\s*'([0-9a-fA-F]+)'");
  static final RegExp _nativeFrame = RegExp(r'^#\d+\s+abs\s+[0-9a-fA-F]+\s+virt\s');

  @override
  Future<DVCrashReport> symbolicate(DVCrashReport report) async {
    try {
      final bool hasJvm = report.frames
          .any((DVCrashFrame f) => (f.uri ?? '').startsWith(_jvm));
      if (hasJvm) return await _symbolicateJvm(report);
      if (_isObfuscatedNative(report)) return await _symbolicateDart(report);
      return report;
    } on Object {
      return report.copyWith(symbolicated: false);
    }
  }

  bool _isObfuscatedNative(DVCrashReport report) => report.frames.any(
      (DVCrashFrame f) =>
          f.uri == null &&
          (f.function.contains('isolate_dso_base') ||
              _nativeFrame.hasMatch(f.function)));

  Future<DVSymbolsManifest?> _manifest(String release) async {
    if (!dvSymbolReleaseOk(release)) return null;
    return repository.manifest(release);
  }

  Future<DVCrashReport> _symbolicateJvm(DVCrashReport report) async {
    final String release = report.context.release;
    final DVProguardMapping? mapping = await _mapping(release);
    if (mapping == null) return report.copyWith(symbolicated: false);

    final List<DVCrashFrame> frames = <DVCrashFrame>[];
    for (final DVCrashFrame frame in report.frames) {
      final String uri = frame.uri ?? '';
      if (!uri.startsWith(_jvm)) {
        frames.add(frame);
        continue;
      }
      for (final DVRetracedFrame original in mapping.retraceFrame(
          uri.substring(_jvm.length), frame.function, frame.line)) {
        frames.add(DVCrashFrame(
          function: original.methodName,
          uri: '$_jvm${original.className}',
          line: original.line,
        ));
      }
    }
    final String errorType = mapping.originalClass(report.errorType);
    return report.copyWith(
      frames: frames,
      errorType: errorType,
      fingerprint: DVCrashFingerprint.of(errorType: errorType, frames: frames),
      symbolicated: true,
    );
  }

  Future<DVProguardMapping?> _mapping(String release) async {
    final DVProguardMapping? cached = _mappings[release];
    if (cached != null) return cached;
    final DVSymbolsManifest? manifest = await _manifest(release);
    final DVSymbolFile? file = manifest?.firstOfKind(DVSymbolKind.r8Mapping);
    if (file == null) return null;
    final List<int>? bytes = await repository.readFile(release, file.name);
    if (bytes == null) return null;
    final DVProguardMapping mapping =
        DVProguardMapping.parse(utf8.decode(bytes));
    if (mapping.isEmpty) return null;
    if (_mappings.length >= parsedMappings) {
      _mappings.remove(_mappings.keys.first);
    }
    return _mappings[release] = mapping;
  }

  Future<DVCrashReport> _symbolicateDart(DVCrashReport report) async {
    final DVDartStackDecoder? decoder = dartDecoder;
    if (decoder == null) return report.copyWith(symbolicated: false);
    final DVSymbolsManifest? manifest = await _manifest(report.context.release);
    if (manifest == null) return report.copyWith(symbolicated: false);

    final String stack =
        report.frames.map((DVCrashFrame f) => f.function).join('\n');
    final String? buildId = _buildId.firstMatch(stack)?.group(1)?.toLowerCase();

    final List<DVSymbolFile> files =
        manifest.ofKind(DVSymbolKind.dartSymbols).toList();
    final bool anyIds = files.any((DVSymbolFile f) => f.buildId != null);
    final List<DVSymbolFile> candidates = <DVSymbolFile>[
      for (final DVSymbolFile file in files)
        // A bundle that recorded build ids is matched on them; one that did
        // not, or a stack that names none, offers every file and leaves the
        // decoder to refuse the wrong one.
        if (!anyIds || buildId == null || file.buildId?.toLowerCase() == buildId)
          file,
    ];
    if (candidates.isEmpty) return report.copyWith(symbolicated: false);

    final List<List<int>> bytes = <List<int>>[];
    for (final DVSymbolFile file in candidates) {
      final List<int>? content =
          await repository.readFile(report.context.release, file.name);
      if (content != null) bytes.add(content);
    }
    if (bytes.isEmpty) return report.copyWith(symbolicated: false);

    final String? decoded = await decoder.decode(stack, symbolFiles: bytes);
    if (decoded == null) return report.copyWith(symbolicated: false);
    // The decoder passes the header lines (pid, tid, base addresses) through
    // beside the frames it decoded. Those differ on every run, so a group id
    // taken from them would put each occurrence of one bug in a group of its
    // own; only the frames are kept.
    final List<DVCrashFrame> frames = DVCrashFrame.parse(decoded
        .split('\n')
        .where((String line) => line.trimLeft().startsWith('#'))
        .join('\n'));
    if (frames.isEmpty) return report.copyWith(symbolicated: false);
    return report.copyWith(
      frames: frames,
      fingerprint:
          DVCrashFingerprint.of(errorType: report.errorType, frames: frames),
      symbolicated: true,
    );
  }
}
