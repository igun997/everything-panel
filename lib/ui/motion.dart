import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'glass.dart';

/// Content rises into place and settles on a spring, staggered by [index].
/// Plays once; respects reduced motion.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.index = 0, this.dy = 22, this.step = 55});
  final Widget child;
  final int index;
  final double dy;

  /// Milliseconds between consecutive items. Capped so long lists stay snappy.
  final int step;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // A screen or tab that is itself animating in already carries the motion; adding
    // each item's own entrance on top reads as the transition playing twice.
    final gate = TransitionGate.maybeOf(context);
    if (gate != null && gate.status != AnimationStatus.completed) {
      _c.value = 1;
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
      return;
    }
    final delay = Duration(milliseconds: math.min(widget.index, 9) * widget.step);
    Future<void>.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const spring = SpringCurve(damping: 0.86, omega: 13);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final s = spring.transform(_c.value);
        final o = Curves.easeOut.transform((_c.value * 2.2).clamp(0.0, 1.0));
        return Opacity(
          opacity: o,
          child: Transform.translate(
            offset: Offset(0, widget.dy * (1 - s)),
            child: Transform.scale(scale: 0.965 + 0.035 * s, child: child),
          ),
        );
      },
    );
  }
}

/// A number that rolls to its new value instead of jumping.
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, this.style, this.suffix = '', this.decimals = 0});
  final double value;
  final TextStyle? style;
  final String suffix;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 800),
      curve: const SpringCurve(damping: 1, omega: 11),
      builder: (context, v, _) => Text(
        '${v.toStringAsFixed(decimals)}$suffix',
        style: style?.copyWith(fontFeatures: const [ui.FontFeature.tabularFigures()]),
      ),
    );
  }
}

/// Swaps content by materialising it: the incoming view un-blurs and scales up
/// while the outgoing one softens away. Interruptible; no input is blocked.
class MaterializeSwitcher extends StatelessWidget {
  const MaterializeSwitcher({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduce ? const Duration(milliseconds: 150) : const Duration(milliseconds: 520),
      reverseDuration: reduce ? const Duration(milliseconds: 150) : const Duration(milliseconds: 280),
      switchInCurve: const SpringCurve(damping: 1, omega: 12),
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) {
        if (reduce) return TransitionGate(animation: animation, child: FadeTransition(opacity: animation, child: child));
        return TransitionGate(
          animation: animation,
          child: AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final t = animation.value.clamp(0.0, 1.0);
            final blur = (1 - t) * 10;
            return Opacity(
              opacity: Curves.easeOut.transform(t),
              child: Transform.scale(
                scale: 0.97 + 0.03 * animation.value,
                child: blur < 0.05
                    ? child
                    : ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal),
                        child: child,
                      ),
              ),
            );
          },
        ),
        );
      },
      child: child,
    );
  }
}

/// Idle breathing motion for hero art: a slow float and tilt.
class Float extends StatefulWidget {
  const Float({super.key, required this.child, this.amplitude = 10, this.period = const Duration(seconds: 6)});
  final Widget child;
  final double amplitude;
  final Duration period;

  @override
  State<Float> createState() => _FloatState();
}

class _FloatState extends State<Float> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeInOutSine.transform(_c.value);
        return Transform.translate(
          offset: Offset(0, (t - 0.5) * 2 * widget.amplitude),
          child: Transform.rotate(angle: (t - 0.5) * 0.02, child: child),
        );
      },
    );
  }
}

/// Soft pulsing halo, used for live status.
class Breathe extends StatefulWidget {
  const Breathe({super.key, required this.child, this.active = true});
  final Widget child;
  final bool active;

  @override
  State<Breathe> createState() => _BreatheState();
}

class _BreatheState extends State<Breathe> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = widget.active && !MediaQuery.disableAnimationsOf(context);
    if (run && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!run) {
      _c.stop();
    }
  }

  @override
  void didUpdateWidget(Breathe old) {
    super.didUpdateWidget(old);
    didChangeDependencies();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: 0.65 + 0.35 * Curves.easeInOut.transform(_c.value),
        child: Transform.scale(scale: 0.92 + 0.12 * _c.value, child: child),
      ),
    );
  }
}

/// Route that glides in with a spring, scaling the previous page back
/// slightly so depth reads. Enters and leaves along the same path.
class FluidRoute<T> extends PageRouteBuilder<T> {
  FluidRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: 560),
          reverseTransitionDuration: const Duration(milliseconds: 380),
          opaque: true,
          pageBuilder: (context, animation, _) => TransitionGate(animation: animation, child: builder(context)),
          transitionsBuilder: (context, animation, secondary, child) {
            if (MediaQuery.disableAnimationsOf(context)) {
              return FadeTransition(opacity: animation, child: child);
            }
            final inCurve = CurvedAnimation(
              parent: animation,
              curve: const SpringCurve(damping: 0.9, omega: 12),
              reverseCurve: Curves.easeInCubic,
            );
            final back = CurvedAnimation(parent: secondary, curve: Curves.easeOutCubic);
            return AnimatedBuilder(
              animation: Listenable.merge([inCurve, back]),
              child: child,
              builder: (context, child) => Transform.scale(
                scale: 1 - 0.04 * back.value,
                child: Opacity(
                  opacity: (1 - 0.4 * back.value),
                  child: FractionalTranslation(
                    translation: Offset(0, 0.12 * (1 - inCurve.value)),
                    child: Opacity(opacity: animation.value.clamp(0.0, 1.0), child: child),
                  ),
                ),
              ),
            );
          },
        );
}

/// Tells descendants that a transition is running, so their own entrance motion can stand down.
class TransitionGate extends InheritedWidget {
  const TransitionGate({super.key, required this.animation, required super.child});
  final Animation<double> animation;

  AnimationStatus get status => animation.status;

  static TransitionGate? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<TransitionGate>();

  @override
  bool updateShouldNotify(TransitionGate old) => false;
}
