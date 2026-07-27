import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as gapis_auth;

import 'drive_scopes.dart';

/// Web OAuth client id, supplied at build/run time via
/// `--dart-define=GOOGLE_WEB_CLIENT_ID=...`. Empty when not provided — the
/// app must still *compile* without it (this is a compile-time constant
/// that just resolves to `''`), and callers must treat an empty value as
/// "web sign-in unavailable" at runtime rather than handing it to the SDK.
const String kGoogleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

/// Thin wrapper around `google_sign_in` v7's singleton API, shared by the
/// web and mobile auth backends (see `auth_notifier.dart`).
///
/// Desktop (Windows/macOS/Linux) does *not* use this: `google_sign_in` has
/// no federated implementation for Windows/Linux, so desktop goes through
/// `desktop_drive_auth_io.dart` (a plain `googleapis_auth` loopback flow)
/// instead. This class is still safe to compile on every platform — the
/// `google_sign_in` app-facing package is pure platform-interface
/// indirection with no unconditional `dart:io`/`dart:html` imports of its
/// own — it's just never *called* outside web/mobile (see
/// `auth_notifier.dart`'s platform switch).
class GoogleIdentityAuth {
  GoogleIdentityAuth._();

  static final GoogleIdentityAuth instance = GoogleIdentityAuth._();

  GoogleSignIn get _signIn => GoogleSignIn.instance;

  Future<void>? _initFuture;

  /// Initializes the underlying SDK exactly once per app run. On web this
  /// must be given the OAuth web client id; on mobile it relies on native
  /// platform config (`google-services.json` / `GoogleService-Info.plist`)
  /// that this repo does not currently ship, so `clientId` is left null
  /// there — mobile sign-in is wired for correctness but unverified.
  Future<void> ensureInitialized() {
    final webClientId = kGoogleWebClientId.isNotEmpty ? kGoogleWebClientId : null;
    return _initFuture ??= _signIn.initialize(
      // Web uses the OAuth *Web* client id as `clientId`; Android/iOS require
      // that same Web client id as `serverClientId` (each platform's own
      // sign-in is bound via its Android/iOS OAuth client + SHA-1 / bundle id).
      clientId: kIsWeb ? webClientId : null,
      serverClientId: kIsWeb ? null : webClientId,
    );
  }

  /// True when a web client id was supplied at build time. Only meaningful
  /// on web — mobile doesn't need one.
  bool get hasWebClientId => kGoogleWebClientId.isNotEmpty;

  Stream<GoogleSignInAuthenticationEvent> get authenticationEvents =>
      _signIn.authenticationEvents;

  /// True on platforms where `authenticateInteractively` can be triggered
  /// from any ordinary button (mobile, desktop-with-native-support). False
  /// on web, which instead requires the GIS-rendered button — see
  /// `web_signin_button_web.dart`.
  bool get supportsAuthenticate => _signIn.supportsAuthenticate();

  /// Silently restores a previous session, if any, without prompting the
  /// user. Safe to call unconditionally at startup on web/mobile — results
  /// (if any) arrive via [authenticationEvents], not the return value.
  Future<void> attemptLightweightAuthentication() async {
    await ensureInitialized();
    try {
      await _signIn.attemptLightweightAuthentication();
    } catch (_) {
      // Best-effort silent restore: a missing session or (mis)configuration
      // must never crash startup — the user can still sign in explicitly.
    }
  }

  /// Mobile-only interactive sign-in. Returns null if the user cancelled
  /// the consent screen (not treated as an error).
  Future<GoogleSignInAccount?> authenticateInteractively() async {
    await ensureInitialized();
    try {
      return await _signIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  /// Requests (or silently reuses a previously granted) `drive.file`
  /// authorization for [account], then wraps it in a `googleapis`-compatible
  /// [gapis_auth.AuthClient]. Per the plugin's own documented pattern, this
  /// re-derives the client from the account each time rather than caching
  /// one for the whole session, since `authClient()` bakes in an arbitrary
  /// long expiry (the SDK doesn't expose the real one) instead of actually
  /// auto-refreshing — see `auth_notifier.dart` for how callers use this.
  ///
  /// On web, [authorizeScopes] opens a Google consent popup and therefore
  /// must be called synchronously from a user gesture, or the browser's
  /// popup blocker may swallow it — see `web_signin_button_web.dart`.
  Future<gapis_auth.AuthClient> authorizeDriveAccess(
    GoogleSignInAccount account,
  ) async {
    const scopes = [kDriveFileScope];
    final authorizationClient = account.authorizationClient;
    final authorization =
        await authorizationClient.authorizationForScopes(scopes) ??
        await authorizationClient.authorizeScopes(scopes);
    return authorization.authClient(scopes: scopes);
  }

  /// True if [account] already holds `drive.file` authorization without
  /// needing to show a consent popup.
  Future<bool> hasDriveAuthorization(GoogleSignInAccount account) async {
    final authorization = await account.authorizationClient
        .authorizationForScopes(const [kDriveFileScope]);
    return authorization != null;
  }

  Future<void> signOut() async {
    await ensureInitialized();
    await _signIn.signOut();
  }
}
