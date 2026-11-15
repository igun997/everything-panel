import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/providers.dart';
import '../state/scope.dart';
import '../ui/responsive.dart';
import '../theme/brand.dart';
import '../ui/common.dart';
import '../ui/glass.dart';
import '../ui/motion.dart';

class AddServerScreen extends StatefulWidget {
  const AddServerScreen({super.key});

  @override
  State<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends State<AddServerScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _url = TextEditingController();
  final Map<String, TextEditingController> _fields = {};

  PanelKind _kind = PanelKind.easypanel;
  int _mode = 0;
  bool _busy = false;
  String? _error;

  ProviderSpec get _spec => specFor(_kind);
  AuthMode get _auth => _spec.authModes[_mode];

  TextEditingController _ctl(String key) => _fields.putIfAbsent(key, TextEditingController.new);

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    final app = context.app;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final values = {for (final f in _auth.fields) f.key: _ctl(f.key).text};
      final secrets = await _auth.exchange(_url.text.trim(), values);
      await app.addServer(kind: _kind, name: _name.text, url: _url.text, secrets: secrets);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on PanelException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      // Typed passwords never outlive the attempt.
      for (final f in _auth.fields.where((f) => f.secret)) {
        _ctl(f.key).clear();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final theme = Theme.of(context);

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: ContentFrame(
            maxWidth: 620,
            child: Form(
            key: _form,
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(20, 8, 20, 32 + MediaQuery.viewInsetsOf(context).bottom),
              children: [
                Row(
                  children: [
                    GlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: _busy ? null : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Reveal(
                  index: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('NEW SERVER', style: monoStyle(b.signal, size: 11.5)),
                        const SizedBox(height: 6),
                        Text('Connect a panel', style: theme.textTheme.headlineLarge),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Reveal(index: 1, child: _providerRow(context)),
                const SizedBox(height: 22),
                Reveal(
                  index: 2,
                  child: GlassField(
                    controller: _name,
                    label: 'Name (optional)',
                    hint: 'Production',
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(height: 14),
                Reveal(
                  index: 3,
                  child: GlassField(
                    controller: _url,
                    label: 'Panel address',
                    hint: _spec.urlHint,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.trim().length < 4) ? 'Enter the address of your panel' : null,
                  ),
                ),
                const SizedBox(height: 22),
                if (_spec.authModes.length > 1)
                  Reveal(
                    index: 4,
                    child: Wrap(
                      spacing: 10,
                      children: [
                        for (var i = 0; i < _spec.authModes.length; i++)
                          GlassChip(
                            label: _spec.authModes[i].label,
                            selected: i == _mode,
                            onTap: _busy ? () {} : () => setState(() => _mode = i),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                AnimatedSize(
                  duration: const Duration(milliseconds: 420),
                  curve: const SpringCurve(damping: 1, omega: 12),
                  alignment: Alignment.topCenter,
                  child: MaterializeSwitcherInline(
                    key: ValueKey('${_kind.name}.$_mode'),
                    children: [
                      for (final f in _auth.fields)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: GlassField(
                            controller: _ctl(f.key),
                            label: f.label,
                            hint: f.hint,
                            obscure: f.secret,
                            keyboardType: f.keyboard,
                            validator: f.optional
                                ? null
                                : (v) => (v == null || v.trim().isEmpty) ? '${f.label} is required' : null,
                          ),
                        ),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 360),
                  curve: const SpringCurve(damping: 1, omega: 12),
                  alignment: Alignment.topCenter,
                  child: _error == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: GlassSurface(
                            radius: 20,
                            backdrop: false,
                            shadow: false,
                            tint: b.danger.withValues(alpha: 0.12),
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.error_outline_rounded, color: b.danger, size: 20),
                                const SizedBox(width: 12),
                                Expanded(child: Text(_error!, style: theme.textTheme.bodyMedium)),
                              ],
                            ),
                          ),
                        ),
                ),
                Reveal(
                  index: 5,
                  child: GlassButton(
                    label: _busy ? 'Checking connection' : 'Connect',
                    icon: Icons.bolt_rounded,
                    style: GlassButtonStyle.primary,
                    loading: _busy,
                    onPressed: _submit,
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Your token stays in this phone\'s secure keystore and goes only to your own panel, unless you turn on encrypted sync.',
                    textAlign: TextAlign.center,
                    style: monoStyle(b.textMuted, size: 10.5),
                  ),
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _providerRow(BuildContext context) {
    final b = context.brand;
    return SizedBox(
      height: 118,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.none,
        children: [
          for (final spec in providerSpecs.values)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Pressable(
                onTap: () => setState(() {
                  _kind = spec.kind;
                  _mode = 0;
                  _error = null;
                }),
                child: SizedBox(
                  width: 168,
                  child: GlassSurface(
                    radius: 26,
                    blur: 22,
                    selected: spec.kind == _kind,
                    tint: spec.kind == _kind ? b.signal.withValues(alpha: 0.1) : null,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(spec.icon, color: b.signal, size: 24),
                        const Spacer(),
                        Text(spec.name, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(spec.tagline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: b.textMuted, height: 1.25)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          for (final name in upcomingProviders)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Opacity(
                opacity: 0.55,
                child: SizedBox(
                  width: 128,
                  child: GlassSurface(
                    radius: 26,
                    backdrop: false,
                    shadow: false,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.hourglass_empty_rounded, color: b.textMuted, size: 22),
                        const Spacer(),
                        Text(name, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text('SOON', style: monoStyle(b.textMuted, size: 10)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fades its children in together when first built or when the key changes.
class MaterializeSwitcherInline extends StatelessWidget {
  const MaterializeSwitcherInline({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) Reveal(index: i, dy: 14, step: 45, child: children[i]),
      ],
    );
  }
}
