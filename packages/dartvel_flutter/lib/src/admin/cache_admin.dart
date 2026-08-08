import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// The cache and tag explorer: which tags exist, what they cover, and a way
/// to revalidate one.
///
/// A tag is how a group of entries is invalidated together, so the question
/// an operator actually has is "what would revalidating this drop?" — which
/// needs the keys, not just the tag name.
class DVCacheAdmin extends StatefulWidget {
  const DVCacheAdmin({super.key});

  @override
  State<DVCacheAdmin> createState() => _DVCacheAdminState();
}

class _DVCacheAdminState extends State<DVCacheAdmin> {
  static const DVCache _cache = DVCache();

  List<String> _tags = <String>[];
  String? _notice;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _tags = _cache.tags.toList(growable: false)..sort();
    });
  }

  Future<void> _revalidate(String tag) async {
    try {
      final dropped = await _cache.revalidateTag(tag);
      if (!mounted) return;
      // The count is the point: revalidating a tag that covered nothing looks
      // identical to revalidating one that cleared a hundred entries.
      setState(() => _notice =
          'Revalidated $tag: ${dropped.length} ${dropped.length == 1 ? 'entry' : 'entries'} dropped.');
      _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DVBox.scrollableList(<Widget>[
      const DVText('Cache Tags')
          .modifier(const DVModifier().fontSize(24).fontWeight(FontWeight.bold)),
      if (_error != null) DVText('Could not read the cache: $_error'),
      if (_notice != null) DVText(_notice!),
      GestureDetector(
        key: const ValueKey<String>('dv-cache-refresh'),
        onTap: _load,
        child: const DVText('Refresh'),
      ),
      if (_tags.isEmpty) const DVText('No tagged cache entries.'),
      for (final tag in _tags) _tagSection(tag),
    ]);
  }

  Widget _tagSection(String tag) {
    final keys = _cache.keysForTag(tag).toList(growable: false)..sort();
    return DVBox.list(<Widget>[
      DVText(tag)
          .modifier(const DVModifier().fontSize(18).fontWeight(FontWeight.bold)),
      DVText('${keys.length} ${keys.length == 1 ? 'key' : 'keys'}'),
      for (final key in keys) DVText(key),
      GestureDetector(
        key: ValueKey<String>('dv-cache-revalidate-$tag'),
        onTap: () => _revalidate(tag),
        child: const DVText('Revalidate'),
      ),
    ]).modifier(const DVModifier().card().padding(16));
  }
}
