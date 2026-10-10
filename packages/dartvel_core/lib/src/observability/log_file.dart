/// The log a device keeps on its own disk.
///
/// A record that only went to the console is gone the moment the console is
/// not attached, which on a phone in somebody's pocket is always. This is the
/// copy that is still there when the person who saw the problem opens the
/// application again and is asked to send what it wrote.
library dartvel.observability.log_file;

import 'logging.dart';

export 'log_file_unsupported.dart'
    if (dart.library.io) 'log_file_io.dart';

/// A log kept somewhere it outlives the process.
abstract interface class DVLogFile implements DVLogSink {
  /// Every record still kept, oldest first, one JSON object per line.
  ///
  /// Lines that are not whole records -- the last one, cut short by the
  /// crash that was writing it -- are left out rather than passed on as
  /// something a reader would try to parse.
  String export();

  /// Removes every record. The log keeps working afterwards.
  void clear();

  /// Releases the open file. Writing again reopens it.
  void close();
}
