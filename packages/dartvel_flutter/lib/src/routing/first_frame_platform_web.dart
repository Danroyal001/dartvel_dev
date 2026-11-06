import 'package:web/web.dart' as web;

void dvPublishFirstFrame() {
  web.window.dispatchEvent(web.Event('dartvel-first-frame'));
}
