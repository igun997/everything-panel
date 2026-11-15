import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../state/scope.dart';
import '../theme/brand.dart';
import '../ui/common.dart';
import '../ui/glass.dart';
import '../ui/motion.dart';
import 'add_server_screen.dart';
import 'service_sheet.dart';

enum _Filter { all, running, stopped }

IconData kindIcon(ServiceKind k) => switch (k) {
      ServiceKind.app => Icons.rocket_launch_rounded,
      ServiceKind.compose => Icons.view_in_ar_rounded,
      ServiceKind.box => Icons.inventory_2_rounded,
      ServiceKind.wordpress => Icons.language_rounded,
      ServiceKind.redis => Icons.bolt_rounded,
      ServiceKind.other => Icons.dns_rounded,
      _ => Icons.storage_rounded,
    };

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;

  /// Folded project groups, per server, so switching servers keeps each one's folds.
  final _collapsed = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([context.app, _search]),
      builder: (context, _) {
        final app = context.app;
        final session = app.active;
        final b = context.brand;

        if (session == null) {
          return Column(
            children: [
              const PageHeader(eyebrow: 'No server', title: 'Services'),
              Expanded(
                child: Center(
                  child: EmptyArt(
                    title: 'Nothing to show',
                    message: 'Add a server to list its apps, databases and stacks.',
                    action: SizedBox(
                      width: 220,
                      child: GlassButton(
                        label: 'Add a server',
                        style: GlassButtonStyle.primary,
                        onPressed: () => Navigator.of(context).push(FluidRoute<void>(builder: (_) => const AddServerScreen())),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final q = _search.text.trim().toLowerCase();
        final searching = q.isNotEmpty;
        final all = session.services;
        bool matches(ServiceInfo s) =>
            q.isEmpty || s.name.toLowerCase().contains(q) || s.project.toLowerCase().contains(q) || s.kind.label.toLowerCase().contains(q);
        final searched = all.where(matches).toList();
        final shown = searched.where((s) {
          return switch (_filter) {
            _Filter.all => true,
            _Filter.running => s.isRunning,
            _Filter.stopped => !s.isRunning,
          };
        }).toList();

        final byProject = <String, List<ServiceInfo>>{};
        for (final s in shown) {
          byProject.putIfAbsent(s.project, () => []).add(s);
        }
        final projects = byProject.keys.toList()..sort();
        for (final list in byProject.values) {
          list.sort((a, c) => a.name.compareTo(c.name));
        }

        String foldKey(String project) => '${session.profile.id}/$project';
        final allFolded = projects.isNotEmpty && projects.every((p) => _collapsed.contains(foldKey(p)));

        return RefreshIndicator(
          color: b.signal,
          backgroundColor: b.card,
          onRefresh: () => app.refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: PageHeader(
                  eyebrow: session.profile.name,
                  title: 'Services',
                  trailing: GlassIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Refresh',
                    busy: session.loading,
                    onTap: () => app.refresh(),
                  ),
                ),
              ),
              if (app.sessions.length > 1)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      children: [
                        for (final s in app.sessions)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: GlassChip(
                              label: s.profile.name,
                              selected: s.profile.id == session.profile.id,
                              onTap: () => app.select(s.profile.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              // Search and filters stay pinned while the list scrolls under them.
              SliverPersistentHeader(
                pinned: true,
                delegate: PinnedBar(
                  extent: 124,
                  background: b.page,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                        child: GlassSurface(
                          radius: 22,
                          backdrop: false,
                          shadow: false,
                          child: TextField(
                            controller: _search,
                            textInputAction: TextInputAction.search,
                            style: Theme.of(context).textTheme.bodyLarge,
                            decoration: InputDecoration(
                              hintText: 'Search services',
                              hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(color: b.textMuted.withValues(alpha: 0.6)),
                              prefixIcon: Icon(Icons.search_rounded, color: b.textMuted),
                              suffixIcon: !searching
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear',
                                      icon: Icon(Icons.close_rounded, color: b.textMuted),
                                      onPressed: _search.clear,
                                    ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 46,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          children: [
                            GlassChip(
                              label: 'All',
                              count: searched.length,
                              selected: _filter == _Filter.all,
                              onTap: () => setState(() => _filter = _Filter.all),
                            ),
                            const SizedBox(width: 10),
                            GlassChip(
                              label: 'Running',
                              count: searched.where((s) => s.isRunning).length,
                              selected: _filter == _Filter.running,
                              onTap: () => setState(() => _filter = _Filter.running),
                            ),
                            const SizedBox(width: 10),
                            GlassChip(
                              label: 'Stopped',
                              count: searched.where((s) => !s.isRunning).length,
                              selected: _filter == _Filter.stopped,
                              onTap: () => setState(() => _filter = _Filter.stopped),
                            ),
                            if (projects.length > 1 && !searching) ...[
                              const SizedBox(width: 10),
                              GlassChip(
                                label: allFolded ? 'Unfold all' : 'Fold all',
                                selected: false,
                                onTap: () => setState(() {
                                  for (final p in projects) {
                                    allFolded ? _collapsed.remove(foldKey(p)) : _collapsed.add(foldKey(p));
                                  }
                                }),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (session.error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: GlassSurface(
                      radius: 22,
                      backdrop: false,
                      shadow: false,
                      tint: b.danger.withValues(alpha: 0.12),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_off_rounded, color: b.danger, size: 20),
                          const SizedBox(width: 12),
                          Expanded(child: Text(session.error!, style: Theme.of(context).textTheme.bodyMedium)),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!session.loadedOnce && session.error == null)
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
                )
              else if (projects.isEmpty)
                SliverToBoxAdapter(
                  child: EmptyArt(
                    title: !searching && _filter == _Filter.all ? 'No services yet' : 'No matches',
                    message: !searching && _filter == _Filter.all
                        ? 'Create an app or database in your panel and it will appear here.'
                        : 'Try a different search or filter.',
                  ),
                )
              else
                SliverList.builder(
                  itemCount: projects.length,
                  itemBuilder: (context, i) {
                    final project = projects[i];
                    final items = byProject[project]!;
                    // A search shows every match, even inside a folded group.
                    final folded = !searching && _collapsed.contains(foldKey(project));
                    return Reveal(
                      key: ValueKey('${session.profile.id}/$project'),
                      index: i,
                      child: _ProjectGroup(
                        project: project,
                        items: items,
                        session: session,
                        folded: folded,
                        canFold: !searching,
                        onToggle: () => setState(() {
                          final k = foldKey(project);
                          _collapsed.contains(k) ? _collapsed.remove(k) : _collapsed.add(k);
                        }),
                      ),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: kNavClearance)),
            ],
          ),
        );
      },
    );
  }
}

class _ProjectGroup extends StatelessWidget {
  const _ProjectGroup({
    required this.project,
    required this.items,
    required this.session,
    required this.folded,
    required this.canFold,
    required this.onToggle,
  });
  final String project;
  final List<ServiceInfo> items;
  final ServerSession session;
  final bool folded;
  final bool canFold;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final running = items.where((s) => s.isRunning).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Pressable(
          onTap: canFold ? onToggle : null,
          scale: 0.985,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 14, 26, 10),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: folded ? -0.25 : 0,
                  duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 380),
                  curve: const SpringCurve(damping: 0.85, omega: 13),
                  child: Icon(Icons.expand_more_rounded, size: 20, color: b.textMuted),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(project.toUpperCase(), style: monoStyle(b.textMuted, size: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Text('$running/${items.length}', style: monoStyle(running == items.length ? b.signal : b.textMuted, size: 11)),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 420),
          curve: const SpringCurve(damping: 1, omega: 12),
          alignment: Alignment.topCenter,
          child: folded
              ? const SizedBox(width: double.infinity)
              : Column(
                  children: [
                    for (final svc in items)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        child: _ServiceTile(session: session, service: svc),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.session, required this.service});
  final ServerSession session;
  final ServiceInfo service;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final u = service.usage;
    final running = service.isRunning;
    // Databases: state is not reported reliably by every provider, so stay neutral.
    final neutral = service.kind.isDatabase && !running;
    final color = running ? b.signal : (neutral ? b.textMuted : b.warning);

    return Pressable(
      onTap: () => showServiceSheet(context, session, service),
      child: GlassSurface(
        radius: 26,
        blur: 18,
        backdrop: false,
        padding: const EdgeInsets.fromLTRB(16, 16, 18, 16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                color: color.withValues(alpha: 0.13),
              ),
              child: Icon(kindIcon(service.kind), color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(service.name, style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Tag(service.kind.label),
                      if (u != null) ...[
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'CPU ${u.cpuPercent.toStringAsFixed(1)}%  MEM ${u.memPercent.toStringAsFixed(1)}%',
                            style: monoStyle(b.textMuted, size: 10.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Breathe(active: running, child: StatusDot(color: color)),
          ],
        ),
      ),
    );
  }
}
