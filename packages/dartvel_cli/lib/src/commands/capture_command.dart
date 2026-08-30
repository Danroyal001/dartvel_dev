import 'dart:io';

import 'package:args/command_runner.dart';

import '../build/capture_verification.dart';
import '../utils/logger.dart';
import 'firefox_capture_command.dart';
import 'pty_capture_command.dart';

/// `dartvel capture verify` — proving a runtime-verification screenshot shows
/// the application.
///
/// The jobs used to end at `test -s capture.png`. Every capture tool in them
/// writes a full-size image whether or not the application drew, so a crash
/// before the first frame produced a blank screen that passed.
class CaptureCommand extends Command<void> {
  @override
  final String name = 'capture';

  @override
  final String description =
      'Capture what a target rendered, and check that it rendered anything.';

  CaptureCommand() {
    addSubcommand(_VerifyCaptureCommand());
    addSubcommand(PtyCaptureCommand());
    addSubcommand(FirefoxCaptureCommand());
  }
}

class _VerifyCaptureCommand extends Command<void> {
  @override
  final String name = 'verify';

  @override
  final String description =
      'Fail unless the capture is a PNG showing something rendered.';

  @override
  String get invocation => 'dartvel capture verify <file.png> [--min-width N]';

  _VerifyCaptureCommand() {
    argParser
      ..addOption('min-width',
          help: 'Reject a capture narrower than this.', defaultsTo: '1')
      ..addOption('min-height',
          help: 'Reject a capture shorter than this.', defaultsTo: '1')
      ..addOption('max-dominant',
          help: 'Share of one colour above which the capture is called blank.',
          defaultsTo: '0.99')
      ..addOption('expect-colour',
          aliases: <String>['expect-color'],
          help: 'An "r,g,b" the capture must contain.')
      ..addOption('label',
          help: 'What is being verified, for the failure message.',
          defaultsTo: 'the capture');
  }

  @override
  void run() {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('Give the capture to verify.', invocation);
    }
    final label = argResults!['label'] as String;
    final file = File(rest.first);
    if (!file.existsSync()) {
      Logger.error('::error::$label produced no capture at ${rest.first}; '
          'the run step failed.');
      exit(1);
    }

    List<int>? expected;
    final raw = argResults!['expect-colour'] as String?;
    if (raw != null && raw.isNotEmpty) {
      final parts = raw.split(',').map((String p) => int.tryParse(p.trim()));
      if (parts.length != 3 || parts.any((int? p) => p == null)) {
        throw UsageException('--expect-colour takes "r,g,b".', invocation);
      }
      expected = parts.map((int? p) => p!).toList();
    }

    final verdict = verifyCapture(
      file.readAsBytesSync(),
      minWidth: int.parse(argResults!['min-width'] as String),
      minHeight: int.parse(argResults!['min-height'] as String),
      maxDominantFraction: double.parse(argResults!['max-dominant'] as String),
      expectColour: expected,
    );

    Logger.log('$label: ${verdict.width}x${verdict.height}, '
        '${verdict.distinctColours} colours, '
        'dominant ${(verdict.dominantFraction * 100).toStringAsFixed(2)}%');

    if (!verdict.ok) {
      for (final reason in verdict.reasons) {
        Logger.error('::error::$label: $reason');
      }
      exit(1);
    }
    Logger.log('$label shows a rendered application.');
  }
}
