import 'package:material_ui/material_ui.dart';

import '../data/openapi.dart';
import '../state/scope.dart';
import '../theme/brand.dart';
import '../ui/common.dart';
import '../ui/glass.dart';
import '../ui/motion.dart';
import 'add_server_screen.dart';
import 'api_operation_screen.dart';

/// Every operation the panel's API documents, grouped by area. This is the complete
/// surface of the API; the other tabs are shortcuts to its most common parts.
class ApiExplorerScreen extends StatefulWidget {
  const ApiExplorerScreen({super.key});

  @override
  State<ApiExplorerScreen> createState() => _ApiExplorerScreenState();
}

class _ApiExplorerScreenState extends State<ApiExplorerScreen> {
  final _search = TextEditingController();
  // Areas are folded until opened; there are dozens of them.
  final _open = <String>{};

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

        final backend = session?.backend;
        if (session == null || backend is! ApiExplorerBackend) {
          return Column(
            children: [
              PageHeader(eyebrow: session?.profile.name ?? 'No server', title: 'API'),
              Expanded(
                child: Center(
                  child: EmptyArt(
                    title: session == null ? 'No server selected' : 'Not available',
                    message: session == null
                        ? 'Add a server to browse and run its API.'
                        : 'This provider does not expose an API explorer yet.',
                    action: session != null
                        ? null
                        : SizedBox(
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

        final catalog = (backend as ApiExplorerBackend).catalog;
        final q = _search.text.trim().toLowerCase();
        final searching = q.isNotEmpty;

        bool matches(ApiOperation o) =>
            !searching || o.id.toLowerCase().contains(q) || o.summary.toLowerCase().contains(q) || o.tag.toLowerCase().contains(q);

        final tags = [
          for (final t in catalog.tags)
            if (catalog.byTag[t]!.any(matches)) t,
        ];

        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(
              child: PageHeader(
                eyebrow: '${session.profile.name}  -  v${catalog.version}',
                title: 'API',
                trailing: Tag('${catalog.operations.length} operations', color: b.signal),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: PinnedBar(
                extent: 78,
                background: b.page,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: GlassSurface(
                    radius: 22,
                    backdrop: false,
                    shadow: false,
                    child: TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      style: Theme.of(context).textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: 'Search ${catalog.operations.length} operations',
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
              ),
            ),
            if (tags.isEmpty)
              const SliverToBoxAdapter(child: EmptyArt(title: 'No matches', message: 'Try another word, like "backup" or "domain".'))
            else
              SliverList.builder(
                itemCount: tags.length,
                itemBuilder: (context, i) {
                  final tag = tags[i];
                  final ops = catalog.byTag[tag]!.where(matches).toList();
                  final open = searching || _open.contains(tag);
                  return _TagGroup(
                    key: ValueKey('tag.$tag'),
                    tag: tag,
                    ops: ops,
                    open: open,
                    canFold: !searching,
                    onToggle: () => setState(() => _open.contains(tag) ? _open.remove(tag) : _open.add(tag)),
                    onOpenOp: (op) => Navigator.of(context).push(
                      FluidRoute<void>(builder: (_) => ApiOperationScreen(session: session, operation: op)),
                    ),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: kNavClearance)),
          ],
        );
      },
    );
  }
}

class _TagGroup extends StatelessWidget {
  const _TagGroup({
    super.key,
    required this.tag,
    required this.ops,
    required this.open,
    required this.canFold,
    required this.onToggle,
    required this.onOpenOp,
  });
  final String tag;
  final List<ApiOperation> ops;
  final bool open;
  final bool canFold;
  final VoidCallback onToggle;
  final void Function(ApiOperation) onOpenOp;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final reduce = MediaQuery.disableAnimationsOf(context);
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
                  turns: open ? 0 : -0.25,
                  duration: reduce ? Duration.zero : const Duration(milliseconds: 380),
                  curve: const SpringCurve(damping: 0.85, omega: 13),
                  child: Icon(Icons.expand_more_rounded, size: 20, color: b.textMuted),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(tag.toUpperCase(), style: monoStyle(b.textMuted, size: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text('${ops.length}', style: monoStyle(b.textMuted, size: 11)),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 420),
          curve: const SpringCurve(damping: 1, omega: 12),
          alignment: Alignment.topCenter,
          child: !open
              ? const SizedBox(width: double.infinity)
              : Column(
                  children: [
                    for (final op in ops)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: _OpTile(op: op, onTap: () => onOpenOp(op)),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _OpTile extends StatelessWidget {
  const _OpTile({required this.op, required this.onTap});
  final ApiOperation op;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final color = switch (op.risk) {
      ApiRisk.read => b.signal,
      ApiRisk.change => b.warning,
      ApiRisk.danger => b.danger,
    };
    return Pressable(
      onTap: onTap,
      child: GlassSurface(
        radius: 22,
        backdrop: false,
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(
          children: [
            Tag(op.method, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(op.id, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (op.summary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(op.summary, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: b.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: b.textMuted),
          ],
        ),
      ),
    );
  }
}
