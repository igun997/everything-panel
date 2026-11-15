import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../state/scope.dart';
import '../theme/brand.dart';
import '../ui/common.dart';
import '../ui/glass.dart';
import '../ui/motion.dart';
import 'logs_screen.dart';
import 'services_screen.dart' show kindIcon;

Future<void> showServiceSheet(BuildContext context, ServerSession session, ServiceInfo service) {
  return showGlassSheet<void>(context, (_) => _ServiceSheet(session: session, serviceKey: service.key, initial: service));
}

class _ServiceSheet extends StatefulWidget {
  const _ServiceSheet({required this.session, required this.serviceKey, required this.initial});
  final ServerSession session;
  final String serviceKey;
  final ServiceInfo initial;

  @override
  State<_ServiceSheet> createState() => _ServiceSheetState();
}

class _ServiceSheetState extends State<_ServiceSheet> {
  ServiceAction? _busy;

  Future<bool> _confirm(ServiceAction a, ServiceInfo s) async {
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
              Text('${a.label} ${s.name}?', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(
                switch (a) {
                  ServiceAction.stop => 'It will go offline until you start it again.',
                  ServiceAction.restart => 'It will be briefly unavailable while it restarts.',
                  ServiceAction.deploy => 'This redeploys from its source and may take a few minutes.',
                  ServiceAction.start => '',
                },
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: b.textMuted),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(child: GlassButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassButton(
                      label: a.label,
                      style: a == ServiceAction.stop ? GlassButtonStyle.danger : GlassButtonStyle.primary,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return ok ?? false;
  }

  Future<void> _run(ServiceAction a, ServiceInfo s) async {
    if (a.isDisruptive && !await _confirm(a, s)) return;
    if (!mounted) return;
    final app = context.app;
    final messenger = Navigator.of(context);
    setState(() => _busy = a);
    try {
      await app.perform(widget.session, s, a);
      if (!mounted) return;
      messenger.pop();
      if (messenger.context.mounted) showGlassToast(messenger.context, '${s.name}: ${a.label.toLowerCase()} requested');
    } on PanelException catch (e) {
      if (mounted) showGlassToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: context.app,
      builder: (context, _) {
        final b = context.brand;
        final s = widget.session.services.where((x) => x.key == widget.serviceKey).firstOrNull ?? widget.initial;
        final u = s.usage;
        final running = s.isRunning;
        final canControl = s.kind.canControl;
        final color = running ? b.signal : b.warning;

        final actions = <ServiceAction>[
          if (canControl && !running) ServiceAction.start,
          if (canControl && running) ServiceAction.restart,
          if (canControl && running) ServiceAction.stop,
          if (s.kind.canDeploy) ServiceAction.deploy,
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: color.withValues(alpha: 0.14),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Icon(kindIcon(s.kind), color: color, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 26), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(s.project.toUpperCase(), style: monoStyle(b.textMuted, size: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Tag(s.kind.label),
                  const SizedBox(width: 8),
                  Tag(
                    running ? 'Running' : (s.kind.isDatabase ? 'No stats' : 'Stopped'),
                    color: running ? b.signal : (s.kind.isDatabase ? b.textMuted : b.warning),
                  ),
                  if (u != null && u.containers > 1) ...[
                    const SizedBox(width: 8),
                    Tag('${u.containers} replicas'),
                  ],
                ],
              ),
              if (u != null) ...[
                const SizedBox(height: 24),
                Reveal(index: 0, dy: 10, child: UsageBar(label: 'CPU', percent: u.cpuPercent)),
                const SizedBox(height: 16),
                Reveal(index: 1, dy: 10, child: UsageBar(label: 'Memory', percent: u.memPercent)),
              ],
              const SizedBox(height: 26),
              GlassButton(
                label: 'Logs and activity',
                icon: Icons.article_rounded,
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(FluidRoute<void>(builder: (_) => LogsScreen(session: widget.session, service: s)));
                },
              ),
              const SizedBox(height: 10),
              if (actions.isEmpty)
                Text(
                  s.kind.isDatabase
                      ? 'Databases are view-only here. Manage them from the panel.'
                      : 'No actions available for this service.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: b.textMuted),
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < actions.length; i++)
                      Reveal(
                        index: i,
                        dy: 14,
                        step: 50,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassButton(
                            label: actions[i].label,
                            icon: switch (actions[i]) {
                              ServiceAction.start => Icons.play_arrow_rounded,
                              ServiceAction.stop => Icons.stop_rounded,
                              ServiceAction.restart => Icons.restart_alt_rounded,
                              ServiceAction.deploy => Icons.cloud_upload_rounded,
                            },
                            style: switch (actions[i]) {
                              ServiceAction.start => GlassButtonStyle.primary,
                              ServiceAction.stop => GlassButtonStyle.danger,
                              _ => GlassButtonStyle.glass,
                            },
                            loading: _busy == actions[i],
                            onPressed: _busy == null ? () => _run(actions[i], s) : null,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
