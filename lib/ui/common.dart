import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../theme/brand.dart';
import 'glass.dart';
import 'motion.dart';

/// Bottom space that keeps the last row clear of the floating nav bar.
const double kNavClearance = 128;

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.eyebrow, required this.title, this.trailing});
  final String eyebrow;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(eyebrow.toUpperCase(), style: monoStyle(b.signal, size: 11.5)),
                const SizedBox(height: 6),
                Text(title, style: Theme.of(context).textTheme.headlineLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.onTap, required this.tooltip, this.busy = false});
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onTap,
        scale: 0.9,
        child: GlassSurface(
          radius: 22,
          blur: 16,
          backdrop: false,
          shadow: false,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: b.signal),
                    )
                  : Icon(icon, size: 21, color: b.text),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mono pill, for kinds and states.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final c = color ?? b.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: c.withValues(alpha: 0.13),
        border: Border.all(color: c.withValues(alpha: 0.28)),
      ),
      child: Text(text.toUpperCase(), style: monoStyle(c, size: 10)),
    );
  }
}

/// Thin animated usage bar.
class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.percent, required this.label, this.height = 5});
  final double percent;
  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final p = (percent.clamp(0, 100)) / 100;
    final color = p > 0.9 ? b.danger : (p > 0.75 ? b.warning : b.signal);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label.toUpperCase(), style: monoStyle(b.textMuted, size: 10)),
            const Spacer(),
            CountUp(value: percent, decimals: 1, suffix: '%', style: monoStyle(b.text, size: 11)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: Stack(
            children: [
              Container(height: height, color: (b.isDark ? Colors.white : Colors.black).withValues(alpha: 0.09)),
              TweenAnimationBuilder<double>(
                tween: Tween(end: p),
                duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 700),
                curve: const SpringCurve(damping: 1, omega: 11),
                builder: (context, v, _) => FractionallySizedBox(
                  widthFactor: v.clamp(0.0, 1.0),
                  child: Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: color,
                      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class EmptyArt extends StatelessWidget {
  const EmptyArt({super.key, required this.title, required this.message, this.action, this.asset = 'assets/images/empty.webp'});
  final String title;
  final String message;
  final Widget? action;
  final String asset;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Float(
            amplitude: 8,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => const RadialGradient(
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0, 0.6, 1],
              ).createShader(r),
              child: Image.asset(asset, width: 220, height: 220, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 8),
          Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: b.textMuted), textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

String relativeTime(DateTime? t) {
  if (t == null) return 'never';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 10) return 'just now';
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  return '${d.inHours}h ago';
}

String formatUptime(Duration d) {
  if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inMinutes}m';
}

/// Header that stays at the top while a list scrolls under it (search, filters).
class PinnedBar extends SliverPersistentHeaderDelegate {
  PinnedBar({required this.extent, required this.background, required this.child});
  final double extent;
  final Color background;
  final Widget child;

  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // List rows scroll under this bar, so it is frosted: a blur layer sits *behind* the bar's
    // content (a sibling, not an ancestor, so the glass fields inside it keep painting
    // normally), tinted toward the page colour and fading out at the bottom edge.
    final tint = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [background.withValues(alpha: 0.62), background.withValues(alpha: 0.62), background.withValues(alpha: 0)],
          stops: const [0, 0.82, 1],
        ),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18, tileMode: TileMode.clamp),
              child: tint,
            ),
          ),
        ),
        // The sliver asks its child for "at most" the extent; without a tight height a shorter
        // child leaves the header's paint size below its layout size.
        SizedBox(height: extent, child: child),
      ],
    );
  }

  @override
  bool shouldRebuild(PinnedBar old) => old.child != child || old.background != background || old.extent != extent;
}
