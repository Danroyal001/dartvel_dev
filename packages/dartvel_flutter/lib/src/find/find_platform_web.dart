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
        DVFindBlock,
        dvFallbackCss,
        dvFallbackIsStale,
        dvFindAnchorAttribute,
        dvFindMirrorBlocks,
        dvFindMissing,
        dvFindRuntimeAnchor;
import 'package:flutter/scheduler.dart';
import 'package:web/web.dart' as web;

import 'find_in_page.dart';

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
  final web.Element? block = web.document.querySelector('.dv-fallback');

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
  final bool builtForHere = block != null &&
      !block.hasAttribute(_runtimeAttribute) &&
      !dvFallbackIsStale(block.getAttribute('data-dv-path'), path);
  final String signature =
      '$path\u0000$builtForHere\u0000${blocks.map((DVFindBlock b) => '${b.tag}:${b.text}').join('\u0000')}';
  if (signature == _written && block != null && block.isConnected) return;
  _written = signature;

  if (builtForHere) {
    _writeExtra(block, blocks);
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
  _fill(extra, <int, DVFindBlock>{
    for (int i = 0; i < blocks.length; i++)
      if (missing.contains(blocks[i])) i: blocks[i],
  });
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
  _fill(target, <int, DVFindBlock>{
    for (int i = 0; i < blocks.length; i++) i: blocks[i],
  });
  _hideFromAssistiveTech(target);
}

/// Replace [parent]'s children with one until-found section per block, each
/// anchored with the index it was read at.
///
/// Built as elements with text content, never as markup: the text is
/// whatever the page drew, and a paragraph that reads `<img onerror=...>` is
/// a paragraph, not an image.
void _fill(web.Element parent, Map<int, DVFindBlock> blocks) {
  while (parent.firstChild != null) {
    parent.removeChild(parent.firstChild!);
  }
  for (final MapEntry<int, DVFindBlock> entry in blocks.entries) {
    final web.Element section = web.document.createElement('section')
      ..setAttribute('hidden', 'until-found')
      ..setAttribute(dvFindAnchorAttribute, 'r${entry.key}');
    section.append(
        web.document.createElement(entry.value.tag)..textContent = entry.value.text);
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
