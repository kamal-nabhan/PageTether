import 'package:flutter/foundation.dart';

/// State of the Google Drive connection, surfaced by `authProvider`
/// (see `auth_notifier.dart`) and rendered by the sidebar/UI.
///
/// This is intentionally a small sealed hierarchy (rather than one class
/// with nullable fields) so the UI can exhaustively `switch` on it and never
/// render an inconsistent combination (e.g. "signed in" with an error
/// message still showing).
@immutable
sealed class AuthState {
  const AuthState();
}

/// Nothing has happened yet / the user has never connected Drive. This is
/// also the state right after a successful sign-out.
class AuthStateSignedOut extends AuthState {
  const AuthStateSignedOut();
}

/// Brief state while `main()`'s startup silently checks for an existing
/// desktop token cache / web-mobile lightweight session. Never triggers a
/// user-facing consent prompt — just avoids flashing "signed out" for a
/// frame before an existing session is restored.
class AuthStateInitializing extends AuthState {
  const AuthStateInitializing();
}

/// A sign-in (and, on desktop, the loopback consent flow) is in progress.
class AuthStateSigningIn extends AuthState {
  const AuthStateSigningIn();
}

/// Signed in to a Google account. [hasDriveAccess] is false only on the
/// web two-step flow, between "signed in to Google" and "granted the
/// drive.file scope" — see `web_signin_button_web.dart` for why those are
/// separate steps on web. [email]/[displayName]/[photoUrl] are available on
/// web/mobile via `google_sign_in`'s basic profile; on desktop, [email] is
/// populated once the loopback flow's `openid`/`userinfo.email` scopes
/// resolve an identity (see `desktop_drive_auth_io.dart`) and stays null
/// otherwise (e.g. a session cached before that scope existed) — desktop
/// never has [displayName]/[photoUrl], since only the email scope is
/// requested there.
///
/// [syncUserId]/[syncEmail] are the identity Phase 4's Supabase sync keys
/// rows by — set together with [email] and non-null exactly when sync is
/// available. [syncUserId] prefers Google's stable `sub`/account id (the
/// `GoogleSignInAccount.id` on web/mobile, the userinfo `sub` on desktop),
/// falling back to [syncEmail] if only the email could be resolved.
class AuthStateSignedIn extends AuthState {
  const AuthStateSignedIn({
    required this.hasDriveAccess,
    this.email,
    this.displayName,
    this.photoUrl,
    this.syncUserId,
  });

  final bool hasDriveAccess;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String? syncUserId;

  /// Alias for [email] under the name Phase 4's sync code reasons about —
  /// currently always the same value, but kept distinct so call sites that
  /// care about "is sync identity available" read that way rather than
  /// implicitly reusing the Drive-account-chip field.
  String? get syncEmail => email;

  /// True once both halves of a usable sync identity are known.
  bool get canSync => syncUserId != null;

  AuthStateSignedIn copyWith({
    bool? hasDriveAccess,
    String? email,
    String? displayName,
    String? photoUrl,
    String? syncUserId,
  }) {
    return AuthStateSignedIn(
      hasDriveAccess: hasDriveAccess ?? this.hasDriveAccess,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      syncUserId: syncUserId ?? this.syncUserId,
    );
  }
}

/// Drive sign-in can't work on this platform/build right now — missing
/// `credentials.json` (desktop) or `GOOGLE_WEB_CLIENT_ID` (web), or running
/// on a platform with no auth backend at all (Fuchsia). [reason] is a short,
/// user-actionable sentence shown directly in the UI.
class AuthStateUnavailable extends AuthState {
  const AuthStateUnavailable(this.reason);
  final String reason;
}

/// Sign-in or authorization failed for a reason other than the user simply
/// cancelling the consent screen (cancellation just returns to
/// [AuthStateSignedOut] without an error).
class AuthStateError extends AuthState {
  const AuthStateError(this.message);
  final String message;
}
