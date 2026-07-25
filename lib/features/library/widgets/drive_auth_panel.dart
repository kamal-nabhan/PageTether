import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/auth/auth_notifier.dart';
import '../../../core/services/auth/auth_state.dart';
import '../../../core/services/auth/web_signin_button.dart';
import '../../../core/theme/app_theme.dart';
import '../library_providers.dart';

/// Google Drive connect/account panel, reused as-is in both the desktop
/// sidebar (`library_sidebar.dart`) and a mobile bottom sheet
/// (`library_screen.dart`) — see the Phase 2 plan's "reachable on mobile"
/// requirement.
///
/// Renders one of six mutually-exclusive rows depending on [AuthState]:
/// initializing, signed-out (connect prompt), signing in, signed in
/// (account chip + disconnect), signed in but Drive access not yet granted
/// (web-only second step), or an error with retry. Never shows more than
/// one at once, since [AuthState] is a sealed hierarchy the switch below
/// exhausts.
class DriveAuthPanel extends ConsumerWidget {
  const DriveAuthPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authProvider);

    return switch (state) {
      AuthStateInitializing() => const _StatusRow(
        icon: Icons.cloud_sync_rounded,
        label: 'Checking Drive connection…',
        showSpinner: true,
      ),
      AuthStateSignedOut() => const _ConnectPrompt(),
      AuthStateSigningIn() => const _StatusRow(
        icon: Icons.cloud_sync_rounded,
        label: 'Connecting to Google Drive…',
        showSpinner: true,
      ),
      AuthStateSignedIn(
        hasDriveAccess: true,
        :final email,
        :final displayName,
      ) =>
        _ConnectedRow(email: email, displayName: displayName),
      AuthStateSignedIn(hasDriveAccess: false) => const _GrantAccessRow(),
      AuthStateUnavailable(:final reason) => _StatusRow(
        icon: Icons.cloud_off_rounded,
        label: reason,
      ),
      AuthStateError(:final message) => _ErrorRow(message: message),
    };
  }
}

class _ConnectPrompt extends ConsumerWidget {
  const _ConnectPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Google Identity Services doesn't allow a custom button on web — it
    // must render its own (see `web_signin_button_web.dart`). Desktop and
    // mobile use an ordinary button that calls `signIn()` directly.
    final trigger = kIsWeb
        ? buildGoogleSignInButton()
        : SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => ref.read(authProvider.notifier).signIn(),
              icon: const Icon(Icons.add_to_drive_rounded, size: 18),
              label: const Text('Connect Google Drive'),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Not connected',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        trigger,
      ],
    );
  }
}

class _GrantAccessRow extends ConsumerWidget {
  const _GrantAccessRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Signed in — Drive access needed',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => ref.read(authProvider.notifier).grantDriveAccess(),
          icon: const Icon(Icons.lock_open_rounded, size: 18),
          label: const Text('Grant Drive access'),
        ),
      ],
    );
  }
}

class _ConnectedRow extends ConsumerWidget {
  const _ConnectedRow({this.email, this.displayName});

  final String? email;
  final String? displayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = displayName ?? email ?? 'Google Drive connected';
    // Manual reconcile-with-Drive action (see `hydrateFromDrive` in
    // `library_providers.dart`) — reachable from both the desktop sidebar
    // and the mobile Drive bottom sheet, since both embed this panel.
    // Naturally hidden while signed out (this row only renders once
    // `hasDriveAccess` is true) and disabled while a Drive sync is already
    // in flight, rather than queuing a redundant second one.
    final syncState = ref.watch(driveSyncProvider);
    final isSyncing = syncState is DriveSyncLoading;
    return Row(
      children: [
        const Icon(
          Icons.cloud_done_rounded,
          color: AppColors.accentTeal,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        IconButton(
          tooltip: 'Refresh Drive library',
          icon: isSyncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 18),
          onPressed: isSyncing
              ? null
              : () => ref.read(libraryProvider.notifier).hydrateFromDrive(),
        ),
        IconButton(
          tooltip: 'Disconnect Google Drive',
          icon: const Icon(Icons.logout_rounded, size: 18),
          onPressed: () => ref.read(authProvider.notifier).signOut(),
        ),
      ],
    );
  }
}

class _ErrorRow extends ConsumerWidget {
  const _ErrorRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFEF4444),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => ref.read(authProvider.notifier).signIn(),
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

/// "Upload to Drive" action — only rendered once signed in with Drive
/// access granted; hidden entirely otherwise, so it never shows an action
/// the user can't currently use. Placed right below [DriveAuthPanel] in
/// both the desktop sidebar (`library_sidebar.dart`) and the mobile Drive
/// bottom sheet (`library_screen.dart`).
class DriveUploadButton extends ConsumerWidget {
  const DriveUploadButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    if (authState is! AuthStateSignedIn || !authState.hasDriveAccess) {
      return const SizedBox.shrink();
    }

    final progress = ref.watch(driveTransferProgressProvider);
    final busy = progress != null;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => ref.read(libraryProvider.notifier).uploadPickedPdfToDrive(),
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: Text(
              busy ? 'Uploading… ${(progress * 100).round()}%' : 'Upload to Drive',
            ),
          ),
          if (busy) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress, minHeight: 4),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    this.showSpinner = false,
  });

  final IconData icon;
  final String label;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSpinner)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}
