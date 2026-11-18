import 'dart:math';
import 'dart:ui' show ImageFilter;
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

class C {
  static const bg = Color(0xFF07090D);
  static const text = Color(0xFFECEEF2);
  static const sub = Color(0xFFC9CED6);
  static const mute = Color(0xFF9AA1AD);
  static const up = Color(0xFF7FD6C6);
  static const down = Color(0xFFF0A86E);
  static const flat = Color(0xFFC9CED6);
  static const gold = Color(0xFFE3C68C);
  static const line = Color(0x12FFFFFF);
  static Color tone(num d) => d > 0 ? up : (d < 0 ? down : flat);
}

TextStyle inter(double size, {FontWeight w = FontWeight.w400, Color c = C.text, double? h, double ls = 0}) =>
    GoogleFonts.inter(fontSize: size, fontWeight: w, color: c, height: h, letterSpacing: ls,
        fontFeatures: const [FontFeature.tabularFigures()]);

TextStyle serif(double size, {Color c = C.text}) =>
    GoogleFonts.instrumentSerif(fontSize: size, color: c, height: 1, fontFeatures: const [FontFeature.tabularFigures()]);

TextStyle label() => inter(12, c: C.mute, ls: 1.0, w: FontWeight.w500);

/// Frosted liquid-glass surface.
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final List<BoxShadow>? glow;
  const Glass({super.key, required this.child, this.radius = 28, this.padding = const EdgeInsets.all(20), this.borderColor, this.glow});

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: r, boxShadow: [
        const BoxShadow(color: Color(0x73000000), blurRadius: 60, offset: Offset(0, 24)),
        ...?glow,
      ]),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: r,
              border: Border.all(color: borderColor ?? const Color(0x17FFFFFF)),
              gradient: const LinearGradient(
                begin: Alignment(-0.6, -1), end: Alignment(0.6, 1),
                colors: [Color(0x1AFFFFFF), Color(0x08FFFFFF), Color(0x0FFFFFFF)],
                stops: [0, 0.48, 1],
              ),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: r,
              gradient: const LinearGradient(
                begin: Alignment.topCenter, end: Alignment(0, -0.92),
                colors: [Color(0x14FFFFFF), Color(0x00FFFFFF)],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Slowly drifting ambient glows behind the glass.
class Ambient extends StatefulWidget {
  final Color glow;
  final Widget child;
  const Ambient({super.key, required this.glow, required this.child});
  @override
  State<Ambient> createState() => _AmbientState();
}

class _AmbientState extends State<Ambient> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 22))..repeat(reverse: true);
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  Widget _blob(double size, Color color, double opacity) => Container(
        width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)])),
      );

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return ColoredBox(
      color: C.bg,
      child: Stack(children: [
        AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            final t = reduce ? 0.5 : Curves.easeInOut.transform(_c.value);
            final w = MediaQuery.of(context).size.width;
            return Stack(children: [
              Positioned(left: -200 + 40 * t, top: -180 + 50 * t, child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: widget.glow), duration: const Duration(milliseconds: 900),
                builder: (_, c, _) => _blob(640, c ?? widget.glow, 0.55))),
              Positioned(right: -260 + 30 * (1 - t), top: 380 + 40 * sin(t * pi), child: _blob(620, const Color(0xFF2C4F63), 0.5)),
              Positioned(left: w * 0.1, bottom: -260 + 30 * t, child: _blob(520, widget.glow, 0.22)),
            ]);
          },
        ),
        widget.child,
      ]),
    );
  }
}

class GlassSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  const GlassSwitch({super.key, required this.value, required this.onChanged, required this.label});
  @override
  Widget build(BuildContext context) => Semantics(
        toggled: value, label: label, button: true,
        child: GestureDetector(
          onTap: () => onChanged(!value),
          child: SizedBox(
            width: 52, height: 44,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48, height: 28, padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: value ? C.up : const Color(0x24FFFFFF)),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200), curve: Curves.easeOut,
                  alignment: value ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                  child: Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, color: value ? C.bg : C.text)),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Pill-shaped tappable chip.
class Pill extends StatelessWidget {
  final Widget child;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;
  final double height;
  const Pill({super.key, required this.child, required this.selected, required this.onTap, this.accent, this.height = 40});
  @override
  Widget build(BuildContext context) {
    final a = accent;
    return Semantics(
      selected: selected, button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height / 2),
            color: selected ? (a?.withValues(alpha: 0.16) ?? const Color(0x1FFFFFFF)) : const Color(0x00000000),
            border: Border.all(color: selected && a != null ? a.withValues(alpha: 0.4) : const Color(0x1FFFFFFF)),
          ),
          child: Center(widthFactor: 1, child: DefaultTextStyle(style: inter(14, w: FontWeight.w500, c: selected ? (a ?? C.text) : C.mute), child: child)),
        ),
      ),
    );
  }
}

Widget dot(Color c, [double s = 8]) => Container(width: s, height: s, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
