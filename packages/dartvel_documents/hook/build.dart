import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:dartvel_documents/src/pdfium_fetch.dart';
import 'package:dartvel_documents/src/pdfium_release.dart';
import 'package:hooks/hooks.dart';

/// Bundles PDFium for the target: the pinned archive, downloaded once into
/// `~/.dartvel/cache/pdfium/`, refused if its sha256 differs from the pin, and
/// handed to the toolchain as the `pdfium.dart` code asset, which ships inside
/// the app. A target PDFium has no build for gets no asset; opening a document
/// there answers with the reason.
Future<void> main(List<String> args) async {
  await build(args, (BuildInput input, BuildOutputBuilder output) async {
    if (!input.config.buildCodeAssets) return;
    final CodeConfig code = input.config.code;
    final bool simulator = code.targetOS == OS.iOS && code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
    final DVPdfiumArchive? archive = dvPdfiumArchiveFor(code.targetOS.name, code.targetArchitecture.name, simulator: simulator);
    if (archive == null) {
      stderr.writeln('dartvel_documents: PDFium has no build for ${code.targetOS.name}-${code.targetArchitecture.name}; '
          'documents will answer that they cannot open there.');
      return;
    }
    final File tgz = await dvFetchPdfium(archive, dvPdfiumCacheDirectory());
    final Directory extracted = Directory.fromUri(input.outputDirectory.resolve('pdfium/'));
    final File library = await dvExtract(tgz, archive.library, extracted);
    output.assets.code.add(CodeAsset(
      package: input.packageName,
      name: 'pdfium.dart',
      file: library.uri,
      linkMode: DynamicLoadingBundled(),
    ));
    output.dependencies.add(tgz.uri);
  });
}
