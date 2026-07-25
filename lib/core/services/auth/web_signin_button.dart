// Conditional export: picks the real Google Identity Services button widget
// on web builds and a no-op stub everywhere else, since `google_sign_in_web`
// uses browser JS interop that cannot be compiled in for native (VM/AOT)
// targets. Mirrors `core/services/fullscreen/web_fullscreen.dart`.
export 'web_signin_button_stub.dart'
    if (dart.library.html) 'web_signin_button_web.dart';
