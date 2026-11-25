/// The browser half of find in page: the hidden copy of the page's text the
/// browser searches, and what happens when it lands in it.
///
/// The build writes a copy of each page's text into its HTML, each paragraph
/// in a `hidden="until-found"` section (dvFindableHtml). That covers the first
/// paint and every reader who does not run the app. From there the runtime
/// keeps it current -- the reader routes on the client, and the page draws
/// what its data brought -- and listens for the browser saying which section
/// it matched in.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:dartvel_core/dartvel.dart'
    show
        DVDocumentCollection,
        DVFindBlock,
        dvFallbackCss,
        dvFallbackIsStale,
        dvFindAnchorAttribute,
        dvFindMirrorBlocks,
        dvFindMissing,
        dvFindRuntimeAnchor,
        dvDocumentOfPage,
        dvDocumentRows,
        dvHeadingIds;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show Element, WidgetsBinding;
import 'package:web/web.dart' as web;

import 'find_in_page.dart';
import '../lists/document_rows.dart';

bool _installed = false;

/// Whether the find runtime is keeping the page-text block current, which
/// takes over from the SEO layer's dropping it after the first navigation.
bool get dvFindOwnsFallback => _installed;

/// How long, in milliseconds, the page has to stop drawing before its text is
/// read again.
///
/// Debounced on frames, so reading the text never competes with an animation
/// or a scroll, and a page that settles is read once rather than every frame.
const int _settleAfterMs = 400;

/// The browser's timer rather than a Dart [Timer]: this is housekeeping for
/// the document, and a Dart timer re-armed on every frame is a timer still
/// pending when any widget test of any page ends.
int? _settle;

/// What the block was last written from, so a page that drew the same words
/// again does not rewrite the DOM for nothing.
String? _written;

/// Marks a block the runtime wrote, as against one the build wrote.
const String _runtimeAttribute = 'data-dv-runtime';

/// The container, inside a block the build wrote, for what the page drew
/// that the build's copy does not say.
const String _extraAttribute = 'data-dv-runtime-extra';

/// Listens for the browser's matches and keeps the copy current.
///
/// Once per application, from the first page shell built. Nothing here runs
/// until a frame has been drawn and the page has stopped drawing.
void dvFindInstall() {
  if (_installed) return;
  _installed = true;
  // Captured on the document: the event is fired on the section, which
  // Flutter knows nothing about.
  web.document.addEventListener('beforematch', _onBeforeMatch.toJS, true.toJS);
  SchedulerBinding.instance.addPersistentFrameCallback((Duration _) {
    final int? pending = _settle;
    if (pending != null) web.window.clearTimeout(pending);
    _settle = web.window.setTimeout(
      (() {
        _settle = null;
        _refresh();
        _standInRows();
      }).toJS,
      _settleAfterMs.toJS,
    );
  });
}

/// Where the reader is, as the build would have stamped it.
///
/// The hash first, for an application using the hash URL strategy: there the
/// path is `#/invoice/12` and `pathname` is whatever served the shell.
String _currentPath() {
  final String hash = web.window.location.hash;
  if (hash.startsWith('#/')) return hash.substring(1);
  return web.window.location.pathname;
}

/// The browser matched text in one of the sections.
///
/// It has removed the section's `hidden` attribute and is about to scroll to
/// it and highlight the match -- inside a clipped box of one pixel, where
/// neither shows. The page does both instead: scrolls the Flutter page to the
/// paragraph the section mirrors and highlights it there.
void _onBeforeMatch(web.Event event) {
  final JSAny? target = event.target;
  if (target == null || !target.isA<web.Element>()) return;
  final web.Element? section = (target as web.Element)
      .closest('.dv-fallback [$dvFindAnchorAttribute]');
  if (section == null) return;
  _follow(section);
}

/// Scroll the page to what [section] mirrors, and hide it again.
void _follow(web.Element section) {
  final String text = section.textContent ?? '';
  final int? hint =
      dvFindRuntimeAnchor(section.getAttribute(dvFindAnchorAttribute));
  // Hidden again on the next task, after the browser has finished revealing
  // it: the mirror never paints over the canvas, and hidden until-found is
  // still searched, so the next match in the same section fires again.
  web.window.setTimeout(
    (() => section.setAttribute('hidden', 'until-found')).toJS,
    0.toJS,
  );
  unawaited(DVFindInPage.reveal(text, hint: hint));
}

/// Read the page on top again and bring the block in line with it.
void _refresh() {
  final DVFindPage? page = DVFindInPage.active;
  final String path = _currentPath();
  web.Element? block = web.document.querySelector('.dv-fallback');

  if (page == null || !page.findable) {
    _optOut(block, path);
    return;
  }

  // A section the browser revealed before anything was listening: a link
  // carrying a text fragment (`#:~:text=`), which is what a search result's
  // "jump to" link is, lands on the build's copy while the app is still
  // loading. The page it names is drawn now, so go there.
  final web.Element? revealed = web.document.querySelector(
      '.dv-fallback [$dvFindAnchorAttribute]:not([hidden])');
  if (revealed != null) _follow(revealed);

  final List<DVFindBlock> blocks = dvFindMirrorBlocks(
    DVFindInPage.paragraphs().map((DVFoundParagraph p) => p.block),
  );
  bool builtForHere = block != null &&
      !block.hasAttribute(_runtimeAttribute) &&
      !dvFallbackIsStale(block.getAttribute('data-dv-path'), path);
  if (builtForHere) {
    _keepDocument(path, block);
  } else {
    // After a navigation: the document the server sends for this page, when
    // it is at hand, is the copy find searches -- every row of it, built or
    // not, with its links -- and what the page drew beside it, as on the
    // page the reader arrived on.
    final String? document = _documentFor(path, wanted: _rowsWaiting);
    if (document != null && document.isNotEmpty) {
      block = _writeDocument(block, document, path);
      builtForHere = true;
    }
  }
  final String signature =
      '$path\u0000$builtForHere\u0000${blocks.map((DVFindBlock b) => '${b.tag}:${b.text}').join('\u0000')}';
  if (signature == _written && block != null && block.isConnected) return;
  _written = signature;

  if (builtForHere) {
    _writeExtra(block!, blocks);
  } else {
    _writeMirror(block, blocks, path);
  }
}

/// On the route the build wrote the block for, the block stays: it carries
/// the links and landmarks the semantics tree gave it, which a crawler that
/// runs scripts reads and a copy rebuilt from painted paragraphs would lose.
/// What the page drew since goes beside it.
void _writeExtra(web.Element block, List<DVFindBlock> blocks) {
  final String built = _textOutside(block);
  final Set<DVFindBlock> missing = dvFindMissing(built, blocks).toSet();
  web.Element? extra = block.querySelector('[$_extraAttribute]');
  if (missing.isEmpty) {
    extra?.remove();
    _hideFromAssistiveTech(block);
    return;
  }
  extra ??= web.document.createElement('div')
    ..setAttribute(_extraAttribute, '');
  if (!extra.isConnected) block.append(extra);
  _fill(
    extra,
    <int, DVFindBlock>{
      for (int i = 0; i < blocks.length; i++)
        if (missing.contains(blocks[i])) i: blocks[i],
    },
    dvHeadingIds(blocks),
  );
  _hideFromAssistiveTech(block);
}

/// Anywhere else -- after a navigation, or on a page served with no block --
/// the block is the page on screen, written from what it drew.
void _writeMirror(web.Element? block, List<DVFindBlock> blocks, String path) {
  _ensureStyle();
  final web.Element target = block ??
      (web.document.createElement('div')..className = 'dv-fallback');
  if (!target.isConnected) web.document.body?.append(target);
  target
    ..setAttribute('data-dv-path', path)
    ..setAttribute(_runtimeAttribute, '');
  _fill(
    target,
    <int, DVFindBlock>{for (int i = 0; i < blocks.length; i++) i: blocks[i]},
    dvHeadingIds(blocks),
  );
  _hideFromAssistiveTech(target);
}

/// Replace [parent]'s children with one until-found section per block, each
/// anchored with the index it was read at. A heading carries its id from
/// [dvHeadingIds], the one a link to it names, so the browser has an element
/// to go to as well as the page.
///
/// Built as elements with text content, never as markup: the text is
/// whatever the page drew, and a paragraph that reads `<img onerror=...>` is
/// a paragraph, not an image.
void _fill(
    web.Element parent, Map<int, DVFindBlock> blocks, List<String?> ids) {
  while (parent.firstChild != null) {
    parent.removeChild(parent.firstChild!);
  }
  for (final MapEntry<int, DVFindBlock> entry in blocks.entries) {
    final web.Element section = web.document.createElement('section')
      ..setAttribute('hidden', 'until-found')
      ..setAttribute(dvFindAnchorAttribute, 'r${entry.key}');
    final web.Element element = web.document.createElement(entry.value.tag)
      ..textContent = entry.value.text;
    final String? id = entry.key < ids.length ? ids[entry.key] : null;
    // Only where the document has no element by that id already: the
    // build's copy, or the application's own page, may have one.
    if (id != null && web.document.getElementById(id) == null) {
      element.id = id;
    }
    section.append(element);
    parent.append(section);
  }
}

/// The block's text less what the runtime added to it.
String _textOutside(web.Element block) {
  final web.Element? extra = block.querySelector('[$_extraAttribute]');
  final String all = block.textContent ?? '';
  final String added = extra?.textContent ?? '';
  return added.isEmpty ? all : all.replaceFirst(added, '');
}

/// Screen readers read the page from Flutter's semantics tree, so the copy
/// is kept from them: the page read twice is worse than the page read once.
///
/// Set here and not by the build, because a reader with scripting off has no
/// semantics tree -- for them the block is the page.
void _hideFromAssistiveTech(web.Element block) {
  block.setAttribute('aria-hidden', 'true');
}

/// The style element the block needs: clipped on screen, and the print rules.
///
/// Normally the build's. Absent when the page was served with no block, or
/// after an opted-out page took the block away.
void _ensureStyle() {
  if (web.document.querySelector('style.dv-fallback-style') != null) return;
  final web.Element style = web.document.createElement('style')
    ..className = 'dv-fallback-style'
    ..textContent = dvFallbackCss;
  web.document.body?.append(style);
}

/// The page on top said `findable: false`, or there is no page shell up.
///
/// A block written for another page goes, style and all -- the print rules
/// are in the style, and printing somebody else's page is worse than
/// printing the canvas. A block the build wrote for this page stays for the
/// printer and stops being searched: its sections become plainly hidden,
/// which the print rules still show.
void _optOut(web.Element? block, String path) {
  _written = null;
  if (block == null) return;
  final bool builtForHere = !block.hasAttribute(_runtimeAttribute) &&
      !dvFallbackIsStale(block.getAttribute('data-dv-path'), path);
  if (!builtForHere) {
    final web.NodeList parts =
        web.document.querySelectorAll('.dv-fallback,.dv-fallback-style');
    for (int i = parts.length - 1; i >= 0; i--) {
      (parts.item(i) as web.Element?)?.remove();
    }
    return;
  }
  // No page shell up at all is not a page that opted out.
  if (DVFindInPage.active == null) return;
  block.querySelector('[$_extraAttribute]')?.remove();
  final web.NodeList sections =
      block.querySelectorAll('[$dvFindAnchorAttribute]');
  for (int i = 0; i < sections.length; i++) {
    (sections.item(i) as web.Element?)?.setAttribute('hidden', '');
  }
}

// -- The document the server sends for each page, for what is not built.
//
// A lazy list builds only the rows near the screen. On the page the reader
// arrived on, the block the build wrote holds every row; after a navigation
// inside the app, the page the server would send for the new address holds
// them, and it is fetched once, when the page has rows waiting, while the
// page is idle. From it, find searches every row (above), and each row not
// built stands in with what the document says it holds
// (lists/document_rows.dart): no row is built to be read.

/// The document of each page, by path; empty when its page has none.
final Map<String, String> _documents = <String, String>{};

/// The rows each document marks, read once.
final Map<String, List<DVDocumentCollection>> _documentRows = <String, List<DVDocumentCollection>>{};

/// Paths being fetched.
final Set<String> _fetching = <String>{};

/// Whether a lazy list on the page has rows waiting for their stand-ins.
bool get _rowsWaiting => DVDocumentRows.enabled && DVDocumentRows.waiting.isNotEmpty;

/// The block the build wrote for [path], kept as it was written: it is
/// rewritten after a navigation, and a reader may come back.
void _keepDocument(String path, web.Element block) {
  if (_documents.containsKey(path)) return;
  final web.Element copy = block.cloneNode(true) as web.Element;
  copy.querySelector('[$_extraAttribute]')?.remove();
  _documents[path] = (copy.innerHTML as JSString).toDart;
}

/// The document of [path], when it is at hand. Fetched once, when [wanted]:
/// the page it is for asks again when it arrives.
String? _documentFor(String path, {required bool wanted}) {
  final String? known = _documents[path];
  if (known != null || !wanted || _fetching.contains(path)) return known;
  _fetching.add(path);
  unawaited(() async {
    String document = '';
    try {
      final web.Response response = await web.window
          .fetch(
            Uri.base.resolve(path).toString().toJS,
            web.RequestInit(credentials: 'same-origin', headers: <String, String>{'Accept': 'text/html'}.jsify()! as web.HeadersInit),
          )
          .toDart;
      if (response.ok) {
        document = dvDocumentOfPage((await response.text().toDart).toDart) ?? '';
      }
    } catch (_) {
      // Offline, or the server says no: the page keeps what it drew.
    }
    _fetching.remove(path);
    _documents[path] = document;
    if (document.isNotEmpty && _currentPath() == path) {
      _refresh();
      _standInRows();
    }
  }());
  return null;
}

/// [document] as the block for [path]: a copy find searches, hidden from
/// assistive technology as every copy is.
web.Element _writeDocument(web.Element? block, String document, String path) {
  _ensureStyle();
  final web.Element target = block ?? (web.document.createElement('div')..className = 'dv-fallback');
  if (!target.isConnected) web.document.body?.append(target);
  while (target.firstChild != null) {
    target.removeChild(target.firstChild!);
  }
  // Parsed apart from the page, so nothing in it runs or loads.
  final web.Document parsed = web.DOMParser().parseFromString(document.toJS, 'text/html');
  final web.HTMLElement? body = parsed.body;
  if (body != null) {
    while (body.firstChild != null) {
      target.append(web.document.adoptNode(body.firstChild!));
    }
  }
  target
    ..setAttribute('data-dv-path', path)
    ..removeAttribute(_runtimeAttribute);
  _hideFromAssistiveTech(target);
  _written = null;
  return target;
}

/// Gives the rows waiting on the page their stand-ins from its document, a
/// few at a time: each batch draws a frame, and the next waits for the page
/// to be still again.
void _standInRows() {
  if (!_rowsWaiting) return;
  final String path = _currentPath();
  final String? document = _documentFor(path, wanted: true);
  if (document == null || document.isEmpty) return;
  final List<DVDocumentCollection> collections = _documentRows[path] ??= dvDocumentRows(document);
  if (collections.isEmpty) return;
  final Element? root = WidgetsBinding.instance.rootElement;
  if (root == null) return;
  dvApplyDocumentRows(root, collections, limit: _standInsPerStep);
}

/// How many rows one idle moment gives stand-ins to.
const int _standInsPerStep = 24;
