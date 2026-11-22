import 'package:material_ui/material_ui.dart';

import '../core/appearance.dart';
import '../ui/sheets.dart';

/// The desktop's menus and panels (see showAppSheet): a song's, an album's or an episode's menu opens where you
/// clicked, as a compact menu; the phone's other bottom sheets open as a dialog in the middle of the window.

/// Where and when the mouse last went down (the right click, or the ⋯ button, that opened a menu).
Offset? _pointer;
DateTime _pointerAt = DateTime(0);

/// Put round the window once: notes where clicks happen, and takes over showAppSheet.
class DesktopSheets extends StatefulWidget {
  const DesktopSheets({super.key, required this.child});
  final Widget child;
  @override
  State<DesktopSheets> createState() => _DesktopSheetsState();
}

class _DesktopSheetsState extends State<DesktopSheets> {
  @override
  void initState() {
    super.initState();
    sheetOpener = openDesktopSheet;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (e) {
      _pointer = e.position;
      _pointerAt = DateTime.now();
    },
    child: widget.child,
  );
}

/// Where a menu opens: at the click that opened it; opened from the keyboard, under the focused button.
Offset? _menuAnchor() {
  if (DateTime.now().difference(_pointerAt) < const Duration(seconds: 1)) return _pointer;
  final box = FocusManager.instance.primaryFocus?.context?.findRenderObject();
  if (box is RenderBox && box.attached && box.hasSize) return box.localToGlobal(box.size.bottomLeft(Offset.zero));
  return null; // the middle of the window
}

Future<Object?> openDesktopSheet(BuildContext context, WidgetBuilder builder, {required bool menu}) {
  if (!menu) {
    return showDialog<Object>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
          child: Padding(padding: const EdgeInsets.only(top: 12), child: builder(ctx)),
        ),
      ),
    );
  }
  final at = _menuAnchor();
  return showGeneralDialog<Object>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Close the menu',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 90),
    transitionBuilder: (ctx, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (ctx, _, _) => CustomSingleChildLayout(
      delegate: MenuLayout(at),
      child: Material(
        color: Theme.of(ctx).colorScheme.surfaceContainerHigh,
        elevation: 8,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(AppLook.of(ctx).r(12)),
        clipBehavior: Clip.antiAlias,
        // rows for a mouse, not a finger
        child: ListTileTheme(
          data: ListTileTheme.of(ctx).copyWith(
            dense: true,
            visualDensity: const VisualDensity(vertical: -2),
            minVerticalPadding: 6,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            horizontalTitleGap: 12,
            minLeadingWidth: 20,
          ),
          child: IconTheme.merge(
            data: const IconThemeData(size: 20),
            child: MediaQuery.removePadding(context: ctx, removeTop: true, removeBottom: true, child: builder(ctx)),
          ),
        ),
      ),
    ),
  );
}

/// A menu by the pointer: to its right and below; flipped to its left when there's no room on the right, and
/// moved up to stay inside the window. 300 px wide at most.
class MenuLayout extends SingleChildLayoutDelegate {
  MenuLayout(this.at);
  final Offset? at;
  static const margin = 8.0, width = 300.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(Size(width, constraints.maxHeight - 2 * margin));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final p = at;
    if (p == null) return Offset((size.width - childSize.width) / 2, (size.height - childSize.height) / 2);
    var x = p.dx;
    if (x + childSize.width > size.width - margin) x = p.dx - childSize.width;
    final y = p.dy + childSize.height > size.height - margin ? size.height - margin - childSize.height : p.dy;
    return Offset(x.clamp(margin, size.width - margin - childSize.width), y.clamp(margin, size.height));
  }

  @override
  bool shouldRelayout(MenuLayout old) => old.at != at;
}
