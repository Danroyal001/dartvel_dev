/// Each image's laid-out width, where `dartvel build web`'s capture can read
/// it.
///
/// The capture sees which image a page fetched and cannot see how wide it
/// was drawn: a request for the 384-wide variant says only that the slot was
/// somewhere between 257 and 384 pixels. The link prefetch needs the slot
/// itself, to pick the variant for a denser screen than the one the build ran
/// on, so the widget writes it down as it lays out.
library dartvel_flutter.media.image_layout.web;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// A plain object on the page, from an image's address to the widest it was
/// laid out, in logical pixels. Read by the capture as JSON.
const String _global = '__dartvelImages';

/// Records that [src] was laid out [width] logical pixels wide.
void dvRecordImageLayout(String src, double width) {
  final JSObject page = globalContext;
  JSObject? images = page.getProperty<JSObject?>(_global.toJS);
  if (images == null) {
    images = JSObject();
    page.setProperty(_global.toJS, images);
  }
  final JSNumber? before = images.getProperty<JSNumber?>(src.toJS);
  // The widest, because the same image in two slots needs the larger variant
  // for the page to paint both from one download.
  if (before == null || before.toDartDouble < width) {
    images.setProperty(src.toJS, width.toJS);
  }
}
