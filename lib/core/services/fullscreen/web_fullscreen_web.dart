// Only ever compiled for web targets (see the conditional export in
// `web_fullscreen.dart`) — uses the browser's Fullscreen API on the
// document's root element via `package:web` + `dart:js_interop`.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> requestWebFullscreen() async {
  final element = web.document.documentElement;
  if (element == null) return;
  try {
    await element.requestFullscreen().toDart;
  } catch (_) {
    // The Fullscreen API can reject (no user gesture, embedded iframe
    // without `allowfullscreen`, etc.) — the in-app immersive mode still
    // applies either way, so this is safe to ignore.
  }
}

Future<void> exitWebFullscreen() async {
  if (web.document.fullscreenElement == null) return;
  try {
    await web.document.exitFullscreen().toDart;
  } catch (_) {}
}

bool get isWebFullscreenActive => web.document.fullscreenElement != null;
