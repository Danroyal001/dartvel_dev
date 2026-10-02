/// A browser has no paths to read; an opened file arrives with its bytes.
Future<List<int>> dvReadOpenedFile(String path) =>
    Future<List<int>>.error(UnsupportedError('A browser cannot read $path by path; the bytes came with the file.'));
