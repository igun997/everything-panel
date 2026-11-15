import 'package:material_ui/material_ui.dart';

/// Window-size classes. Phones are compact; tablets and unfolded foldables are wide.
/// Layout follows the window, not the device, so split-screen and rotation just work.
const double kMediumWidth = 600;
const double kWideWidth = 840;

extension ResponsiveContext on BuildContext {
  double get windowWidth => MediaQuery.sizeOf(this).width;
  bool get isMedium => windowWidth >= kMediumWidth;
  bool get isWide => windowWidth >= kWideWidth;
}

/// Centres content and stops it stretching across a tablet screen.
class ContentFrame extends StatelessWidget {
  const ContentFrame({super.key, required this.child, this.maxWidth = 820});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}
