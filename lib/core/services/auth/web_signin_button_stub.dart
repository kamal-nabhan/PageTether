// Fallback used on every non-web target. See `web_signin_button.dart` for
// the conditional export that picks between this file and
// `web_signin_button_web.dart`. Desktop/mobile use an ordinary button that
// calls `AuthNotifier.signIn()` directly instead — see
// `drive_auth_panel.dart` — so this widget is never actually shown; it only
// needs to exist so the import compiles.
import 'package:flutter/widgets.dart';

Widget buildGoogleSignInButton() => const SizedBox.shrink();
