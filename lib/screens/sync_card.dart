import 'package:material_ui/material_ui.dart';

import '../state/scope.dart';
import '../state/sync_controller.dart';
import '../theme/brand.dart';
import '../ui/common.dart';
import '../ui/glass.dart';

/// Settings card for optional end-to-end encrypted sync.
class SyncCard extends StatelessWidget {
  const SyncCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([context.sync, context.app]),
      builder: (context, _) {
        final sync = context.sync;
        final b = context.brand;
        final theme = Theme.of(context);

        final (IconData icon, String title, String body) = switch (sync.state) {
          SyncState.off => (Icons.lock_outline_rounded, 'Encrypted sync', 'Sign in with Google to keep your servers on all your devices.'),
          SyncState.checking => (Icons.sync_rounded, 'Encrypted sync', 'Checking your vault...'),
          SyncState.needsSetup => (
              Icons.enhanced_encryption_rounded,
              'Encrypted sync',
              'Back up your servers to your own Google account. They are encrypted on this phone with a passphrase only you know.'
            ),
          SyncState.locked => (Icons.lock_rounded, 'Vault locked', 'Enter your passphrase to restore your servers on this device.'),
          SyncState.unlocked => (
              Icons.verified_user_rounded,
              'Synced and encrypted',
              '${context.app.sessions.length} server${context.app.sessions.length == 1 ? '' : 's'}  -  last sync ${relativeTime(sync.lastSync)}'
            ),
          SyncState.error => (Icons.cloud_off_rounded, 'Encrypted sync', sync.error ?? 'Could not reach the sync service.'),
        };

        final accent = sync.state == SyncState.error ? b.danger : b.signal;

        return GlassSurface(
          radius: 30,
          blur: 22,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      color: accent.withValues(alpha: 0.14),
                    ),
                    child: Icon(icon, color: accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 3),
                        Text(body, style: theme.textTheme.bodySmall?.copyWith(color: b.textMuted, height: 1.35)),
                      ],
                    ),
                  ),
                ],
              ),
              if (sync.state == SyncState.needsSetup) ...[
                const SizedBox(height: 16),
                GlassButton(
                  label: 'Set up encrypted sync',
                  icon: Icons.enhanced_encryption_rounded,
                  style: GlassButtonStyle.primary,
                  onPressed: () => _setup(context),
                ),
              ],
              if (sync.state == SyncState.locked) ...[
                const SizedBox(height: 16),
                GlassButton(
                  label: 'Unlock',
                  icon: Icons.lock_open_rounded,
                  style: GlassButtonStyle.primary,
                  onPressed: () => _unlock(context),
                ),
              ],
              if (sync.state == SyncState.error) ...[
                const SizedBox(height: 16),
                GlassButton(label: 'Try again', icon: Icons.refresh_rounded, onPressed: sync.refreshStatus),
              ],
              if (sync.state == SyncState.unlocked) ...[
                const SizedBox(height: 16),
                GlassButton(
                  label: 'Sync now',
                  icon: Icons.sync_rounded,
                  loading: sync.busy,
                  onPressed: () async {
                    final err = await sync.sync();
                    if (context.mounted && err != null) showGlassToast(context, err, error: true);
                  },
                ),
                const SizedBox(height: 10),
                GlassButton(label: 'Lock this device', icon: Icons.lock_rounded, onPressed: sync.lock),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => _reset(context),
                    child: Text('Delete cloud copy', style: TextStyle(color: b.danger)),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                'Tokens are sealed with AES-256-GCM before they leave your phone. Google only stores ciphertext, and nobody can recover a forgotten passphrase.',
                style: monoStyle(b.textMuted, size: 10),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _setup(BuildContext context) async {
    final sync = context.sync;
    final ok = await showPassphraseDialog(
      context,
      title: 'Choose a sync passphrase',
      message:
          'You will enter it once on each device. If you forget it, the cloud copy cannot be recovered, only deleted and recreated.',
      confirmLabel: 'Encrypt and sync',
      confirm: true,
      onSubmit: sync.setup,
    );
    if (ok == true && context.mounted) showGlassToast(context, 'Encrypted sync is on');
  }

  Future<void> _unlock(BuildContext context) async {
    final sync = context.sync;
    final ok = await showPassphraseDialog(
      context,
      title: 'Unlock your vault',
      message: 'Enter the passphrase you chose when you set up encrypted sync.',
      confirmLabel: 'Unlock',
      onSubmit: sync.unlock,
    );
    if (ok == true && context.mounted) showGlassToast(context, 'Servers restored');
  }

  Future<void> _reset(BuildContext context) async {
    final sync = context.sync;
    final b = context.brand;
    final yes = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: GlassSurface(
          radius: 32,
          blur: 40,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Delete the cloud copy?', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(
                'Your encrypted vault is removed from your Google account. Servers on this phone stay.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: b.textMuted),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(child: GlassButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false))),
                  const SizedBox(width: 12),
                  Expanded(child: GlassButton(label: 'Delete', style: GlassButtonStyle.danger, onPressed: () => Navigator.pop(ctx, true))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (yes != true) return;
    final err = await sync.resetCloud();
    if (context.mounted) showGlassToast(context, err ?? 'Cloud copy deleted', error: err != null);
  }
}

/// Passphrase prompt as a bottom sheet, so the keyboard never covers the fields:
/// the sheet lifts above it and scrolls if the screen is short. Stays open and shows
/// the message when [onSubmit] returns one.
Future<bool?> showPassphraseDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required Future<String?> Function(String passphrase) onSubmit,
  bool confirm = false,
}) {
  return showGlassSheet<bool>(
    context,
    (_) => _PassphraseForm(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      onSubmit: onSubmit,
      confirm: confirm,
    ),
    dismissible: false,
  );
}

class _PassphraseForm extends StatefulWidget {
  const _PassphraseForm({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onSubmit,
    required this.confirm,
  });
  final String title;
  final String message;
  final String confirmLabel;
  final Future<String?> Function(String) onSubmit;
  final bool confirm;

  @override
  State<_PassphraseForm> createState() => _PassphraseFormState();
}

class _PassphraseFormState extends State<_PassphraseForm> {
  final _pass = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _pass.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    if (widget.confirm && _pass.text != _again.text) {
      setState(() => _error = 'The two passphrases differ.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onSubmit(_pass.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(widget.message, style: theme.textTheme.bodyMedium?.copyWith(color: b.textMuted)),
          const SizedBox(height: 20),
          GlassField(
            controller: _pass,
            label: 'Passphrase',
            obscure: !_show,
            textInputAction: widget.confirm ? TextInputAction.next : TextInputAction.done,
            onSubmitted: widget.confirm ? null : (_) => _go(),
            suffix: IconButton(
              tooltip: _show ? 'Hide' : 'Show',
              icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: b.textMuted),
              onPressed: () => setState(() => _show = !_show),
            ),
          ),
          if (widget.confirm) ...[
            const SizedBox(height: 14),
            GlassField(
              controller: _again,
              label: 'Repeat passphrase',
              obscure: !_show,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _go(),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                'At least ${SyncController.minPassphraseLength} characters. A few random words work well.',
                style: monoStyle(b.textMuted, size: 10),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, color: b.danger, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: b.danger))),
              ],
            ),
          ],
          const SizedBox(height: 22),
          GlassButton(
            label: widget.confirmLabel,
            style: GlassButtonStyle.primary,
            loading: _busy,
            onPressed: _go,
          ),
          const SizedBox(height: 10),
          GlassButton(label: 'Cancel', onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
        ],
      ),
    );
  }
}
