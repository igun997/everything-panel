import 'package:material_ui/material_ui.dart';

import '../ui/glass.dart';
import '../ui/motion.dart';
import '../ui/responsive.dart';
import 'fleet_screen.dart';
import 'services_screen.dart';
import 'settings_screen.dart';
import 'system_screen.dart';

/// Phones get a floating bottom bar; tablets and wide windows get a side rail and a
/// centred, width-limited content column.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  static const _items = [
    GlassNavItem(Icons.grid_view_rounded, 'Fleet'),
    GlassNavItem(Icons.layers_rounded, 'Services'),
    GlassNavItem(Icons.monitor_heart_rounded, 'System'),
    GlassNavItem(Icons.tune_rounded, 'Settings'),
  ];

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      FleetScreen(onOpenServices: () => _go(1)),
      const ServicesScreen(),
      const SystemScreen(),
      const SettingsScreen(),
    ];

    final page = MaterializeSwitcher(child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]));

    if (context.isWide) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GlassNavRail(items: _items, index: _index, onChanged: _go),
                ),
              ),
              Expanded(child: ContentFrame(maxWidth: 980, child: page)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        children: [
          SafeArea(bottom: false, child: ContentFrame(maxWidth: 720, child: page)),
          const Positioned(left: 0, right: 0, bottom: 0, child: ScrollEdgeFade(height: 150)),
          Positioned(
            left: 18,
            right: 18,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 14),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Reveal(
                    dy: 40,
                    child: GlassNavBar(items: _items, index: _index, onChanged: _go),
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
