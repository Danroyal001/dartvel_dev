/// PDFium's C API, as much of it as rendering pages needs. The library is the
/// `pdfium.dart` code asset the build hook bundles for the target.
@DefaultAsset('package:dartvel_documents/pdfium.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

@Native<Void Function()>(symbol: 'FPDF_InitLibrary')
external void fpdfInitLibrary();

@Native<Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>)>(symbol: 'FPDF_LoadDocument')
external Pointer<Void> fpdfLoadDocument(Pointer<Utf8> path, Pointer<Utf8> password);

@Native<Void Function(Pointer<Void>)>(symbol: 'FPDF_CloseDocument')
external void fpdfCloseDocument(Pointer<Void> document);

/// FPDF_DWORD is C `unsigned long`: 64 bits on Linux and macOS, 32 on Windows.
@Native<UnsignedLong Function()>(symbol: 'FPDF_GetLastError')
external int fpdfGetLastError();

@Native<Int32 Function(Pointer<Void>)>(symbol: 'FPDF_GetPageCount')
external int fpdfGetPageCount(Pointer<Void> document);

@Native<Pointer<Void> Function(Pointer<Void>, Int32)>(symbol: 'FPDF_LoadPage')
external Pointer<Void> fpdfLoadPage(Pointer<Void> document, int index);

@Native<Void Function(Pointer<Void>)>(symbol: 'FPDF_ClosePage')
external void fpdfClosePage(Pointer<Void> page);

/// In points (1/72 inch). C `float`, not `double`.
@Native<Float Function(Pointer<Void>)>(symbol: 'FPDF_GetPageWidthF')
external double fpdfGetPageWidthF(Pointer<Void> page);

@Native<Float Function(Pointer<Void>)>(symbol: 'FPDF_GetPageHeightF')
external double fpdfGetPageHeightF(Pointer<Void> page);

/// A BGRA (or BGRx without alpha) bitmap PDFium owns.
@Native<Pointer<Void> Function(Int32, Int32, Int32)>(symbol: 'FPDFBitmap_Create')
external Pointer<Void> fpdfBitmapCreate(int width, int height, int alpha);

@Native<Int32 Function(Pointer<Void>, Int32, Int32, Int32, Int32, UnsignedLong)>(symbol: 'FPDFBitmap_FillRect')
external int fpdfBitmapFillRect(Pointer<Void> bitmap, int left, int top, int width, int height, int color);

@Native<Void Function(Pointer<Void>, Pointer<Void>, Int32, Int32, Int32, Int32, Int32, Int32)>(
    symbol: 'FPDF_RenderPageBitmap')
external void fpdfRenderPageBitmap(
    Pointer<Void> bitmap, Pointer<Void> page, int startX, int startY, int sizeX, int sizeY, int rotate, int flags);

@Native<Pointer<Uint8> Function(Pointer<Void>)>(symbol: 'FPDFBitmap_GetBuffer')
external Pointer<Uint8> fpdfBitmapGetBuffer(Pointer<Void> bitmap);

@Native<Int32 Function(Pointer<Void>)>(symbol: 'FPDFBitmap_GetStride')
external int fpdfBitmapGetStride(Pointer<Void> bitmap);

@Native<Void Function(Pointer<Void>)>(symbol: 'FPDFBitmap_Destroy')
external void fpdfBitmapDestroy(Pointer<Void> bitmap);

/// FPDF_ANNOT: draw annotations (form fields, stamps) as a viewer does.
const int fpdfAnnot = 0x01;

/// FPDF_LCD_TEXT is for subpixel screens; on a projector, plain antialiasing.
const int fpdfReverseByteOrder = 0x10;
