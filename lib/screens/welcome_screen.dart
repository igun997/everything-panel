import 'package:material_ui/material_ui.dart';

import '../state/scope.dart';
import '../theme/brand.dart';
import '../ui/glass.dart';
import '../ui/motion.dart';
import '../ui/responsive.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final wide = context.isWide;

    return ListenableBuilder(
      listenable: context.auth,
      builder: (context, _) {
        final auth = context.auth;

        Widget hero(AlignmentGeometry align) => Float(
              amplitude: 12,
              period: const Duration(seconds: 7),
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (r) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, Colors.white, wide ? Colors.white : Colors.transparent],
                  stops: const [0, 0.65, 1],
                ).createShader(r),
                child: Image.asset('assets/images/hero.webp', fit: BoxFit.cover, alignment: align),
              ),
            );

        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Reveal(index: 0, child: Text('EVERYTHING-PANEL', style: monoStyle(b.signal, size: 12))),
            const SizedBox(height: 12),
            Reveal(
              index: 1,
              child: Text('Every server.\nOne glass panel.', style: theme.textTheme.displayMedium?.copyWith(fontSize: wide ? 56 : 44)),
            ),
            const SizedBox(height: 14),
            Reveal(
              index: 2,
              child: Text(
                'Watch and control your hosting panels from your pocket. Easypanel today, more providers next. Your servers stay on this device unless you choose encrypted sync.',
                style: theme.textTheme.bodyLarge?.copyWith(color: b.textMuted),
              ),
            ),
            const SizedBox(height: 28),
            Reveal(
              index: 3,
              child: GlassButton(
                label: 'Continue with Google',
                icon: Icons.account_circle_rounded,
                style: GlassButtonStyle.glass,
                loading: auth.busy,
                onPressed: auth.available
                    ? () async {
                        final ok = await auth.signInWithGoogle();
                        if (!context.mounted) return;
                        if (ok) {
                          await context.app.markOnboarded();
                        } else if (auth.error != null) {
                          showGlassToast(context, auth.error!, error: true);
                        }
                      }
                    : null,
              ),
            ),
            if (!auth.available)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 6),
                child: Reveal(
                  index: 4,
                  dy: 8,
                  child: Text(
                    'Google sign-in turns on once this build has its Firebase config.',
                    style: monoStyle(b.textMuted, size: 10.5),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Reveal(
              index: 5,
              child: GlassButton(
                label: 'Continue without an account',
                style: GlassButtonStyle.primary,
                onPressed: () => context.app.markOnboarded(),
              ),
            ),
          ],
        );

        if (wide) {
          // Tablet: art on the left, the pitch on the right.
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: ClipRRect(borderRadius: BorderRadius.circular(40), child: hero(Alignment.center)),
                  ),
                  const SizedBox(width: 48),
                  Expanded(
                    flex: 4,
                    child: Center(child: SingleChildScrollView(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: copy))),
                  ),
                ],
              ),
            ),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // Hero art floats; a gradient dissolves it into the page.
            Positioned(
              top: -size.height * 0.04,
              left: -size.width * 0.1,
              right: -size.width * 0.1,
              height: size.height * 0.62,
              child: hero(Alignment.topCenter),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    ContentFrame(maxWidth: 560, child: copy),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
