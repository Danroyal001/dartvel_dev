import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';

import 'documents.dart';
import 'pdfium_ffi.dart';

/// The PDFium backend: every target with `dart:ffi`.
final class _Pdfium {
  const _Pdfium._();

  static bool _initialised = false;

  /// Calls into PDFium are made one at a time: it is not thread-safe, and a
  /// render waits for the one before it.
  static Future<void> _queue = Future<void>.value();

  static Future<T> _serial<T>(T Function() call) {
    final Completer<T> done = Completer<T>();
    _queue = _queue.then((_) {
      try {
        done.complete(call());
      } on Object catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    return done.future;
  }

  static void _init() {
    if (_initialised) return;
    try {
      fpdfInitLibrary();
    } on ArgumentError catch (error) {
      // The asset is missing: a target PDFium has no build for, or an app
      // built without the hook.
      throw DVDocumentUnavailable('', 'PDFium is not in this app ($error).');
    }
    _initialised = true;
  }

  /// Opens [path]: a PDF directly, a presentation or office document by
  /// converting it to PDF with LibreOffice. Throws [DVDocumentUnavailable]
  /// with the reason when it cannot.
  static Future<DVDocument> open(String path) async {
    if (!File(path).existsSync()) throw DVDocumentUnavailable(path, 'There is no file there.');
    final String extension = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    final String pdf = dvConvertedExtensions.contains(extension) ? await _convert(path) : path;
    return _serial(() {
      _init();
      final Pointer<Utf8> native = pdf.toNativeUtf8();
      final Pointer<Void> handle = fpdfLoadDocument(native, nullptr);
      calloc.free(native);
      if (handle == nullptr) {
        throw DVDocumentUnavailable(path, _loadError(fpdfGetLastError()));
      }
      return _PdfiumDocument(path, handle, fpdfGetPageCount(handle));
    });
  }

  static String _loadError(int code) => switch (code) {
        2 => 'The file could not be read.',
        3 => 'It is not a PDF, or it is damaged.',
        4 => 'It is protected by a password.',
        5 => 'Its security settings are not supported.',
        6 => 'A page could not be read.',
        _ => 'PDFium could not open it (error $code).',
      };

  /// Converted copies, by source path and modification time, so a deck is
  /// converted once per change.
  static final Map<String, String> _converted = <String, String>{};

  static Future<String> _convert(String path) async {
    final DateTime modified = File(path).lastModifiedSync();
    final String key = '$path@${modified.millisecondsSinceEpoch}';
    final String? known = _converted[key];
    if (known != null && File(known).existsSync()) return known;
    final String? soffice = findLibreOffice();
    if (soffice == null) {
      throw DVDocumentUnavailable(path,
          'Opening this kind of file needs LibreOffice, which is not installed. Install it from libreoffice.org, or save the file as PDF and use that.');
    }
    final Directory out = Directory.systemTemp.createTempSync('dartvel-doc-');
    final ProcessResult result = await Process.run(
      soffice,
      <String>['--headless', '--norestore', '--convert-to', 'pdf', '--outdir', out.path, path],
    ).timeout(const Duration(minutes: 3));
    final String name = path.split(Platform.pathSeparator).last;
    final String stem = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    final File pdf = File('${out.path}/$stem.pdf');
    if (result.exitCode != 0 || !pdf.existsSync()) {
      throw DVDocumentUnavailable(path, 'LibreOffice could not convert it: ${'${result.stderr}'.trim()}');
    }
    _converted[key] = pdf.path;
    return pdf.path;
  }

  /// LibreOffice's command, from PATH or where its installers put it.
  static String? findLibreOffice() {
    final List<String> candidates = <String>[
      if (Platform.isWindows) ...<String>[
        r'C:\Program Files\LibreOffice\program\soffice.exe',
        r'C:\Program Files (x86)\LibreOffice\program\soffice.exe',
      ],
      if (Platform.isMacOS) '/Applications/LibreOffice.app/Contents/MacOS/soffice',
    ];
    for (final String candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    for (final String name in <String>['soffice', 'libreoffice']) {
      final ProcessResult which = Process.runSync(Platform.isWindows ? 'where' : 'which', <String>[name]);
      if (which.exitCode == 0) return '${which.stdout}'.split('\n').first.trim();
    }
    return null;
  }
}

final class _PdfiumDocument implements DVDocument {
  _PdfiumDocument(this.path, this._handle, this.pageCount);

  @override
  final String path;
  final Pointer<Void> _handle;
  @override
  final int pageCount;
  bool _closed = false;

  @override
  Future<ui.Size> pageSize(int index) => _Pdfium._serial(() {
        final Pointer<Void> page = _page(index);
        try {
          return ui.Size(fpdfGetPageWidthF(page), fpdfGetPageHeightF(page));
        } finally {
          fpdfClosePage(page);
        }
      });

  @override
  Future<ui.Image> renderPage(int index, {required int width}) async {
    final ({Uint8List pixels, int width, int height, int stride}) drawn = await _Pdfium._serial(() {
      final Pointer<Void> page = _page(index);
      Pointer<Void> bitmap = nullptr;
      try {
        final double pageWidth = fpdfGetPageWidthF(page);
        final double pageHeight = fpdfGetPageHeightF(page);
        final int height = (width * pageHeight / pageWidth).round().clamp(1, 1 << 15);
        bitmap = fpdfBitmapCreate(width, height, 1);
        if (bitmap == nullptr) throw DVDocumentUnavailable(path, 'Not enough memory to draw page ${index + 1}.');
        fpdfBitmapFillRect(bitmap, 0, 0, width, height, 0xFFFFFFFF);
        fpdfRenderPageBitmap(bitmap, page, 0, 0, width, height, 0, fpdfAnnot | fpdfReverseByteOrder);
        final int stride = fpdfBitmapGetStride(bitmap);
        final Uint8List pixels = Uint8List.fromList(fpdfBitmapGetBuffer(bitmap).asTypedList(stride * height));
        return (pixels: pixels, width: width, height: height, stride: stride);
      } finally {
        if (bitmap != nullptr) fpdfBitmapDestroy(bitmap);
        fpdfClosePage(page);
      }
    });
    final Completer<ui.Image> image = Completer<ui.Image>();
    ui.decodeImageFromPixels(drawn.pixels, drawn.width, drawn.height, ui.PixelFormat.rgba8888, image.complete,
        rowBytes: drawn.stride);
    return image.future;
  }

  Pointer<Void> _page(int index) {
    if (_closed) throw StateError('$path is closed.');
    RangeError.checkValidIndex(index, this, 'index', pageCount);
    final Pointer<Void> page = fpdfLoadPage(_handle, index);
    if (page == nullptr) throw DVDocumentUnavailable(path, 'Page ${index + 1} could not be read.');
    return page;
  }

  @override
  Future<void> close() => _Pdfium._serial(() {
        if (_closed) return;
        _closed = true;
        fpdfCloseDocument(_handle);
      });
}

/// What [DVDocuments.open] calls on this target.
Future<DVDocument> dvOpenDocument(String path) => _Pdfium.open(path);

/// What [DVDocuments.dvFindLibreOffice] calls on this target.
String? dvFindLibreOffice() => _Pdfium.findLibreOffice();
