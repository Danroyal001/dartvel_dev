import 'package:puppeteer/puppeteer.dart' show Page;

/// Requests presentation while waiting for the application's raster signal.
///
/// Headless Chrome can leave a frame unpresented until capture requests a
/// readback. Waiting for its raster notification before requesting any capture
/// then deadlocks. A capture drives presentation; only [ready] admits the frame,
/// and puppeteer's original [timeout] still bounds that notification.
Future<void> dvWaitForWebRaster(
  Page page, {
  required String ready,
  required Duration timeout,
}) async {
  bool waiting = true;
  Future<void> present() async {
    while (waiting) {
      await page.screenshot();
      if (waiting) {
        await Future<void>.delayed(const .new(milliseconds: 100));
      }
    }
  }

  final presenting = present();
  try {
    await Future.any<void>([
      page.waitForFunction(ready, timeout: timeout).then((_) {}),
      presenting,
    ]);
  } finally {
    waiting = false;
    await presenting;
  }
}
