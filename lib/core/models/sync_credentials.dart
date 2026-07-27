import 'package:flutter/foundation.dart';

/// The user's own ("BYOD") Supabase project connection details, pasted into
/// the Settings screen and persisted locally via
/// `LibraryStore.loadSyncCredentials`/`saveSyncCredentials`.
///
/// Deliberately just a URL + anon (publishable) key — never a service-role
/// key, and never bundled at build time — see `core/services/sync/sync_engine.dart`
/// for why the `SupabaseClient` is built from these at runtime rather than
/// via `supabase_flutter`'s compile-time `Supabase.initialize` singleton.
@immutable
class SyncCredentials {
  const SyncCredentials({required this.url, required this.anonKey});

  static const empty = SyncCredentials(url: '', anonKey: '');

  final String url;
  final String anonKey;

  /// True once both fields hold something non-blank. Doesn't validate the
  /// URL's shape or that the key is actually valid — that's what
  /// `SyncEngine.testConnection` is for.
  bool get isConfigured => url.trim().isNotEmpty && anonKey.trim().isNotEmpty;

  SyncCredentials copyWith({String? url, String? anonKey}) => SyncCredentials(
    url: url ?? this.url,
    anonKey: anonKey ?? this.anonKey,
  );

  Map<String, dynamic> toJson() => {'url': url, 'anonKey': anonKey};

  factory SyncCredentials.fromJson(Map<String, dynamic> json) =>
      SyncCredentials(
        url: json['url'] as String? ?? '',
        anonKey: json['anonKey'] as String? ?? '',
      );
}
