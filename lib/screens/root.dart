import 'package:material_ui/material_ui.dart';

import '../state/scope.dart';
import '../ui/glass.dart';
import '../ui/motion.dart';
import 'shell.dart';
import 'welcome_screen.dart';

/// Chooses between splash, first-run welcome and the main shell, and
/// materialises from one to the next.
class RootScreen extends StatelessWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Material ancestor gives every Text a default style (no yellow underline).
    return Material(
      type: MaterialType.transparency,
      child: AmbientBackground(
        child: ListenableBuilder(
          listenable: context.app,
          builder: (context, _) {
            final app = context.app;
            final Widget page;
            if (!app.ready) {
              page = const _Splash(key: ValueKey('splash'));
            } else if (!app.onboarded && !app.hasServers) {
              page = const WelcomeScreen(key: ValueKey('welcome'));
            } else {
              page = const Shell(key: ValueKey('shell'));
            }
            return MaterializeSwitcher(child: page);
          },
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Float(
        amplitude: 6,
        child: Image.asset('assets/images/splash.webp', width: 220, filterQuality: FilterQuality.medium),
      ),
    );
  }
}
