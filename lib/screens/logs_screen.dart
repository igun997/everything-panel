import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/panel_backend.dart';
import '../state/app_state.dart';
import '../theme/brand.dart';
import '../ui/common.dart';
import '../ui/responsive.dart';
import '../ui/glass.dart';
import '../ui/motion.dart';

enum _Tab { runtime, activity }

/// Runtime logs and recorded activity (builds, deployments, starts and stops) for one service.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key, required this.session, required this.service});
  final ServerSession session;
  final ServiceInfo service;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  _Tab _tab = _Tab.runtime;

  PanelBackend? get _backend => widget.session.backend;

  // Runtime
  final _search = TextEditingController();
  List<LogLine> _lines = const [];
  bool _loadingLogs = false;
  String? _logsError;
  bool _logsUnavailable = false;
  bool _live = false;
  Timer? _timer;

  // Activity
  List<ActivityEntry> _activity = const [];
  bool _loadingActivity = false;
  String? _activityError;
  final _expanded = <String>{};
  final _entryLogs = <String, String>{};
  final _entryLoading = <String>{};

  @override
  void initState() {
    super.initState();
    _loadRuntime();
    _loadActivity();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadRuntime({bool quiet = false}) async {
    final b = _backend;
    if (b == null || _logsUnavailable) return;
    if (!quiet) setState(() => _loadingLogs = true);
    try {
      final lines = await b.runtimeLogs(widget.service, search: _search.text);
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _logsError = null;
      });
    } on LogsUnavailable catch (e) {
      if (!mounted) return;
      _timer?.cancel();
      setState(() {
        _logsUnavailable = true;
        _live = false;
        _logsError = e.message;
      });
    } on PanelException catch (e) {
      if (mounted) setState(() => _logsError = e.message);
    } finally {
      if (mounted) setState(() => _loadingLogs = false);
    }
  }

  Future<void> _loadActivity() async {
    final b = _backend;
    if (b == null) return;
    setState(() => _loadingActivity = true);
    try {
      final items = await b.activity(widget.service);
      if (mounted) {
        setState(() {
          _activity = items;
          _activityError = null;
        });
      }
    } on PanelException catch (e) {
      if (mounted) setState(() => _activityError = e.message);
    } finally {
      if (mounted) setState(() => _loadingActivity = false);
    }
  }

  void _toggleLive() {
    setState(() => _live = !_live);
    _timer?.cancel();
    if (_live) {
      _loadRuntime(quiet: true);
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _loadRuntime(quiet: true));
    }
  }

  Future<void> _toggleEntry(ActivityEntry e) async {
    if (_expanded.contains(e.id)) {
      setState(() => _expanded.remove(e.id));
      return;
    }
    setState(() => _expanded.add(e.id));
    if (!e.hasLog || _entryLogs.containsKey(e.id)) return;
    setState(() => _entryLoading.add(e.id));
    try {
      final text = await _backend!.activityLog(e.id);
      if (mounted) setState(() => _entryLogs[e.id] = text);
    } on PanelException catch (err) {
      if (mounted) setState(() => _entryLogs[e.id] = 'Could not load this log: ${err.message}');
    } finally {
      if (mounted) setState(() => _entryLoading.remove(e.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final s = widget.service;

    return AmbientBackground(
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: ContentFrame(
            maxWidth: 860,
            child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: [
                    GlassIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: () => Navigator.of(context).pop()),
                    const Spacer(),
                    if (_tab == _Tab.runtime && !_logsUnavailable) ...[
                      GlassChip(label: _live ? 'Live' : 'Go live', selected: _live, onTap: _toggleLive),
                      const SizedBox(width: 10),
                    ],
                    GlassIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Refresh',
                      busy: _tab == _Tab.runtime ? _loadingLogs : _loadingActivity,
                      onTap: () => _tab == _Tab.runtime ? _loadRuntime() : _loadActivity(),
                    ),
                  ],
                ),
              ),
              PageHeader(eyebrow: '${s.project} / ${s.kind.label}', title: s.name),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    GlassChip(label: 'Runtime', selected: _tab == _Tab.runtime, onTap: () => setState(() => _tab = _Tab.runtime)),
                    const SizedBox(width: 10),
                    GlassChip(
                      label: 'Activity',
                      count: _activity.isEmpty ? null : _activity.length,
                      selected: _tab == _Tab.activity,
                      onTap: () => setState(() => _tab = _Tab.activity),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: MaterializeSwitcher(
                  child: KeyedSubtree(
                    key: ValueKey(_tab),
                    child: _tab == _Tab.runtime ? _runtime(context, b) : _activityList(context, b),
                  ),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- runtime

  Widget _runtime(BuildContext context, BrandColors b) {
    if (_logsUnavailable) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: GlassSurface(
          radius: 28,
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.article_outlined, color: b.warning, size: 28),
              const SizedBox(height: 14),
              Text('Runtime logs are off', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(_logsError ?? '', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: b.textMuted)),
              const SizedBox(height: 18),
              GlassButton(
                label: 'See activity instead',
                icon: Icons.history_rounded,
                onPressed: () => setState(() => _tab = _Tab.activity),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: GlassSurface(
            radius: 20,
            backdrop: false,
            shadow: false,
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _loadRuntime(),
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Search these logs',
                hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(color: b.textMuted.withValues(alpha: 0.6)),
                prefixIcon: Icon(Icons.search_rounded, color: b.textMuted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        if (_logsError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(_logsError!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: b.danger)),
          ),
        Expanded(
          child: _lines.isEmpty
              ? (_loadingLogs
                  ? const Center(child: CircularProgressIndicator())
                  : EmptyArt(
                      title: 'No log lines',
                      message: _search.text.trim().isEmpty ? 'Nothing was logged recently.' : 'Nothing matches that search.',
                    ))
              : _LogView(lines: _lines),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- activity

  Widget _activityList(BuildContext context, BrandColors b) {
    if (_activityError != null && _activity.isEmpty) {
      return Center(child: EmptyArt(title: 'Could not load activity', message: _activityError!));
    }
    if (_activity.isEmpty) {
      return _loadingActivity
          ? const Center(child: CircularProgressIndicator())
          : const Center(child: EmptyArt(title: 'No activity yet', message: 'Builds, deployments, starts and stops appear here.'));
    }
    return RefreshIndicator(
      color: b.signal,
      backgroundColor: b.card,
      onRefresh: _loadActivity,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        itemCount: _activity.length,
        itemBuilder: (context, i) {
          final e = _activity[i];
          return Reveal(
            key: ValueKey(e.id),
            index: i,
            dy: 14,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ActivityTile(
                entry: e,
                expanded: _expanded.contains(e.id),
                loading: _entryLoading.contains(e.id),
                log: _entryLogs[e.id],
                onTap: () => _toggleEntry(e),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LogView extends StatelessWidget {
  const _LogView({required this.lines});
  final List<LogLine> lines;

  static String _clock(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final base = monoStyle(b.text, size: 11.5).copyWith(height: 1.45);
    final spans = <InlineSpan>[];
    for (final l in lines) {
      final lvl = (l.level ?? '').toLowerCase();
      final isErr = lvl.contains('err') || lvl.contains('fatal') || l.stream == 'stderr';
      final isWarn = lvl.contains('warn');
      if (l.time != null) spans.add(TextSpan(text: '${_clock(l.time!)}  ', style: base.copyWith(color: b.textMuted)));
      spans.add(TextSpan(
        text: '${l.message.trimRight()}\n',
        style: base.copyWith(color: isErr ? b.danger : (isWarn ? b.warning : b.text)),
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: GlassSurface(
        radius: 24,
        backdrop: false,
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            // Newest at the bottom, and the view starts there.
            ListView(
              reverse: true,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              children: [SelectableText.rich(TextSpan(children: spans))],
            ),
            Positioned(
              top: 6,
              right: 6,
              child: GlassIconButton(
                icon: Icons.copy_rounded,
                tooltip: 'Copy logs',
                onTap: () {
                  Clipboard.setData(ClipboardData(text: lines.map((l) => l.message).join('\n')));
                  showGlassToast(context, 'Logs copied');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.entry, required this.expanded, required this.loading, required this.log, required this.onTap});
  final ActivityEntry entry;
  final bool expanded;
  final bool loading;
  final String? log;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final status = entry.status.toLowerCase();
    final color = status == 'done'
        ? b.signal
        : (status.contains('fail') || status.contains('error') ? b.danger : b.warning);
    final when = entry.createdAt == null ? '' : relativeTime(entry.createdAt);

    return Pressable(
      onTap: entry.hasLog ? onTap : null,
      child: GlassSurface(
        radius: 24,
        backdrop: false,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusDot(color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.description.isEmpty ? entry.type : entry.description,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 15),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (entry.hasLog)
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    curve: const SpringCurve(damping: 1, omega: 12),
                    child: Icon(Icons.expand_more_rounded, color: b.textMuted),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Tag(entry.type),
                const SizedBox(width: 8),
                Tag(entry.status, color: color),
                const Spacer(),
                Text(when.toUpperCase(), style: monoStyle(b.textMuted, size: 10)),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 380),
              curve: const SpringCurve(damping: 1, omega: 12),
              alignment: Alignment.topCenter,
              child: !expanded
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: loading
                          ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
                          : Container(
                              width: double.infinity,
                              constraints: const BoxConstraints(maxHeight: 320),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: b.isDark ? 0.35 : 0.06),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  (log == null || log!.trim().isEmpty) ? 'This action recorded no log output.' : log!.trim(),
                                  style: monoStyle(b.text, size: 11).copyWith(height: 1.45),
                                ),
                              ),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
