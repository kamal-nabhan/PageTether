// Fallback used on every non-web target. See `web_fullscreen.dart` for the
// conditional export that picks between this file and
// `web_fullscreen_web.dart`.
Future<void> requestWebFullscreen() async {}

Future<void> exitWebFullscreen() async {}

bool get isWebFullscreenActive => false;
