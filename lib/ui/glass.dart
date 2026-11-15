import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme/brand.dart';

/// Critically/under-damped spring expressed as a [Curve], so implicit
/// animations can settle like a spring (Apple: damping ratio + response).
class SpringCurve extends Curve {
  const SpringCurve({this.damping = 0.85, this.omega = 14});
  final double damping;
  final double omega;

  @override
  double transformInternal(double t) {
    final z = damping;
    if (z >= 1) return 1 - math.exp(-omega * t) * (1 + omega * t);
    final wd = omega * math.sqrt(1 - z * z);
    return 1 - math.exp(-z * omega * t) * (math.cos(wd * t) + (z * omega / wd) * math.sin(wd * t));
  }
}

bool _reduceMotion(BuildContext c) => MediaQuery.disableAnimationsOf(c);

/// Feedback on press-down, spring back on release. Never waits for release to
/// react, and re-targets from the live value when interrupted.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.97, this.haptic = true});
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this, value: 1);
  static const _spring = SpringDescription(mass: 1, stiffness: 420, damping: 36);

  void _to(double target) {
    if (_reduceMotion(context)) {
      _c.value = target == 1 ? 1 : widget.scale;
      return;
    }
    _c.animateWith(SpringSimulation(_spring, _c.value, target, _c.velocity));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _to(widget.scale) : null,
      onTapUp: enabled ? (_) => _to(1) : null,
      onTapCancel: enabled ? () => _to(1) : null,
      onTap: enabled
          ? () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            }
          : null,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => Transform.scale(scale: _c.value, child: child),
        child: widget.child,
      ),
    );
  }
}

/// Slowly drifting colour fields behind the glass, so there is something to
/// refract. Static when the user asks for reduced motion.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key, required this.child});
  final Widget child;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 48));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return ColoredBox(
      color: b.page,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(painter: _AmbientPainter(_c, b)),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.t, this.b) : super(repaint: t);
  final Animation<double> t;
  final BrandColors b;

  @override
  void paint(Canvas canvas, Size size) {
    final a = t.value * 2 * math.pi;
    void blob(Offset c, double r, Color color, double alpha) {
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(c, r, [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ]),
      );
      assert(rect.isFinite);
    }

    final w = size.width, h = size.height;
    final k = b.isDark ? 1.0 : 0.55;
    blob(Offset(w * (0.85 + 0.06 * math.sin(a)), h * (0.10 + 0.04 * math.cos(a))), w * 0.85, b.signal, 0.22 * k);
    blob(Offset(w * (0.05 + 0.07 * math.cos(a + 1)), h * (0.55 + 0.05 * math.sin(a + 1))), w * 0.95, b.edge, 0.20 * k);
    blob(Offset(w * (0.70 + 0.08 * math.sin(a + 2)), h * (0.98 + 0.03 * math.cos(a + 2))), w * 0.8, b.signal, 0.14 * k);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.b != b;
}

ColorFilter _saturate(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  return ColorFilter.matrix([
    lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), 0, 0, //
    lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), 0, 0,
    lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, 0, 0,
    0, 0, 0, 1, 0,
  ]);
}

/// The liquid-glass material: blurred + saturated backdrop, a luminous
/// gradient body, and a specular rim where light catches the edge.
///
/// Bigger surfaces should use a larger [blur] and deeper shadow. Never put a
/// light glass surface directly on another; nest with [tint] instead.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding,
    this.blur = 24,
    this.backdrop = true,
    this.tint,
    this.shadow = true,
    this.selected = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double blur;

  /// `false` skips the (expensive) backdrop filter for list rows; the gradient
  /// body and rim still read as glass over the ambient background.
  final bool backdrop;
  final Color? tint;
  final bool shadow;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final highContrast = MediaQuery.highContrastOf(context);
    final r = BorderRadius.circular(radius);

    final top = b.isDark ? 0.15 : 0.78;
    final bottom = b.isDark ? 0.05 : 0.42;
    final boost = highContrast ? (b.isDark ? 0.18 : 0.2) : 0.0;
    final base = b.isDark ? Colors.white : Colors.white;
    final body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withValues(alpha: top + boost),
            base.withValues(alpha: bottom + boost),
          ],
        ),
      ),
      child: tint == null
          ? _pad()
          : DecoratedBox(
              decoration: BoxDecoration(borderRadius: r, color: tint),
              child: _pad(),
            ),
    );

    Widget glass = CustomPaint(
      foregroundPainter: _RimPainter(radius: radius, isDark: b.isDark, accent: selected ? b.signal : null),
      child: body,
    );

    glass = ClipRRect(
      borderRadius: r,
      child: backdrop
          ? BackdropFilter(
              filter: ui.ImageFilter.compose(
                outer: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.clamp),
                inner: _saturate(1.7),
              ),
              child: glass,
            )
          : glass,
    );

    if (!shadow) return glass;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: b.isDark ? 0.38 : 0.10),
            blurRadius: 12 + blur,
            offset: Offset(0, 6 + blur / 4),
            spreadRadius: -6,
          ),
        ],
      ),
      child: glass,
    );
  }

  Widget _pad() => padding == null ? child : Padding(padding: padding!, child: child);
}

class _RimPainter extends CustomPainter {
  _RimPainter({required this.radius, required this.isDark, this.accent});
  final double radius;
  final bool isDark;
  final Color? accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(0.6);
    final lit = isDark ? 0.55 : 0.95;
    final dim = isDark ? 0.07 : 0.18;
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, size.height), [
        (accent ?? Colors.white).withValues(alpha: accent == null ? lit : 0.9),
        Colors.white.withValues(alpha: dim),
        Colors.white.withValues(alpha: dim),
        (accent ?? Colors.white).withValues(alpha: accent == null ? lit * 0.6 : 0.5),
      ], const [0, 0.35, 0.65, 1]);
    canvas.drawRRect(rrect, rim);

    // Specular streak hugging the top edge.
    final streak = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = ui.Gradient.linear(Offset(radius, 0), Offset(size.width - radius, 0), [
        Colors.white.withValues(alpha: 0),
        Colors.white.withValues(alpha: isDark ? 0.5 : 0.9),
        Colors.white.withValues(alpha: 0),
      ], const [0, 0.5, 1]);
    canvas.drawLine(Offset(radius, 1.4), Offset(size.width - radius, 1.4), streak);
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius || old.isDark != isDark || old.accent != accent;
}

enum GlassButtonStyle { primary, glass, danger }

class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = GlassButtonStyle.glass,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final GlassButtonStyle style;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final enabled = onPressed != null && !loading;
    final (fg, tint) = switch (style) {
      GlassButtonStyle.primary => (Brand.ink, b.signal),
      GlassButtonStyle.danger => (b.danger, b.danger.withValues(alpha: 0.16)),
      GlassButtonStyle.glass => (b.text, null),
    };

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icon != null)
          Icon(icon, size: 19, color: fg),
        if (loading || icon != null) const SizedBox(width: 9),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg, fontSize: 15),
          ),
        ),
      ],
    );

    final isPrimary = style == GlassButtonStyle.primary;
    return Opacity(
      opacity: enabled || loading ? 1 : 0.45,
      child: Pressable(
        onTap: enabled ? onPressed : null,
        child: isPrimary
            ? DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(b.signal, Colors.white, 0.28)!,
                      b.signal,
                    ],
                  ),
                  boxShadow: [BoxShadow(color: b.signal.withValues(alpha: 0.35), blurRadius: 24, spreadRadius: -4)],
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1),
                ),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15), child: content),
              )
            : GlassSurface(
                radius: 22,
                blur: 14,
                backdrop: false,
                tint: tint,
                shadow: false,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
                child: content,
              ),
      ),
    );
  }
}

class GlassChip extends StatelessWidget {
  const GlassChip({super.key, required this.label, required this.selected, required this.onTap, this.count});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: _reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 260),
        curve: const SpringCurve(damping: 0.9),
        child: GlassSurface(
          radius: 18,
          backdrop: false,
          shadow: false,
          selected: selected,
          tint: selected ? b.signal.withValues(alpha: b.isDark ? 0.18 : 0.16) : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 13,
                      color: selected ? (b.isDark ? b.signal : b.signal) : b.textMuted,
                    ),
              ),
              if (count != null) ...[
                const SizedBox(width: 7),
                Text('$count', style: monoStyle(selected ? b.signal : b.textMuted, size: 11)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class GlassField extends StatelessWidget {
  const GlassField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
    this.validator,
    this.textInputAction,
    this.onSubmitted,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 7),
          child: Text(label.toUpperCase(), style: monoStyle(b.textMuted, size: 10.5)),
        ),
        GlassSurface(
          radius: 20,
          backdrop: false,
          shadow: false,
          child: TextFormField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            autofillHints: autofillHints,
            validator: validator,
            textInputAction: textInputAction,
            onFieldSubmitted: onSubmitted,
            autocorrect: false,
            enableSuggestions: false,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(color: b.textMuted.withValues(alpha: 0.6)),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              suffixIcon: suffix,
              errorStyle: TextStyle(color: b.danger, height: 1.2),
            ),
          ),
        ),
      ],
    );
  }
}

/// A status light with a soft glow.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 9, this.glow = true});
  final Color color;
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: glow ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 9, spreadRadius: 0.5)] : null,
        ),
      );
}

/// Floating bottom navigation: a glass pill with a lens that springs between
/// items. Content scrolls underneath it.
class GlassNavItem {
  const GlassNavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

class GlassNavBar extends StatelessWidget {
  const GlassNavBar({super.key, required this.items, required this.index, required this.onChanged});
  final List<GlassNavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final reduce = _reduceMotion(context);
    return GlassSurface(
      radius: 34,
      blur: 30,
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        height: 58,
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth / items.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: reduce ? Duration.zero : const Duration(milliseconds: 520),
                curve: const SpringCurve(damping: 0.78, omega: 13),
                left: index * w,
                top: 0,
                bottom: 0,
                width: w,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        b.signal.withValues(alpha: b.isDark ? 0.26 : 0.30),
                        b.signal.withValues(alpha: b.isDark ? 0.10 : 0.12),
                      ],
                    ),
                    border: Border.all(color: b.signal.withValues(alpha: 0.55), width: 1.2),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == index,
                        label: items[i].label,
                        child: Pressable(
                          scale: 0.92,
                          onTap: () => onChanged(i),
                          child: SizedBox(
                            height: 58,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(height: 0),
                                Icon(items[i].icon, size: 22, color: i == index ? b.signal : b.text.withValues(alpha: 0.72)),
                                const SizedBox(height: 3),
                                Text(
                                  items[i].label,
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: i == index ? b.signal : b.text.withValues(alpha: 0.72),
                                        fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// Fades content into the floating chrome instead of a hard divider.
class ScrollEdgeFade extends StatelessWidget {
  const ScrollEdgeFade({super.key, this.height = 120});
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.brand.page;
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c.withValues(alpha: 0), c.withValues(alpha: 0.85)],
            ),
          ),
        ),
      ),
    );
  }
}

Future<T?> showGlassSheet<T>(BuildContext context, WidgetBuilder builder, {bool dismissible = true}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    elevation: 0,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, 10 + MediaQuery.viewInsetsOf(context).bottom),
      child: GlassSurface(
        radius: 36,
        blur: 40,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: context.brand.textMuted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Flexible(child: builder(context)),
            ],
          ),
        ),
      ),
    ),
  );
}

void showGlassToast(BuildContext context, String message, {bool error = false}) {
  final b = context.brand;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 104),
      padding: EdgeInsets.zero,
      duration: Duration(seconds: error ? 5 : 3),
      content: GlassSurface(
        radius: 22,
        blur: 28,
        tint: (error ? b.danger : b.signal).withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Icon(error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                size: 20, color: error ? b.danger : b.signal),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
          ],
        ),
      ),
    ),
  );
}

/// Circular gauge with a rounded gradient arc.
class RingGauge extends StatelessWidget {
  const RingGauge({super.key, required this.percent, required this.label, required this.value, this.size = 108});
  final double percent; // 0..100
  final String label;
  final String value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final p = (percent.clamp(0, 100)) / 100;
    final color = p > 0.9 ? b.danger : (p > 0.75 ? b.warning : b.signal);
    return Semantics(
      label: '$label $value',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: p),
            duration: _reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 700),
            curve: const SpringCurve(damping: 1),
            builder: (context, v, _) => SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _RingPainter(v, color, b.isDark),
                child: Center(
                  child: Text(
                    '${(v * 100).round()}%',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: size * 0.22),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(label.toUpperCase(), style: monoStyle(b.textMuted, size: 10.5)),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: b.text)),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.p, this.color, this.dark);
  final double p;
  final Color color;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.095;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    canvas.drawArc(
      arcRect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = (dark ? Colors.white : Colors.black).withValues(alpha: dark ? 0.09 : 0.07),
    );
    if (p <= 0) return;
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 2 * p,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.6)
        ..color = color.withValues(alpha: 0.45),
    );
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 2 * p,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.p != p || old.color != color || old.dark != dark;
}

/// The tablet counterpart of [GlassNavBar]: a vertical glass rail whose lens springs
/// between items. The lens is a plain decorated box (a nested glass surface inside a
/// backdrop-filtered parent drops its sibling content on Impeller).
class GlassNavRail extends StatelessWidget {
  const GlassNavRail({super.key, required this.items, required this.index, required this.onChanged});
  final List<GlassNavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  static const double itemHeight = 72;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final reduce = _reduceMotion(context);
    return GlassSurface(
      radius: 34,
      blur: 30,
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 76,
        height: itemHeight * items.length,
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: reduce ? Duration.zero : const Duration(milliseconds: 520),
              curve: const SpringCurve(damping: 0.78, omega: 13),
              top: index * itemHeight,
              left: 0,
              right: 0,
              height: itemHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      b.signal.withValues(alpha: b.isDark ? 0.26 : 0.30),
                      b.signal.withValues(alpha: b.isDark ? 0.10 : 0.12),
                    ],
                  ),
                  border: Border.all(color: b.signal.withValues(alpha: 0.55), width: 1.2),
                ),
              ),
            ),
            Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  Semantics(
                    button: true,
                    selected: i == index,
                    label: items[i].label,
                    child: Pressable(
                      scale: 0.92,
                      onTap: () => onChanged(i),
                      child: SizedBox(
                        height: itemHeight,
                        width: double.infinity,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(items[i].icon, size: 24, color: i == index ? b.signal : b.text.withValues(alpha: 0.72)),
                            const SizedBox(height: 4),
                            Text(
                              items[i].label,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: i == index ? b.signal : b.text.withValues(alpha: 0.72),
                                    fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
