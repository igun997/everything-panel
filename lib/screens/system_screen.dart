import 'package:material_ui/material_ui.dart';

import '../state/scope.dart';
import '../theme/brand.dart';
import '../ui/common.dart';
import '../ui/glass.dart';
import '../ui/motion.dart';

class SystemScreen extends StatelessWidget {
  const SystemScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: context.app,
      builder: (context, _) {
        final app = context.app;
        final session = app.active;
        final b = context.brand;
        final st = session?.stats;

        return RefreshIndicator(
          color: b.signal,
          backgroundColor: b.card,
          onRefresh: () => app.refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: PageHeader(
                  eyebrow: session?.profile.name ?? 'No server',
                  title: 'System',
                  trailing: session == null
                      ? null
                      : Text('UPDATED ${relativeTime(session.lastUpdated).toUpperCase()}', style: monoStyle(b.textMuted, size: 10)),
                ),
              ),
              if (session == null || st == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: EmptyArt(
                      title: session == null ? 'No server selected' : (session.error ?? 'No system stats'),
                      message: session == null
                          ? 'Add a server to see CPU, memory and disk.'
                          : 'This panel did not return host metrics. Pull down to retry.',
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Reveal(
                    index: 0,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      child: GlassSurface(
                        radius: 32,
                        blur: 30,
                        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            RingGauge(percent: st.cpuPercent, label: 'CPU', value: '${st.cpuCores} cores', size: 92),
                            RingGauge(
                              percent: st.memPercent,
                              label: 'Memory',
                              value: '${(st.memUsedMb / 1024).toStringAsFixed(1)} / ${(st.memTotalMb / 1024).toStringAsFixed(1)} GB',
                              size: 92,
                            ),
                            RingGauge(
                              percent: st.diskPercent,
                              label: 'Disk',
                              value: '${st.diskUsedGb.toStringAsFixed(0)} / ${st.diskTotalGb.toStringAsFixed(0)} GB',
                              size: 92,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: Reveal(
                      index: 1,
                      child: Row(
                        children: [
                          Expanded(child: _Metric(icon: Icons.schedule_rounded, label: 'Uptime', value: formatUptime(st.uptime))),
                          const SizedBox(width: 10),
                          Expanded(child: _Metric(icon: Icons.south_west_rounded, label: 'Net in', value: _mb(st.netInMb))),
                          const SizedBox(width: 10),
                          Expanded(child: _Metric(icon: Icons.north_east_rounded, label: 'Net out', value: _mb(st.netOutMb))),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: Reveal(
                      index: 2,
                      child: _Metric(
                        icon: Icons.speed_rounded,
                        label: 'Load average  1 / 5 / 15 min',
                        value: st.load.isEmpty ? '-' : st.load.take(3).map((l) => l.toStringAsFixed(2)).join('   '),
                        wide: true,
                      ),
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

/// 1536 MB reads better as 1.5 GB.
String _mb(double mb) => mb >= 1024 ? '${(mb / 1024).toStringAsFixed(1)} GB' : '${mb.toStringAsFixed(1)} MB';

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value, this.wide = false});
  final IconData icon;
  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: wide ? 20 : 16)),
    );
    return GlassSurface(
      radius: 24,
      blur: 18,
      backdrop: false,
      padding: EdgeInsets.all(wide ? 18 : 14),
      child: wide
          ? Row(
              children: [
                Icon(icon, color: b.signal, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      text,
                      const SizedBox(height: 3),
                      Text(label.toUpperCase(), style: monoStyle(b.textMuted, size: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: b.signal, size: 18),
                const SizedBox(height: 10),
                text,
                const SizedBox(height: 3),
                Text(label.toUpperCase(), style: monoStyle(b.textMuted, size: 9.5), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
    );
  }
}
