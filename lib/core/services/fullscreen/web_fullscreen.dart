// Conditional export: picks the real browser Fullscreen API implementation
// on web builds and a no-op stub everywhere else, since `dart:js_interop`
// cannot be compiled in for native (VM/AOT) targets.
export 'web_fullscreen_stub.dart' if (dart.library.html) 'web_fullscreen_web.dart';
