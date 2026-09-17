/// A Windows pseudo console (ConPTY), opened through `dart:ffi`.
///
/// Windows has no `script(1)`. What a terminal application draws on Windows
/// goes to its console, not its standard output, so a pipe captures nothing a
/// windows-cli bundle renders; a pseudo console turns that console into a
/// byte stream of VT sequences, which is what a terminal would be sent.
///
/// kernel32 only, allocated with LocalAlloc, so no package dependency is added
/// for one command.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

/// What a run under ConPTY produced.
class DVConPtyRun {
  const DVConPtyRun({required this.exitCode});

  /// The exit code, or null when the process was still running and was
  /// terminated.
  final int? exitCode;
}

final class _Coord extends Struct {
  @Int16()
  external int x;
  @Int16()
  external int y;
}

final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

final int Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<Void>, int)
_createPipe = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<Void>, Uint32),
      int Function(Pointer<IntPtr>, Pointer<IntPtr>, Pointer<Void>, int)
    >('CreatePipe');

final int Function(_Coord, int, int, int, Pointer<IntPtr>)
_createPseudoConsole = _kernel32
    .lookupFunction<
      Int32 Function(_Coord, IntPtr, IntPtr, Uint32, Pointer<IntPtr>),
      int Function(_Coord, int, int, int, Pointer<IntPtr>)
    >('CreatePseudoConsole');

final void Function(int) _closePseudoConsole = _kernel32
    .lookupFunction<Void Function(IntPtr), void Function(int)>(
      'ClosePseudoConsole',
    );

final int Function(Pointer<Void>, int, int, Pointer<IntPtr>)
_initializeProcThreadAttributeList = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Uint32, Pointer<IntPtr>),
      int Function(Pointer<Void>, int, int, Pointer<IntPtr>)
    >('InitializeProcThreadAttributeList');

final int Function(
  Pointer<Void>,
  int,
  int,
  Pointer<Void>,
  int,
  Pointer<Void>,
  Pointer<Void>,
)
_updateProcThreadAttribute = _kernel32
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Uint32,
        IntPtr,
        Pointer<Void>,
        IntPtr,
        Pointer<Void>,
        Pointer<Void>,
      ),
      int Function(
        Pointer<Void>,
        int,
        int,
        Pointer<Void>,
        int,
        Pointer<Void>,
        Pointer<Void>,
      )
    >('UpdateProcThreadAttribute');

final void Function(Pointer<Void>) _deleteProcThreadAttributeList = _kernel32
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'DeleteProcThreadAttributeList',
    );

final int Function(
  Pointer<Void>,
  Pointer<Uint16>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  int,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
)
_createProcessW = _kernel32
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<Uint16>,
        Pointer<Void>,
        Pointer<Void>,
        Int32,
        Uint32,
        Pointer<Void>,
        Pointer<Void>,
        Pointer<Void>,
        Pointer<Void>,
      ),
      int Function(
        Pointer<Void>,
        Pointer<Uint16>,
        Pointer<Void>,
        Pointer<Void>,
        int,
        int,
        Pointer<Void>,
        Pointer<Void>,
        Pointer<Void>,
        Pointer<Void>,
      )
    >('CreateProcessW');

final int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
_writeFile = _kernel32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint32>,
        Pointer<Void>,
      ),
      int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
    >('WriteFile');

final int Function(int, int) _waitForSingleObject = _kernel32
    .lookupFunction<Uint32 Function(IntPtr, Uint32), int Function(int, int)>(
      'WaitForSingleObject',
    );

final int Function(int, Pointer<Uint32>) _getExitCodeProcess = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)
    >('GetExitCodeProcess');

final int Function(int, int) _terminateProcess = _kernel32
    .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
      'TerminateProcess',
    );

final int Function(int) _closeHandle = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

final Pointer<Void> Function(int, int) _localAlloc = _kernel32
    .lookupFunction<
      Pointer<Void> Function(Uint32, IntPtr),
      Pointer<Void> Function(int, int)
    >('LocalAlloc');

final void Function(Pointer<Void>) _localFree = _kernel32
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'LocalFree',
    );

final int Function() _getLastError = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetLastError');

const int _lmemZeroInit = 0x0040;
const int _procThreadAttributePseudoConsole = 0x00020016;
const int _extendedStartupInfoPresent = 0x00080000;
const int _startfUseStdHandles = 0x00000100;
const int _waitObject0 = 0;
const int _invalidHandle = -1;

// STARTUPINFOEXW on 64-bit Windows: STARTUPINFOW is 104 bytes and the
// attribute list pointer follows it.
const int _startupInfoExSize = 112;
const int _startupInfoFlagsOffset = 60;
const int _startupInfoStdInputOffset = 80;
const int _startupInfoAttributeListOffset = 104;
const int _processInformationSize = 24;

Pointer<T> _alloc<T extends NativeType>(int bytes) {
  final Pointer<Void> memory = _localAlloc(_lmemZeroInit, bytes);
  if (memory == nullptr) {
    throw StateError('LocalAlloc($bytes) failed');
  }
  return memory.cast<T>();
}

Never _fail(String call) =>
    throw StateError('$call failed (Windows error ${_getLastError()})');

/// Runs [commandLine] in a [columns]x[rows] pseudo console for [window],
/// passing everything it draws to [onOutput].
///
/// With [interrupt], Ctrl+C is typed at the end of the window and the process
/// has [exitWithin] to exit; without it, or when it does not, the process is
/// terminated.
Future<DVConPtyRun> dvRunInConPty({
  required String commandLine,
  required int rows,
  required int columns,
  required Duration window,
  required bool interrupt,
  required Duration exitWithin,
  required void Function(List<int> bytes) onOutput,
}) async {
  if (sizeOf<IntPtr>() != 8) {
    throw UnsupportedError('ConPTY capture is implemented for 64-bit Windows');
  }

  final Pointer<IntPtr> inputRead = _alloc<IntPtr>(8);
  final Pointer<IntPtr> inputWrite = _alloc<IntPtr>(8);
  final Pointer<IntPtr> outputRead = _alloc<IntPtr>(8);
  final Pointer<IntPtr> outputWrite = _alloc<IntPtr>(8);
  final Pointer<IntPtr> console = _alloc<IntPtr>(8);
  if (_createPipe(inputRead, inputWrite, nullptr, 0) == 0) _fail('CreatePipe');
  if (_createPipe(outputRead, outputWrite, nullptr, 0) == 0) {
    _fail('CreatePipe');
  }

  final _Coord size = Struct.create<_Coord>()
    ..x = columns
    ..y = rows;
  final int hr = _createPseudoConsole(
    size,
    inputRead.value,
    outputWrite.value,
    0,
    console,
  );
  if (hr != 0) {
    throw StateError(
      'CreatePseudoConsole failed (HRESULT '
      '0x${(hr & 0xffffffff).toRadixString(16)})',
    );
  }

  // The attribute list that attaches the child to the pseudo console.
  final Pointer<IntPtr> listSize = _alloc<IntPtr>(8);
  _initializeProcThreadAttributeList(nullptr, 1, 0, listSize);
  final Pointer<Void> attributes = _alloc<Void>(listSize.value);
  if (_initializeProcThreadAttributeList(attributes, 1, 0, listSize) == 0) {
    _fail('InitializeProcThreadAttributeList');
  }
  if (_updateProcThreadAttribute(
        attributes,
        0,
        _procThreadAttributePseudoConsole,
        Pointer<Void>.fromAddress(console.value),
        8,
        nullptr,
        nullptr,
      ) ==
      0) {
    _fail('UpdateProcThreadAttribute');
  }

  final Pointer<Uint8> startupInfo = _alloc<Uint8>(_startupInfoExSize);
  final Uint8List infoBytes = startupInfo.asTypedList(_startupInfoExSize);
  final ByteData view = ByteData.sublistView(infoBytes);
  view.setUint32(0, _startupInfoExSize, Endian.little);
  // Standard handles explicitly invalid: without STARTF_USESTDHANDLES a child
  // inherits this process's redirected handles, and a runner's are pipes, so
  // anything written to them would bypass the pseudo console.
  view.setUint32(_startupInfoFlagsOffset, _startfUseStdHandles, Endian.little);
  for (var i = 0; i < 3; i++) {
    view.setInt64(
      _startupInfoStdInputOffset + 8 * i,
      _invalidHandle,
      Endian.little,
    );
  }
  view.setInt64(
    _startupInfoAttributeListOffset,
    attributes.address,
    Endian.little,
  );

  final List<int> units = '$commandLine '.codeUnits;
  final Pointer<Uint16> commandLineW = _alloc<Uint16>(units.length * 2);
  commandLineW.asTypedList(units.length).setAll(0, units);

  final Pointer<Uint8> processInfo = _alloc<Uint8>(_processInformationSize);
  if (_createProcessW(
        nullptr,
        commandLineW,
        nullptr,
        nullptr,
        0,
        _extendedStartupInfoPresent,
        nullptr,
        nullptr,
        startupInfo.cast(),
        processInfo.cast(),
      ) ==
      0) {
    _fail('CreateProcessW');
  }
  final ByteData processView = ByteData.sublistView(
    processInfo.asTypedList(_processInformationSize),
  );
  final int process = processView.getInt64(0, Endian.little);
  final int thread = processView.getInt64(8, Endian.little);
  _closeHandle(thread);

  // The pseudo console holds its own references to these two.
  _closeHandle(inputRead.value);
  _closeHandle(outputWrite.value);

  // Output is read on another isolate. ReadFile blocks, and a pseudo console
  // whose output nobody drains blocks the child writing to it.
  final ReceivePort chunks = ReceivePort();
  final Completer<void> drained = Completer<void>();
  chunks.listen((Object? message) {
    if (message is TransferableTypedData) {
      onOutput(message.materialize().asUint8List());
    } else {
      chunks.close();
      if (!drained.isCompleted) drained.complete();
    }
  });
  await Isolate.spawn(_drain, <Object>[outputRead.value, chunks.sendPort]);

  await Future<void>.delayed(window);

  int? exitCode;
  if (interrupt) {
    final Pointer<Uint8> ctrlC = _alloc<Uint8>(1)..value = 3;
    final Pointer<Uint32> written = _alloc<Uint32>(4);
    _writeFile(inputWrite.value, ctrlC, 1, written, nullptr);
    _localFree(ctrlC.cast());
    _localFree(written.cast());

    final DateTime deadline = DateTime.now().add(exitWithin);
    while (DateTime.now().isBefore(deadline)) {
      if (_waitForSingleObject(process, 0) == _waitObject0) {
        final Pointer<Uint32> code = _alloc<Uint32>(4);
        _getExitCodeProcess(process, code);
        exitCode = code.value;
        _localFree(code.cast());
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
  if (exitCode == null) {
    _terminateProcess(process, 1);
    _waitForSingleObject(process, 5000);
  }

  // Closing the pseudo console ends the output pipe, which ends the drain.
  _closePseudoConsole(console.value);
  await drained.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  _closeHandle(inputWrite.value);
  _closeHandle(process);

  _deleteProcThreadAttributeList(attributes);
  for (final Pointer<NativeType> p in <Pointer<NativeType>>[
    inputRead,
    inputWrite,
    outputRead,
    outputWrite,
    console,
    listSize,
    attributes,
    startupInfo,
    commandLineW,
    processInfo,
  ]) {
    _localFree(p.cast());
  }
  return DVConPtyRun(exitCode: exitCode);
}

void _drain(List<Object> arguments) {
  final int handle = arguments[0] as int;
  final SendPort port = arguments[1] as SendPort;
  final DynamicLibrary kernel32 = DynamicLibrary.open('kernel32.dll');
  final int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
  readFile = kernel32
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Void>,
        ),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
      >('ReadFile');
  final Pointer<Void> Function(int, int) localAlloc = kernel32
      .lookupFunction<
        Pointer<Void> Function(Uint32, IntPtr),
        Pointer<Void> Function(int, int)
      >('LocalAlloc');
  final int Function(int) closeHandle = kernel32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

  const int capacity = 65536;
  final Pointer<Uint8> buffer = localAlloc(_lmemZeroInit, capacity).cast();
  final Pointer<Uint32> read = localAlloc(_lmemZeroInit, 4).cast();
  while (readFile(handle, buffer, capacity, read, nullptr) != 0 &&
      read.value > 0) {
    port.send(
      TransferableTypedData.fromList(<TypedData>[
        Uint8List.fromList(buffer.asTypedList(read.value)),
      ]),
    );
  }
  closeHandle(handle);
  port.send(null);
}
