/// Thrown by a platform auth backend when Drive sign-in cannot proceed at
/// all right now — e.g. `credentials.json` is missing on desktop, or
/// `GOOGLE_WEB_CLIENT_ID` wasn't supplied on web. Caught by `AuthNotifier`
/// (see `auth_notifier.dart`) and surfaced as `AuthStateUnavailable` with
/// [reason] shown directly to the user, so it should always be a short,
/// actionable sentence rather than a raw stack trace.
class DriveAuthUnavailableException implements Exception {
  const DriveAuthUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}
