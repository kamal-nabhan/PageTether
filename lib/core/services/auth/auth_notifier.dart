import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as gapis_auth;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'auth_exceptions.dart';
import 'auth_state.dart';
import 'desktop_drive_auth.dart' as desktop;
import 'google_identity_auth.dart';

/// Orchestrates Google Drive sign-in across all three platform stories
/// described in the Phase 2 plan, behind one Riverpod-facing API:
///
/// - **Desktop** (Windows/macOS/Linux): [desktop] — a plain `googleapis_auth`
///   OAuth loopback flow (`credentials.json` + a cached token file), because
///   `google_sign_in` has no Windows/Linux implementation.
/// - **Web**: [GoogleIdentityAuth] + the GIS-rendered button (see
///   `web_signin_button_web.dart`) — sign-in itself is triggered by that
///   button, not by calling [signIn] (which just no-ops there); Drive
///   authorization is then a separate explicit step via [grantDriveAccess],
///   since browsers require the consent popup to originate from a direct
///   click, not from an async event-stream callback.
/// - **Mobile** (Android/iOS): [GoogleIdentityAuth] + a normal button
///   calling [signIn] directly. Unbuilt/unverified in this phase (no
///   Android SDK/Mac available) but wired for correctness.
///
/// Every branch requests only [kDriveFileScope] scope
/// (`drive.file` — see `drive_scopes.dart`).
class AuthNotifier extends Notifier<AuthState> {
  StreamSubscription<GoogleSignInAuthenticationEvent>? _eventsSub;

  /// Set on web/mobile once signed in to a Google account — used to
  /// (re)derive a fresh Drive [http.Client] per `DriveService` call, and to
  /// request the `drive.file` scope.
  GoogleSignInAccount? _account;

  /// Set on desktop once connected — kept for the whole session (unlike
  /// web/mobile, this one auto-refreshes itself, so it's reused rather than
  /// rebuilt per call).
  gapis_auth.AutoRefreshingAuthClient? _desktopClient;

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  AuthState build() {
    ref.onDispose(() {
      unawaited(_eventsSub?.cancel());
      _desktopClient?.close();
    });
    unawaited(_bootstrap());
    return const AuthStateInitializing();
  }

  Future<void> _bootstrap() async {
    if (kIsWeb) {
      await _bootstrapWebOrMobile();
      return;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        await _bootstrapDesktop();
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        await _bootstrapWebOrMobile();
      case TargetPlatform.fuchsia:
        state = const AuthStateUnavailable(
          'Google Drive sign-in is not supported on this platform.',
        );
    }
  }

  Future<void> _bootstrapDesktop() async {
    try {
      final client = await desktop.desktopRestoreSession();
      if (client == null) {
        state = const AuthStateSignedOut();
        return;
      }
      _desktopClient = client;
      state = const AuthStateSignedIn(hasDriveAccess: true);
    } on DriveAuthUnavailableException catch (e) {
      state = AuthStateUnavailable(e.reason);
    } catch (_) {
      // A corrupt/expired cache shouldn't block startup — just fall back to
      // signed-out so the user can retry an explicit sign-in.
      state = const AuthStateSignedOut();
    }
  }

  Future<void> _bootstrapWebOrMobile() async {
    if (kIsWeb && !GoogleIdentityAuth.instance.hasWebClientId) {
      state = const AuthStateUnavailable(
        'GOOGLE_WEB_CLIENT_ID was not provided at build time. Run/build '
        'with --dart-define=GOOGLE_WEB_CLIENT_ID=<your OAuth web client id>.',
      );
      return;
    }
    try {
      await GoogleIdentityAuth.instance.ensureInitialized();
    } catch (e) {
      state = AuthStateUnavailable('Google Sign-In failed to initialize: $e');
      return;
    }

    _eventsSub ??= GoogleIdentityAuth.instance.authenticationEvents.listen(
      _handleAuthEvent,
      onError: (Object e) {
        // A failed *silent* restore (attemptLightweightAuthentication) or a
        // dismissed prompt surfaces here as `canceled` — this includes
        // FedCM's "NetworkError: Error retrieving a token" when the browser
        // simply has no session to restore. That is benign: fall back to
        // signed-out so the "Sign in with Google" button renders, instead of
        // a blocking error banner that hides it. (Matches the package's own
        // example, which treats `canceled` as no-error.)
        if (e is GoogleSignInException &&
            e.code == GoogleSignInExceptionCode.canceled) {
          state = const AuthStateSignedOut();
          return;
        }
        state = AuthStateError('$e');
      },
    );

    state = const AuthStateSignedOut();
    // Best-effort silent restore of a previous session; the result (if any)
    // arrives asynchronously via the authenticationEvents stream subscribed
    // above, not via this call's return value.
    unawaited(GoogleIdentityAuth.instance.attemptLightweightAuthentication());
  }

  Future<void> _handleAuthEvent(GoogleSignInAuthenticationEvent event) async {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn(:final user):
        _account = user;
        final hasAccess = await GoogleIdentityAuth.instance
            .hasDriveAuthorization(user);
        state = AuthStateSignedIn(
          hasDriveAccess: hasAccess,
          email: user.email,
          displayName: user.displayName,
          photoUrl: user.photoUrl,
        );
      case GoogleSignInAuthenticationEventSignOut():
        _account = null;
        state = const AuthStateSignedOut();
    }
  }

  /// Explicit "Connect Google Drive" action for desktop and mobile. On web
  /// this is a no-op — the UI instead renders the GIS button directly (see
  /// `drive_auth_panel.dart`), since sign-in there can't be triggered
  /// programmatically.
  Future<void> signIn() async {
    if (state is AuthStateUnavailable || kIsWeb) return;
    if (_isDesktop) {
      await _signInDesktop();
    } else {
      await _signInMobile();
    }
  }

  Future<void> _signInDesktop() async {
    state = const AuthStateSigningIn();
    try {
      final client = await desktop.desktopSignIn(
        onConsentUrl: (url) {
          unawaited(launchUrl(url, mode: LaunchMode.externalApplication));
        },
      );
      _desktopClient = client;
      state = const AuthStateSignedIn(hasDriveAccess: true);
    } on DriveAuthUnavailableException catch (e) {
      state = AuthStateUnavailable(e.reason);
    } catch (e) {
      state = AuthStateError('Could not connect to Google Drive: $e');
    }
  }

  Future<void> _signInMobile() async {
    state = const AuthStateSigningIn();
    try {
      final account = await GoogleIdentityAuth.instance
          .authenticateInteractively();
      if (account == null) {
        state = const AuthStateSignedOut(); // user cancelled
        return;
      }
      _account = account;
      await GoogleIdentityAuth.instance.authorizeDriveAccess(account);
      state = AuthStateSignedIn(
        hasDriveAccess: true,
        email: account.email,
        displayName: account.displayName,
        photoUrl: account.photoUrl,
      );
    } catch (e) {
      state = AuthStateError('Could not connect to Google Drive: $e');
    }
  }

  /// Web-only second step: the user is signed in to a Google account (via
  /// the rendered GIS button) but hasn't granted the `drive.file` scope
  /// yet ([AuthStateSignedIn.hasDriveAccess] is false). Must be called
  /// directly from a button's `onPressed` — a real user gesture — since the
  /// browser may otherwise block the consent popup.
  Future<void> grantDriveAccess() async {
    final account = _account;
    final current = state;
    if (account == null || current is! AuthStateSignedIn) return;
    try {
      await GoogleIdentityAuth.instance.authorizeDriveAccess(account);
      state = current.copyWith(hasDriveAccess: true);
    } catch (e) {
      state = AuthStateError('Could not authorize Google Drive access: $e');
    }
  }

  Future<void> signOut() async {
    try {
      if (_isDesktop) {
        await desktop.desktopSignOut();
        _desktopClient?.close();
        _desktopClient = null;
      } else {
        await GoogleIdentityAuth.instance.signOut();
        _account = null;
      }
    } catch (_) {
      // Sign-out should never leave the user stuck — fall through to
      // signed-out regardless of whether the underlying call succeeded.
    }
    state = const AuthStateSignedOut();
  }

  /// An authenticated [http.Client] for `googleapis`'s `DriveApi`. Only
  /// meaningful when [state] is [AuthStateSignedIn] with `hasDriveAccess:
  /// true` — UI actions that call this should already be gated on that, so
  /// this should not normally throw in practice.
  Future<http.Client> requireAuthClient() async {
    if (_isDesktop) {
      final client = _desktopClient;
      if (client == null) {
        throw const DriveAuthUnavailableException(
          'Not connected to Google Drive.',
        );
      }
      return client;
    }
    final account = _account;
    if (account == null) {
      throw const DriveAuthUnavailableException(
        'Not connected to Google Drive.',
      );
    }
    // Re-derived per call rather than cached — see
    // `GoogleIdentityAuth.authorizeDriveAccess` for why.
    return GoogleIdentityAuth.instance.authorizeDriveAccess(account);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
