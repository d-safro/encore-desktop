import 'package:material_ui/material_ui.dart';

/// A page inside the desktop window. The window's own ‹ › (in the top bar, and Alt+← / Alt+→) go back and forth,
/// so the page's bar doesn't add a second back arrow, and every page title starts at the same place.
class DesktopPage<T> extends Page<T> {
  const DesktopPage({super.key, required this.child});
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => _DesktopRoute<T>(this);
}

class _DesktopRoute<T> extends PageRoute<T> with MaterialRouteTransitionMixin<T> {
  _DesktopRoute(DesktopPage<T> page) : super(settings: page);

  @override
  Widget buildContent(BuildContext context) => (settings as DesktopPage<T>).child;

  @override
  bool get maintainState => true;

  @override
  bool get fullscreenDialog => false;

  // no back arrow in the page's AppBar (see DesktopPage)
  @override
  bool get impliesAppBarDismissal => false;

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';
}
