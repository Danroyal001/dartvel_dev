/// [text] as a URL slug: lowercase words joined by [separator].
String slugify(String text, {String separator = '-'}) => text
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
    .split(RegExp(r'[\s-]+'))
    .where((String w) => w.isNotEmpty)
    .join(separator);
