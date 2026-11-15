import 'package:material_ui/material_ui.dart';

import '../data/providers.dart';
import '../state/scope.dart';
import '../theme/brand.dart';
import '../ui/common.dart';
import '../ui/glass.dart';
import '../ui/motion.dart';
import 'add_server_screen.dart';
import 'sync_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([context.app, context.auth, context.push]),
      builder: (context, _) {
        final b = context.brand;
        final app = context.app;
        final auth = context.auth;
        final push = context.push;
        final theme = Theme.of(context);

        Widget section(String title) => Padding(
              padding: const EdgeInsets.fromLTRB(30, 18, 24, 10),
              child: Text(title.toUpperCase(), style: monoStyle(b.textMuted, size: 11)),
            );

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: kNavClearance),
          children: [
            const PageHeader(eyebrow: 'everything-panel', title: 'Settings'),

            // Account
            Reveal(
              index: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GlassSurface(
                  radius: 30,
                  blur: 26,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: b.signal.withValues(alpha: 0.16),
                            backgroundImage: auth.user?.photoURL == null ? null : NetworkImage(auth.user!.photoURL!),
                            child: auth.user?.photoURL == null ? Icon(Icons.person_rounded, color: b.signal) : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(auth.user?.displayName ?? (auth.user != null ? 'Google account' : 'Not signed in'),
                                    style: theme.textTheme.titleMedium),
                                const SizedBox(height: 2),
                                Text(
                                  auth.user?.email ??
                                      (auth.available ? 'Optional. Sync alerts across devices.' : 'Google sign-in is not configured in this build.'),
                                  style: theme.textTheme.bodySmall?.copyWith(color: b.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (auth.user == null)
                        GlassButton(
                          label: 'Sign in with Google',
                          icon: Icons.account_circle_rounded,
                          loading: auth.busy,
                          onPressed: auth.available
                              ? () async {
                                  final ok = await auth.signInWithGoogle();
                                  if (!context.mounted) return;
                                  if (!ok && auth.error != null) showGlassToast(context, auth.error!, error: true);
                                }
                              : null,
                        )
                      else
                        GlassButton(label: 'Sign out', onPressed: auth.signOut),
                    ],
                  ),
                ),
              ),
            ),

            // Encrypted sync (only meaningful with a Google account)
            section('Sync'),
            const Reveal(
              index: 1,
              child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SyncCard()),
            ),

            // Alerts
            section('Alerts'),
            Reveal(
              index: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GlassSurface(
                  radius: 30,
                  blur: 22,
                  padding: const EdgeInsets.fromLTRB(20, 16, 14, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Service down alerts', style: theme.textTheme.titleMedium),
                                const SizedBox(height: 3),
                                Text(
                                  'Notify me when something I was watching stops running.',
                                  style: theme.textTheme.bodySmall?.copyWith(color: b.textMuted),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: app.alertsEnabled,
                            activeThumbColor: Brand.ink,
                            activeTrackColor: b.signal,
                            onChanged: (on) async {
                              if (on) {
                                final granted = await push.enable();
                                if (!context.mounted) return;
                                if (!granted) {
                                  showGlassToast(context, 'Notifications are blocked. Allow them in system settings.', error: true);
                                  return;
                                }
                                if (auth.user != null) await push.subscribe('user-${auth.user!.uid}');
                              }
                              await app.setAlerts(on);
                            },
                          ),
                        ],
                      ),
                      if (app.alertsEnabled) ...[
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GlassButton(
                            label: 'Send a test alert',
                            icon: Icons.notifications_active_rounded,
                            onPressed: () => push.show('everything-panel', 'Alerts are working.'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          push.firebaseReady
                              ? 'Remote push is ready. ${push.registrationId == null ? 'Turn alerts on to register this device.' : 'This device is registered.'}'
                              : 'Alerts fire while the app is open. Remote push turns on once this build has its Firebase config.',
                          style: monoStyle(b.textMuted, size: 10.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Servers
            section('Servers'),
            for (var i = 0; i < app.sessions.length; i++)
              Reveal(
                key: ValueKey(app.sessions[i].profile.id),
                index: i + 2,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: GlassSurface(
                    radius: 26,
                    backdrop: false,
                    padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                    child: Row(
                      children: [
                        Icon(specFor(app.sessions[i].profile.kind).icon, color: b.signal, size: 22),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(app.sessions[i].profile.name, style: theme.textTheme.titleMedium),
                              Text(app.sessions[i].profile.url, style: monoStyle(b.textMuted, size: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove server',
                          icon: Icon(Icons.delete_outline_rounded, color: b.danger),
                          onPressed: () => _confirmRemove(context, i),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Reveal(
              index: app.sessions.length + 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GlassButton(
                  label: 'Add a server',
                  icon: Icons.add_rounded,
                  onPressed: () => Navigator.of(context).push(FluidRoute<void>(builder: (_) => const AddServerScreen())),
                ),
              ),
            ),

            // About
            section('About'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GlassSurface(
                radius: 30,
                backdrop: false,
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.asset('assets/images/logo.webp', height: 54, alignment: Alignment.centerLeft, fit: BoxFit.contain),
                    const SizedBox(height: 14),
                    Text(
                      'Freeware. Servers and tokens live on this device. If you turn on encrypted sync they are also stored, sealed with your passphrase, in your own Google account. There is no everything-panel server.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: b.textMuted),
                    ),
                    const SizedBox(height: 12),
                    Text('BY PT CIPTA DUA SAUDARA  -  CIPTADUSA.COM', style: monoStyle(b.signal, size: 10.5)),
                    const SizedBox(height: 4),
                    Text('v0.1.0', style: monoStyle(b.textMuted, size: 10.5)),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmRemove(BuildContext context, int i) async {
    final app = context.app;
    final p = app.sessions[i].profile;
    final b = context.brand;
    final ok = await showDialog<bool>(
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
              Text('Remove ${p.name}?', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(
                'Its saved token is deleted from this phone. Your server is not touched.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: b.textMuted),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(child: GlassButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false))),
                  const SizedBox(width: 12),
                  Expanded(child: GlassButton(label: 'Remove', style: GlassButtonStyle.danger, onPressed: () => Navigator.pop(ctx, true))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) await app.removeServer(p);
  }
}
