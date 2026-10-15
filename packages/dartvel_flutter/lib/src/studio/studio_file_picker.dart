/// Choosing files to upload to Studio's media library.
///
/// In a browser, which is where Studio runs, the files come back as bytes
/// from an `<input type="file">`; elsewhere through the platform's open
/// dialog. Either way only the kinds of file the library takes are offered,
/// the same list the server checks again.
library;

import 'studio_file_picker_io.dart'
    if (dart.library.js_interop) 'studio_file_picker_web.dart' as picker;

/// A file somebody picked: its name and its bytes.
typedef DVStudioPickedFile = ({String name, List<int> bytes});

/// Asks for files; empty when the person cancelled.
typedef DVStudioPickFiles = Future<List<DVStudioPickedFile>> Function();

/// Asks the person for one or more files to upload.
Future<List<DVStudioPickedFile>> dvStudioPickFiles() => picker.dvPickFiles();
