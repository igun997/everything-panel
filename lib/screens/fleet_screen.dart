import 'package:material_ui/material_ui.dart';

import '../data/providers.dart';
import '../ui/responsive.dart';
import '../state/app_state.dart';
import '../state/scope.dart';
import '../theme/brand.dart';
import '../ui/common.dart';
import '../ui/glass.dart';
import '../ui/motion.dart';
import 'add_server_screen.dart';

/// All connected servers, across every provider, at a glance.
class FleetScreen extends StatelessWidget {
  const FleetScreen({super.key, required this.onOpenServices});
  final VoidCallback onOpenServices;

  void _add(BuildContext context) =>
      Navigator.of(context).push(FluidRoute<void>(builder: (_) => const AddServerScreen()));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: context.app,
      builder: (context, _) {
        final app = context.app;
        final sessions = app.sessions;
        final anyLoading = sessions.any((s) => s.loading);

        return RefreshIndicator(
          color: context.brand.signal,
          backgroundColor: context.brand.card,
          onRefresh: () => app.refreshAll(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: PageHeader(
                  eyebrow: 'everything-panel',
                  title: 'Fleet',
                  trailing: GlassIconButton(
                    icon: Icons.add_rounded,
                    tooltip: 'Add server',
                    onTap: () => _add(context),
                    busy: anyLoading,
                  ),
                ),
              ),
              if (sessions.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: EmptyArt(
                      title: 'No servers yet',
                      message: 'Connect an Easypanel server to see its services and health here.',
                      action: SizedBox(
                        width: 240,
                        child: GlassButton(
                          label: 'Add a server',
                          icon: Icons.add_rounded,
                          style: GlassButtonStyle.primary,
                          onPressed: () => _add(context),
                        ),
                      ),
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(child: Reveal(index: 0, child: _Summary(sessions: sessions))),
                // Wide windows pair the cards up; narrow ones stack them.
                SliverList.builder(
                  itemCount: context.isWide ? (sessions.length + 1) ~/ 2 : sessions.length,
                  itemBuilder: (context, row) {
                    final cols = context.isWide ? 2 : 1;
                    Widget card(int i) => Reveal(
                          key: ValueKey(sessions[i].profile.id),
                          index: i + 1,
                          child: _ServerCard(
                            session: sessions[i],
                            selected: app.active?.profile.id == sessions[i].profile.id,
                            onTap: () async {
                              await app.select(sessions[i].profile.id);
                              onOpenServices();
                            },
                          ),
                        );
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var c = 0; c < cols; c++) ...[
                            if (c > 0) const SizedBox(width: 14),
                            Expanded(
                              child: row * cols + c < sessions.length ? card(row * cols + c) : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                SliverToBoxAdapter(
                  child: Reveal(
                    index: sessions.length + 1,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      child: _AddTile(onTap: () => _add(context)),
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: kNavClearance)),
            ],
          ),
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.sessions});
  final List<ServerSession> sessions;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final running = sessions.fold<int>(0, (a, s) => a + s.running);
    final total = sessions.fold<int>(0, (a, s) => a + s.total);
    final down = sessions.fold<int>(0, (a, s) => a + s.down.length);
    final healthy = down == 0 && sessions.every((s) => s.error == null);

    Widget stat(String label, double v, {Color? color}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CountUp(value: v, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: color)),
              const SizedBox(height: 2),
              Text(label.toUpperCase(), style: monoStyle(b.textMuted, size: 10)),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: GlassSurface(
        radius: 32,
        blur: 30,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Breathe(active: healthy, child: StatusDot(color: healthy ? b.signal : b.warning, size: 10)),
                const SizedBox(width: 10),
                Text(
                  healthy ? 'All systems running' : (down > 0 ? '$down need attention' : 'Some servers unreachable'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                stat('Servers', sessions.length.toDouble()),
                stat('Running', running.toDouble(), color: b.signal),
                stat('Services', total.toDouble()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.session, required this.selected, required this.onTap});
  final ServerSession session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final s = session;
    final spec = specFor(s.profile.kind);
    final stats = s.stats;
    final ok = s.error == null && s.loadedOnce;
    final host = Uri.tryParse(s.profile.url.contains('://') ? s.profile.url : 'https://${s.profile.url}')?.host ?? s.profile.url;

    return Pressable(
      onTap: onTap,
      child: GlassSurface(
        radius: 30,
        blur: 22,
        selected: selected,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: b.signal.withValues(alpha: 0.14),
                    border: Border.all(color: b.signal.withValues(alpha: 0.3)),
                  ),
                  child: Icon(spec.icon, color: b.signal, size: 23),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.profile.name, style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(host, style: monoStyle(b.textMuted, size: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Tag(spec.name),
                const SizedBox(width: 10),
                Breathe(
                  active: ok,
                  child: StatusDot(color: s.error != null ? b.danger : (ok ? b.signal : b.textMuted), size: 10),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (s.error != null)
              Text(s.error!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: b.danger))
            else if (!s.loadedOnce)
              Text('Connecting...', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: b.textMuted))
            else ...[
              Row(
                children: [
                  CountUp(value: s.running.toDouble(), style: Theme.of(context).textTheme.titleLarge?.copyWith(color: b.signal)),
                  Text(' / ${s.total} running', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: b.textMuted)),
                  const Spacer(),
                  if (s.down.isNotEmpty) Tag('${s.down.length} stopped', color: b.warning),
                ],
              ),
              if (stats != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: UsageBar(label: 'CPU', percent: stats.cpuPercent)),
                    const SizedBox(width: 18),
                    Expanded(child: UsageBar(label: 'Memory', percent: stats.memPercent)),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Pressable(
      onTap: onTap,
      child: GlassSurface(
        radius: 26,
        backdrop: false,
        shadow: false,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: b.signal, size: 22),
            const SizedBox(width: 10),
            Text('Add another server', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: b.signal, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
