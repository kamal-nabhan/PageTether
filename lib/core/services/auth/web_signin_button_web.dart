// Only ever compiled for web targets (see the conditional export in
// `web_signin_button.dart`).
//
// Google Identity Services does not allow a custom "Sign in with Google"
// button on web — it must render its own button so it can attach a secure,
// first-party click handler (see the `google_sign_in_web` package README).
// The resulting sign-in is picked up via `GoogleIdentityAuth.
// authenticationEvents` in `auth_notifier.dart`, not a return value here.
import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

Widget buildGoogleSignInButton() => web.renderButton();
