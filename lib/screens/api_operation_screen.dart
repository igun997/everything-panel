import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/openapi.dart';
import '../state/app_state.dart';
import '../theme/brand.dart';
import '../ui/common.dart';
import '../ui/glass.dart';
import '../ui/responsive.dart';

/// Form and result for one documented API operation. The form is generated from the
/// operation's schema, so every operation Easypanel documents can be run from here.
class ApiOperationScreen extends StatefulWidget {
  const ApiOperationScreen({super.key, required this.session, required this.operation});
  final ServerSession session;
  final ApiOperation operation;

  @override
  State<ApiOperationScreen> createState() => _ApiOperationScreenState();
}

class _ApiOperationScreenState extends State<ApiOperationScreen> {
  final _text = <String, TextEditingController>{};
  final _bools = <String, bool>{};
  final _enums = <String, String?>{};
  final _errors = <String, String>{};

  bool _running = false;
  Object? _result;
  String? _error;
  bool _hasResult = false;

  ApiOperation get op => widget.operation;

  @override
  void initState() {
    super.initState();
    for (final f in op.fields) {
      final d = f.defaultValue;
      if (f.enumValues != null) {
        _enums[f.name] = d == null ? null : '$d';
      } else if (f.type == 'boolean') {
        _bools[f.name] = d == true;
      } else {
        _text[f.name] = TextEditingController(text: d == null ? '' : (d is Map || d is List ? jsonEncode(d) : '$d'));
      }
    }
    // Reads need no confirmation and are safe to run on open when nothing is required.
    if (op.isRead && op.fields.every((f) => !f.required)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run(confirm: false));
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _isJsonField(ApiField f) {
    final t = f.type;
    if (t == 'object') return true;
    if (t == 'array') {
      final it = (f.schema['items'] as Map?)?['type'];
      return it != 'string' && it != 'number' && it != 'integer';
    }
    return t == null;
  }

  /// Turns what was typed into typed values, or records a message per bad field.
  Map<String, Object?>? _collect() {
    _errors.clear();
    final out = <String, Object?>{};
    for (final f in op.fields) {
      Object? value;
      if (f.enumValues != null) {
        value = _enums[f.name];
      } else if (f.type == 'boolean') {
        value = _bools[f.name];
      } else {
        final raw = _text[f.name]!.text.trim();
        if (raw.isEmpty) {
          if (f.required) _errors[f.name] = 'Required';
          continue;
        }
        try {
          if (_isJsonField(f)) {
            value = jsonDecode(raw);
          } else if (f.type == 'array') {
            final numeric = ((f.schema['items'] as Map?)?['type']) != 'string';
            value = [
              for (final p in raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty))
                numeric ? num.parse(p) : p,
            ];
          } else if (f.type == 'integer') {
            value = int.parse(raw);
          } else if (f.type == 'number') {
            value = num.parse(raw);
          } else {
            value = raw;
          }
        } on FormatException {
          _errors[f.name] = switch (f.type) {
            'integer' => 'Enter a whole number',
            'number' || 'array' => 'Enter a number',
            _ => 'Enter valid JSON',
          };
        }
      }
      if (value == null) {
        if (f.required) _errors[f.name] = 'Required';
        continue;
      }
      out[f.name] = value;
    }
    return _errors.isEmpty ? out : null;
  }

  Future<bool> _confirm() async {
    final b = context.brand;
    final danger = op.risk == ApiRisk.danger;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: GlassSurface(
            radius: 32,
            blur: 40,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Run ${op.id}?', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 10),
                Text(
                  danger
                      ? 'This can delete or destroy things on ${widget.session.profile.name}. It cannot be undone from this app.'
                      : 'This changes ${widget.session.profile.name}.',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: danger ? b.danger : b.textMuted),
                ),
                const SizedBox(height: 22),
                GlassButton(
                  label: danger ? 'Yes, run it' : 'Run',
                  style: danger ? GlassButtonStyle.danger : GlassButtonStyle.primary,
                  onPressed: () => Navigator.pop(ctx, true),
                ),
                const SizedBox(height: 10),
                GlassButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
              ],
            ),
          ),
        ),
      ),
    );
    return ok ?? false;
  }

  Future<void> _run({bool confirm = true}) async {
    final backend = widget.session.backend;
    if (backend is! ApiExplorerBackend) return;
    final input = _collect();
    setState(() {});
    if (input == null) return;
    if (confirm && op.risk != ApiRisk.read && !await _confirm()) return;
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final r = await (backend as ApiExplorerBackend).invoke(op, input);
      if (mounted) {
        setState(() {
          _result = r;
          _hasResult = true;
        });
      }
    } on PanelException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _pretty(Object? v) {
    if (v == null) return 'null (the call succeeded and returned nothing)';
    final s = const JsonEncoder.withIndent('  ').convert(v);
    return s.length > 30000 ? '${s.substring(0, 30000)}\n... (${s.length - 30000} more characters)' : s;
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final theme = Theme.of(context);
    final risk = op.risk;
    final riskColor = switch (risk) {
      ApiRisk.read => b.signal,
      ApiRisk.change => b.warning,
      ApiRisk.danger => b.danger,
    };

    return AmbientBackground(
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: ContentFrame(
            maxWidth: 760,
            child: ListView(
              physics: const BouncingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(20, 8, 20, 32 + MediaQuery.viewInsetsOf(context).bottom),
              children: [
                Row(children: [GlassIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: () => Navigator.of(context).pop())]),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(op.tag.toUpperCase(), style: monoStyle(b.signal, size: 11.5)),
                      const SizedBox(height: 6),
                      Text(op.id, style: theme.textTheme.headlineMedium, maxLines: 2),
                      const SizedBox(height: 10),
                      Row(children: [
                        Tag(op.method, color: riskColor),
                        const SizedBox(width: 8),
                        Tag(switch (risk) {
                          ApiRisk.read => 'Read only',
                          ApiRisk.change => 'Changes data',
                          ApiRisk.danger => 'Destructive',
                        }, color: riskColor),
                      ]),
                      if (op.description.isNotEmpty || op.summary.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(op.description.isNotEmpty ? op.description : op.summary,
                            style: theme.textTheme.bodyMedium?.copyWith(color: b.textMuted)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                if (op.fields.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 8),
                    child: Text('No inputs.', style: monoStyle(b.textMuted, size: 11)),
                  ),
                for (var i = 0; i < op.fields.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _fieldWidget(context, op.fields[i]),
                  ),
                const SizedBox(height: 6),
                GlassButton(
                  label: risk == ApiRisk.read ? 'Run' : (risk == ApiRisk.danger ? 'Run (destructive)' : 'Run (changes data)'),
                  icon: Icons.play_arrow_rounded,
                  style: risk == ApiRisk.danger ? GlassButtonStyle.danger : GlassButtonStyle.primary,
                  loading: _running,
                  onPressed: () => _run(),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 420),
                  curve: const SpringCurve(damping: 1, omega: 12),
                  alignment: Alignment.topCenter,
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: GlassSurface(
                            radius: 22,
                            backdrop: false,
                            shadow: false,
                            tint: b.danger.withValues(alpha: 0.12),
                            padding: const EdgeInsets.all(16),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(Icons.error_outline_rounded, color: b.danger, size: 20),
                              const SizedBox(width: 12),
                              Expanded(child: SelectableText(_error!, style: theme.textTheme.bodyMedium)),
                            ]),
                          ),
                        )
                      : _hasResult
                          ? Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: GlassSurface(
                                radius: 24,
                                backdrop: false,
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Icon(Icons.check_circle_rounded, color: b.signal, size: 18),
                                      const SizedBox(width: 8),
                                      Text('RESPONSE', style: monoStyle(b.signal, size: 11)),
                                      const Spacer(),
                                      GlassIconButton(
                                        icon: Icons.copy_rounded,
                                        tooltip: 'Copy response',
                                        onTap: () {
                                          Clipboard.setData(ClipboardData(text: _pretty(_result)));
                                          showGlassToast(context, 'Response copied');
                                        },
                                      ),
                                    ]),
                                    const SizedBox(height: 10),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxHeight: 420),
                                      child: SingleChildScrollView(
                                        child: SelectableText(_pretty(_result), style: monoStyle(b.text, size: 11).copyWith(height: 1.45)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- fields

  Widget _label(BuildContext context, ApiField f) {
    final b = context.brand;
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 7),
      child: Text('${f.name}${f.required ? '  *' : ''}'.toUpperCase(), style: monoStyle(f.required ? b.signal : b.textMuted, size: 10.5)),
    );
  }

  Widget _fieldError(BuildContext context, ApiField f) {
    final msg = _errors[f.name];
    if (msg == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 6),
      child: Text(msg, style: TextStyle(color: context.brand.danger, fontSize: 12)),
    );
  }

  Widget _fieldWidget(BuildContext context, ApiField f) {
    final b = context.brand;
    final theme = Theme.of(context);

    if (f.enumValues != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(context, f),
        Wrap(spacing: 10, runSpacing: 10, children: [
          if (!f.required)
            GlassChip(label: 'none', selected: _enums[f.name] == null, onTap: () => setState(() => _enums[f.name] = null)),
          for (final v in f.enumValues!)
            GlassChip(label: v, selected: _enums[f.name] == v, onTap: () => setState(() => _enums[f.name] = v)),
        ]),
        _fieldError(context, f),
      ]);
    }

    if (f.type == 'boolean') {
      return GlassSurface(
        radius: 20,
        backdrop: false,
        shadow: false,
        padding: const EdgeInsets.fromLTRB(18, 8, 10, 8),
        child: Row(children: [
          Expanded(child: Text(f.name, style: theme.textTheme.bodyLarge)),
          Switch(
            value: _bools[f.name] ?? false,
            activeThumbColor: Brand.ink,
            activeTrackColor: b.signal,
            onChanged: (v) => setState(() => _bools[f.name] = v),
          ),
        ]),
      );
    }

    final isProject = f.name == 'projectName';
    final isService = f.name == 'serviceName';
    if (isProject || isService) {
      final services = widget.session.services;
      final projects = {for (final s in services) s.project}.toList()..sort();
      final project = _text['projectName']?.text.trim() ?? '';
      final choices = isProject
          ? projects
          : ([for (final s in services) if (project.isEmpty || s.project == project) s.name]..sort());
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(context, f),
        GlassSurface(
          radius: 20,
          backdrop: false,
          shadow: false,
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _text[f.name],
                autocorrect: false,
                enableSuggestions: false,
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: isProject ? 'project-name' : 'service-name',
                  hintStyle: theme.textTheme.bodyLarge?.copyWith(color: b.textMuted.withValues(alpha: 0.6)),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                ),
              ),
            ),
            if (choices.isNotEmpty)
              IconButton(
                tooltip: 'Pick from this server',
                icon: Icon(Icons.arrow_drop_down_circle_outlined, color: b.signal),
                onPressed: () async {
                  final picked = await showGlassSheet<String>(
                    context,
                    (ctx) => ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      children: [
                        for (final c in choices)
                          ListTile(
                            title: Text(c, style: theme.textTheme.titleMedium),
                            onTap: () => Navigator.pop(ctx, c),
                          ),
                      ],
                    ),
                  );
                  if (picked != null) setState(() => _text[f.name]!.text = picked);
                },
              ),
          ]),
        ),
        _fieldError(context, f),
      ]);
    }

    final json = _isJsonField(f);
    final secret = RegExp('password|secret|token|key', caseSensitive: false).hasMatch(f.name) && f.type == 'string';
    final hint = json
        ? 'JSON'
        : f.type == 'array'
            ? 'comma, separated, values'
            : (f.type == 'number' || f.type == 'integer')
                ? '0'
                : (f.schema['pattern'] != null ? '${f.schema['pattern']}' : '');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(context, f),
      GlassSurface(
        radius: 20,
        backdrop: false,
        shadow: false,
        child: TextField(
          controller: _text[f.name],
          obscureText: secret,
          autocorrect: false,
          enableSuggestions: false,
          maxLines: json ? 6 : 1,
          minLines: json ? 3 : 1,
          keyboardType: (f.type == 'number' || f.type == 'integer')
              ? const TextInputType.numberWithOptions(decimal: true, signed: true)
              : (json ? TextInputType.multiline : TextInputType.text),
          style: json ? monoStyle(b.text, size: 12.5) : theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: (json ? monoStyle(b.textMuted, size: 12) : theme.textTheme.bodyLarge)?.copyWith(color: b.textMuted.withValues(alpha: 0.55)),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          ),
        ),
      ),
      if (f.description != null && f.description!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 6),
          child: Text(f.description!, style: monoStyle(b.textMuted, size: 10)),
        ),
      _fieldError(context, f),
    ]);
  }
}
