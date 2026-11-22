import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// A clear ring round whatever has the keyboard focus, once you start moving with the keyboard (Tab, the
/// arrows), gone again at the next click. Material's own focus look is the same faint gray as the mouse's
/// hover, hard to follow across a whole window, and links show none at all.
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.child});
  final Widget child;
  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _keyboard = false;
  final _repaint = ValueNotifier(0);

  static final _moves = {
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent && _moves.contains(e.logicalKey) && !_keyboard && mounted) setState(() => _keyboard = true);
    return false; // only watching
  }

  void _changed() => _repaint.value++;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    FocusManager.instance.addListener(_changed);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    FocusManager.instance.removeListener(_changed);
    _repaint.dispose();
    super.dispose();
  }

  /// The focused thing's box, if it's in this window (not a dialog), not a text field, and not the window itself.
  Rect? _target(RenderBox into) {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null || !ctx.mounted || ctx.findAncestorStateOfType<_FocusRingState>() != this) return null;
    if (ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final r = MatrixUtils.transformRect(box.getTransformTo(into), Offset.zero & box.size);
    if (r.width > into.size.width * 0.8 && r.height > into.size.height * 0.5) return null; // a whole pane
    return r;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent, // any click in the window, even on nothing
    onPointerDown: (_) {
      if (_keyboard) setState(() => _keyboard = false);
    },
    child: NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _changed();
        return false;
      },
      child: CustomPaint(
        foregroundPainter: _RingPainter(this, _keyboard, Theme.of(context).colorScheme.primary, _repaint),
        child: widget.child,
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.state, this.keyboard, this.color, Listenable repaint) : super(repaint: repaint);
  final _FocusRingState state;
  final bool keyboard; // moving with the keys (else no ring)
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final into = state.context.findRenderObject();
    if (into is! RenderBox) return;
    final r = keyboard ? state._target(into) : null;
    if (r == null) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.inflate(2), const Radius.circular(10)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.keyboard != keyboard || old.color != color;
}
