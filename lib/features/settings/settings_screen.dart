import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/auth/auth_notifier.dart';
import '../../core/services/auth/auth_state.dart';
import '../../core/theme/app_theme.dart';
import 'settings_providers.dart';

/// BYOD Supabase sync setup: paste a project URL + anon key, test the
/// connection, and trigger a manual "Sync now" — see the Phase 4a plan.
/// Reachable from the library (desktop sidebar icon / mobile app bar
/// action — see `library_sidebar.dart`/`library_screen.dart`).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _anonKeyController;
  bool _obscureAnonKey = true;

  @override
  void initState() {
    super.initState();
    final credentials = ref.read(syncCredentialsProvider);
    _urlController = TextEditingController(text: credentials.url);
    _anonKeyController = TextEditingController(text: credentials.anonKey);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _anonKeyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref
        .read(syncCredentialsProvider.notifier)
        .save(_urlController.text, _anonKeyController.text);
    ref.read(syncConnectionProvider.notifier).reset();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved. Try "Test connection" next.')),
    );
  }

  Future<void> _disconnect() async {
    await ref.read(syncCredentialsProvider.notifier).clear();
    _urlController.clear();
    _anonKeyController.clear();
    ref.read(syncConnectionProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Sync identity', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const _SyncIdentityCard(),
          const SizedBox(height: 8),
          const _AutoSyncStatusLine(),
          const SizedBox(height: 32),
          Text(
            'Your Supabase project',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'PageTether syncs to a Supabase project you create and own — '
            'paste its URL and anon (public) key below. Run schema.sql '
            '(in the repo root) in that project\'s SQL Editor first.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Supabase URL',
              hintText: 'https://xxxxxxxx.supabase.co',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _anonKeyController,
            decoration: InputDecoration(
              labelText: 'Anon (public) key',
              hintText: 'eyJhbGciOi...',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureAnonKey
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscureAnonKey = !_obscureAnonKey),
              ),
            ),
            obscureText: _obscureAnonKey,
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton(onPressed: _save, child: const Text('Save')),
              const SizedBox(width: 12),
              const _TestConnectionButton(),
              const Spacer(),
              TextButton(
                onPressed: _disconnect,
                child: const Text('Disconnect'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _ConnectionStatusRow(),
          const SizedBox(height: 32),
          Text('Sync now', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Pushes this device\'s books and collections to Supabase, then '
            'pulls in whatever changed on other devices (last edit wins).',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          const _SyncNowSection(),
        ],
      ),
    );
  }
}

class _SyncIdentityCard extends ConsumerWidget {
  const _SyncIdentityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final (icon, color, text) = switch (authState) {
      AuthStateSignedIn(canSync: true, :final syncEmail) => (
        Icons.cloud_done_rounded,
        AppColors.accentTeal,
        'Syncing as $syncEmail',
      ),
      AuthStateSignedIn(canSync: false) => (
        Icons.cloud_off_rounded,
        AppColors.textSecondary,
        'Signed in to Google Drive, but no sync identity was resolved yet. '
            'Disconnect and reconnect Google (from the library) to enable sync.',
      ),
      _ => (
        Icons.cloud_off_rounded,
        AppColors.textSecondary,
        'Sign in to Google (from the library) to enable sync.',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Subtle Phase 4b background-sync indicator — the Settings-screen twin of
/// `library_sidebar.dart`'s `_AutoSyncStatusRow`, reading the same
/// [autoSyncStatusProvider] so this reflects automatic syncs too, not just
/// explicit "Sync now" presses (that's still [_SyncNowSection] below, an
/// intentionally separate, more detailed/dismissible state machine — see
/// `AutoSyncStatus`'s class doc for why the two are kept apart).
class _AutoSyncStatusLine extends ConsumerWidget {
  const _AutoSyncStatusLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(autoSyncStatusProvider);
    final (IconData, String)? display = switch (status) {
      AutoSyncIdle() => null,
      AutoSyncSyncing() => (Icons.sync_rounded, 'Background sync: syncing…'),
      AutoSyncSynced(:final at) => (
        Icons.cloud_done_rounded,
        'Background sync: synced · ${formatSyncAge(at)}',
      ),
      AutoSyncFailed() => (
        Icons.cloud_off_rounded,
        'Background sync paused — will retry automatically',
      ),
    };
    if (display == null) return const SizedBox.shrink();
    final (icon, label) = display;

    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _TestConnectionButton extends ConsumerWidget {
  const _TestConnectionButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final testing = ref.watch(syncConnectionProvider) is SyncConnectionTesting;
    return OutlinedButton(
      onPressed: testing
          ? null
          : () => ref.read(syncConnectionProvider.notifier).test(),
      child: testing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Test connection'),
    );
  }
}

class _ConnectionStatusRow extends ConsumerWidget {
  const _ConnectionStatusRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncConnectionProvider);
    final (icon, color, label) = switch (state) {
      SyncConnectionUnknown() => (
        Icons.help_outline_rounded,
        AppColors.textSecondary,
        'Not tested yet',
      ),
      SyncConnectionTesting() => (
        Icons.cloud_sync_rounded,
        AppColors.textSecondary,
        'Testing…',
      ),
      SyncConnectionNotConfigured() => (
        Icons.info_outline_rounded,
        AppColors.textSecondary,
        'Not configured — add a URL and anon key above',
      ),
      SyncConnectionOk() => (
        Icons.check_circle_rounded,
        AppColors.accentTeal,
        'Connected',
      ),
      SyncConnectionFailed(:final message) => (
        Icons.error_outline_rounded,
        const Color(0xFFEF4444),
        'Error: $message',
      ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _SyncNowSection extends ConsumerWidget {
  const _SyncNowSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncRunProvider);
    final busy = state is SyncRunInProgress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: busy
              ? null
              : () => ref.read(syncRunProvider.notifier).syncNow(),
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync_rounded),
          label: Text(state is SyncRunInProgress ? state.message : 'Sync now'),
        ),
        const SizedBox(height: 12),
        switch (state) {
          SyncRunIdle() || SyncRunInProgress() => const SizedBox.shrink(),
          SyncRunSuccess(:final summary) => _ResultBanner(
            icon: Icons.check_circle_rounded,
            color: AppColors.accentTeal,
            message: summary,
            onDismiss: () => ref.read(syncRunProvider.notifier).dismiss(),
          ),
          SyncRunError(:final message) => _ResultBanner(
            icon: Icons.error_outline_rounded,
            color: const Color(0xFFEF4444),
            message: message,
            onDismiss: () => ref.read(syncRunProvider.notifier).dismiss(),
          ),
        },
      ],
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({
    required this.icon,
    required this.color,
    required this.message,
    required this.onDismiss,
  });

  final IconData icon;
  final Color color;
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16),
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
