/// What a browser drop carried, as the map every binding hands over. Pure
/// Dart, so it is tested on the VM with recorded DataTransfer shapes.
library;

/// The map [DVDropEvent.fromMap] takes, from what a browser drop carried.
/// Separate from the event handling so the translation is testable.
Map<String, Object?> dvWebDropMap({
  required List<Map<String, Object?>> files,
  required String uriList,
  required String text,
  double x = 0,
  double y = 0,
}) {
  // text/uri-list is one URL per line, with # starting a comment line.
  final List<String> urls = <String>[
    for (final String line in uriList.split(RegExp(r'\r?\n')))
      if (line.trim().isNotEmpty && !line.trim().startsWith('#')) line.trim(),
  ];
  // A dragged link also arrives as text/plain holding the same URL; that is
  // the link, not separate text.
  final bool textIsTheLink = urls.length == 1 && text.trim() == urls.single;
  return <String, Object?>{
    'files': <Map<String, Object?>>[
      for (final Map<String, Object?> file in files)
        <String, Object?>{
          ...file,
          if (file['mimeType'] == '') 'mimeType': null,
        },
    ],
    'urls': urls,
    if (text.isNotEmpty && !textIsTheLink) 'text': text,
    'x': x,
    'y': y,
  };
}
