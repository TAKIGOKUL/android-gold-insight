import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../analysis.dart';
import '../i18n.dart';
import '../market.dart';
import '../state.dart';
import 'glass.dart';

String money(double usd, AppState a) {
  final v = usd * a.rate;
  final digits = v >= 10000 ? 0 : 2;
  final parts = v.toStringAsFixed(digits).split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${a.sym}$whole${digits > 0 ? '.${parts[1]}' : ''}';
}

/// Which Indian reference the INR price follows.
String _source(AppState a, Metal m) {
  final p = a.premiums;
  switch (m) {
    case Metal.gold: return p['gold_paytm'] == 1 ? 'Paytm' : (p.containsKey('gold') ? 'Groww' : 'India est.');
    case Metal.silver: return p.containsKey('silver') ? 'Groww' : 'India est.';
    case Metal.platinum: return p.containsKey('platinum') ? 'Market' : 'India est.';
  }
}

String pct(double f) => '${(f.abs() * 100).toStringAsFixed(2)}%';

/// Ask Google (AI Mode) why the metal moved — no on-device computation needed.
Future<void> askGoogle(Snapshot x, String lang) async {
  final chg = x.eventChg;
  final up = chg >= 0;
  final now = DateTime.now();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final date = '${now.day} ${months[now.month - 1]} ${now.year}';
  final window = x.eventIsHour ? 'in the last hour today' : 'today';
  final q = 'Why did the ${x.metal.name} price ${up ? 'rise' : 'fall'} '
      '${(chg.abs() * 100).toStringAsFixed(1)}% $window ($date)? Latest news and causes.';
  final uri = Uri.https('www.google.com', '/search', {'q': q, 'udm': '50', 'hl': lang});
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class TodayPage extends StatefulWidget {
  final AppState a;
  const TodayPage({super.key, required this.a});
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  late final PageController _pc = PageController(initialPage: widget.a.metal.index);

  @override
  void didUpdateWidget(TodayPage old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (!_pc.hasClients) return;
    final target = widget.a.metal.index;
    if ((_pc.page ?? target.toDouble()).round() != target && !_pc.position.isScrollingNotifier.value) {
      _pc.animateToPage(target, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() { _pc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final a = widget.a, l = a.s.lang;
    final top = MediaQuery.of(context).padding.top + 12;
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    return Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(20, top, 20, 0),
        child: Column(children: [
          _Header(a: a),
          const SizedBox(height: 18),
          _MetalSwitch(a: a),
        ]),
      ),
      Expanded(
        child: PageView(
          controller: _pc,
          onPageChanged: (i) { HapticFeedback.selectionClick(); a.pickMetal(Metal.values[i]); },
          children: [
            for (final m in Metal.values)
              RefreshIndicator(
                color: C.gold, backgroundColor: const Color(0xFF161920),
                onRefresh: a.refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 130),
                  children: [
                    if (a.snaps[m] == null)
                      const SizedBox(height: 360, child: Center(child: CircularProgressIndicator(color: C.gold, strokeWidth: 2)))
                    else ...[
                      _PriceBlock(a: a, x: a.snaps[m]!),
                      const SizedBox(height: 20),
                      _ChartCard(a: a, metal: m, tone: _chartTone(a.chartFor(m), a.snaps[m]!.dayChg)),
                      const SizedBox(height: 16),
                      _SignalCard(x: a.snaps[m]!, l: l),
                      const SizedBox(height: 16),
                      _WhyCard(x: a.snaps[m]!, l: l),
                    ],
                    if (a.offline) Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(tr(l, 'offline'), textAlign: TextAlign.center, style: inter(12, c: C.mute)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ]);
  }

  Color _chartTone(Series? s, double day) => C.tone(s == null || s.c.length < 2 ? day : s.c.last - s.c.first);
}

/// Small periodic-table tile used as the in-app logo.
class ElementTile extends StatelessWidget {
  final double size;
  const ElementTile({super.key, this.size = 36});
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Insight',
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.22),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0x29FFFFFF), Color(0x0AFFFFFF)]),
            border: Border.all(color: const Color(0x66E3C68C)),
          ),
          child: Stack(children: [
            Positioned(left: size * 0.12, top: size * 0.06,
              child: Text('79', style: inter(size * 0.2, w: FontWeight.w600, c: C.gold))),
            Align(alignment: const Alignment(0, 0.45),
              child: Text('In', style: serif(size * 0.56, c: C.gold))),
          ]),
        ),
      );
}

class _Header extends StatelessWidget {
  final AppState a;
  const _Header({required this.a});

  void _sheet(BuildContext context, String title, List<(String, String, bool, VoidCallback)> items) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0x00000000),
      barrierColor: const Color(0x66000000),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        child: Glass(
          radius: 32, padding: const EdgeInsets.all(8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.all(14), child: Text(title.toUpperCase(), style: label())),
            for (final (main, side, sel, tap) in items)
              Semantics(
                selected: sel, button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () { tap(); Navigator.of(ctx).pop(); },
                  child: Container(
                    height: 56, padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: sel ? const Color(0x1FFFFFFF) : const Color(0x00000000)),
                    child: Row(children: [
                      Expanded(child: Text(main, style: inter(16, w: FontWeight.w500, c: sel ? C.text : C.sub))),
                      Text(side, style: inter(16, c: C.gold)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = a.s.lang;
    Widget btn(Widget child, String sem, VoidCallback onTap) => Semantics(
          button: true, label: sem,
          child: GestureDetector(onTap: onTap, child: Glass(radius: 22, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: child)),
        );
    return Row(children: [
      const ElementTile(),
      const SizedBox(width: 10),
      Text('Insight', style: inter(17, w: FontWeight.w600, ls: 0.3)),
      const SizedBox(width: 8),
      Semantics(
        label: a.offline ? 'Offline' : 'Live',
        child: Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle,
          color: a.offline ? C.down : C.up, boxShadow: [BoxShadow(color: a.offline ? C.down : C.up, blurRadius: 8)])),
      ),
      const Spacer(),
      btn(Row(children: [Text(a.sym, style: inter(16, c: C.gold, w: FontWeight.w600)), const SizedBox(width: 6), Text(a.s.cur, style: inter(14, w: FontWeight.w600)),
          const SizedBox(width: 6), const Icon(Icons.swap_horiz, size: 16, color: C.mute)]),
        'Currency ${a.s.cur}, tap to switch',
        () { HapticFeedback.selectionClick(); a.update((s) => s.cur = s.cur == 'USD' ? 'INR' : 'USD'); }),
    ]);
  }
}

class _MetalSwitch extends StatelessWidget {
  final AppState a;
  const _MetalSwitch({required this.a});
  @override
  Widget build(BuildContext context) => Glass(
        radius: 26, padding: const EdgeInsets.all(4),
        child: Row(children: [
          for (final m in Metal.values)
            Expanded(
              child: Semantics(
                selected: m == a.metal, button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () { HapticFeedback.selectionClick(); a.pickMetal(m); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 44,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: m == a.metal ? const Color(0x1FFFFFFF) : const Color(0x00000000)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      dot(Color(m.dot)), const SizedBox(width: 8),
                      Text(tr(a.s.lang, m.name), style: inter(14, w: FontWeight.w500, c: m == a.metal ? C.text : C.mute)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      );
}

class _PriceBlock extends StatelessWidget {
  final AppState a;
  final Snapshot x;
  const _PriceBlock({required this.a, required this.x});
  @override
  Widget build(BuildContext context) {
    final tone = C.tone(x.dayChg);
    final arrow = x.dayChg > 0 ? '▲' : (x.dayChg < 0 ? '▼' : '•');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: FittedBox(
                fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: Text(money(a.perGram(x.price, x.metal), a), key: ValueKey('${x.metal}${a.s.cur}'), style: serif(58)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Web button: ask Google AI Mode why the price moved.
          Semantics(
            button: true, label: tr(a.s.lang, 'ask'),
            child: GestureDetector(
              onTap: () { HapticFeedback.lightImpact(); askGoogle(x, a.s.lang); },
              child: Glass(
                radius: 26, padding: EdgeInsets.zero,
                borderColor: tone.withValues(alpha: 0.35),
                child: SizedBox(
                  width: 52, height: 52,
                  child: Stack(alignment: Alignment.center, children: [
                    const Icon(Icons.travel_explore, size: 22, color: C.text),
                    Positioned(right: 11, top: 11, child: dot(tone, 6)),
                  ]),
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Text('$arrow ${pct(x.dayChg)}', style: inter(14, w: FontWeight.w600, c: tone)),
          const SizedBox(width: 8),
          Text('${x.metal.sym} / g', style: inter(12, c: C.mute)),
          if (a.s.cur == 'INR') ...[
            const SizedBox(width: 8),
            Semantics(
              button: true, label: a.s.local ? 'Following ${_source(a, x.metal)} rate. Tap for international spot' : 'International spot price. Tap for India rate',
              child: GestureDetector(
                onTap: () { HapticFeedback.selectionClick(); a.update((s) => s.local = !s.local); },
                child: Container(
                  height: 26, padding: const EdgeInsets.symmetric(horizontal: 10), alignment: Alignment.center,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0x2EFFFFFF)),
                    color: a.s.local ? const Color(0x1AE3C68C) : const Color(0x00000000)),
                  child: Text(a.s.local ? _source(a, x.metal) : 'Spot', style: inter(11, w: FontWeight.w600, c: a.s.local ? C.gold : C.mute)),
                ),
              ),
            ),
          ],
          const Spacer(),
          Semantics(
            label: '${x.streak >= 0 ? 'Up' : 'Down'} ${x.streak.abs()} days in a row',
            child: SizedBox(
              height: 26,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < x.last7.length; i++)
                  Container(
                    width: 5, height: 8.0 + i * 3, margin: const EdgeInsetsDirectional.only(start: 4),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(3),
                      color: (x.last7[i] > 0 ? C.up : C.down).withValues(alpha: 0.35 + i * 0.1)),
                  ),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _ChartCard extends StatefulWidget {
  final AppState a;
  final Metal metal;
  final Color tone;
  const _ChartCard({required this.a, required this.metal, required this.tone});
  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  int? _i; // touched point
  Timer? _hide;

  @override
  void dispose() { _pulse.dispose(); _hide?.cancel(); super.dispose(); }

  void _touch(double dx, double width, int n, {bool autoHide = false}) {
    final i = (dx / (width - 8) * (n - 1)).round().clamp(0, n - 1);
    if (i != _i) HapticFeedback.selectionClick();
    _hide?.cancel();
    setState(() => _i = i);
    if (autoHide) _hide = Timer(const Duration(seconds: 3), () { if (mounted) setState(() => _i = null); });
  }

  void _release() { _hide?.cancel(); _hide = Timer(const Duration(milliseconds: 1200), () { if (mounted) setState(() => _i = null); }); }

  String _when(DateTime t) {
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = '${t.day} ${mo[t.month - 1]}';
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return switch (widget.a.range) { '1D' => hm, '1W' => '$d, $hm', '1Y' => '$d ${t.year}', _ => d };
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final s = a.chartFor(widget.metal);
    final snap = a.snaps[widget.metal];
    // Re-base futures history onto the live spot price (small premium).
    var k = 1.0;
    if (s != null && s.c.isNotEmpty && snap != null) {
      final r = snap.price / s.c.last;
      if ((r - 1).abs() < 0.05) k = r;
    }
    final i = (s != null && _i != null && _i! < s.c.length) ? _i : null;
    return Glass(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(children: [
        SizedBox(
          height: 34,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: i == null || s == null
                ? const SizedBox.shrink()
                : Directionality(
                    key: const ValueKey('tip'),
                    textDirection: TextDirection.ltr,
                    child: Row(children: [
                      Text('${money(a.perGram(s.c[i] * k, widget.metal), a)} / g', style: inter(15, w: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Text(_pctFrom(s.c.first, s.c[i]), style: inter(12, w: FontWeight.w600, c: C.tone(s.c[i] - s.c.first))),
                      const Spacer(),
                      Text(_when(s.t[i]), style: inter(12, c: C.mute)),
                    ]),
                  ),
          ),
        ),
        SizedBox(
          height: 150,
          child: s == null || s.c.length < 2
              ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.mute)))
              : LayoutBuilder(
                  builder: (context, box) => Semantics(
                    label: 'Price chart. Drag to see prices.',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _touch(d.localPosition.dx, box.maxWidth, s.c.length, autoHide: true),
                      onHorizontalDragStart: (d) => _touch(d.localPosition.dx, box.maxWidth, s.c.length),
                      onHorizontalDragUpdate: (d) => _touch(d.localPosition.dx, box.maxWidth, s.c.length),
                      onHorizontalDragEnd: (_) => _release(),
                      onLongPressStart: (d) => _touch(d.localPosition.dx, box.maxWidth, s.c.length),
                      onLongPressMoveUpdate: (d) => _touch(d.localPosition.dx, box.maxWidth, s.c.length),
                      onLongPressEnd: (_) => _release(),
                      child: AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, _) => CustomPaint(size: Size.infinite, painter: _LinePainter(s.c, widget.tone, _pulse.value, i)),
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (final r in rangeSpec.keys)
              Semantics(
                selected: r == a.range, button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () { setState(() => _i = null); a.pickRange(r); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 52, height: 36, alignment: Alignment.center,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: r == a.range ? const Color(0x1AFFFFFF) : const Color(0x00000000)),
                    child: Text(r, style: inter(13, w: FontWeight.w500, c: r == a.range ? C.text : C.mute)),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  String _pctFrom(double a, double b) => a == 0 ? '' : '${b >= a ? '+' : '−'}${((b / a - 1).abs() * 100).toStringAsFixed(2)}%';
}

class _LinePainter extends CustomPainter {
  final List<double> c;
  final Color tone;
  final double t;
  final int? sel;
  _LinePainter(this.c, this.tone, this.t, [this.sel]);

  @override
  void paint(Canvas canvas, Size size) {
    final lo = c.reduce(min), hi = c.reduce(max);
    final span = (hi - lo) == 0 ? 1 : hi - lo;
    Offset pt(int i) => Offset(i / (c.length - 1) * (size.width - 8), 8 + (1 - (c[i] - lo) / span) * (size.height - 16));
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < c.length; i++) {
      final p0 = pt(i - 1), p1 = pt(i);
      final mx = (p0.dx + p1.dx) / 2;
      path.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
    }
    final end = pt(c.length - 1);
    final area = Path.from(path)..lineTo(end.dx, size.height)..lineTo(0, size.height)..close();
    canvas.drawPath(area, Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [tone.withValues(alpha: 0.18), tone.withValues(alpha: 0)],
    ).createShader(Offset.zero & size));
    canvas.drawPath(path, Paint()..color = tone..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.round);
    if (sel != null) {
      final p = pt(sel!);
      canvas.drawLine(Offset(p.dx, 0), Offset(p.dx, size.height), Paint()..color = const Color(0x40FFFFFF)..strokeWidth = 1);
      canvas.drawCircle(p, 9, Paint()..color = tone.withValues(alpha: 0.25));
      canvas.drawCircle(p, 5, Paint()..color = C.bg);
      canvas.drawCircle(p, 5, Paint()..color = tone..style = PaintingStyle.stroke..strokeWidth = 2.5);
      canvas.drawCircle(end, 3, Paint()..color = tone.withValues(alpha: 0.6));
    } else {
      canvas.drawCircle(end, 4 + 9 * t, Paint()..color = tone.withValues(alpha: 0.5 * (1 - t)));
      canvas.drawCircle(end, 4, Paint()..color = tone);
    }
  }

  @override
  bool shouldRepaint(_LinePainter o) => o.t != t || o.c != c || o.tone != tone || o.sel != sel;
}

class _SignalCard extends StatelessWidget {
  final Snapshot x;
  final String l;
  const _SignalCard({required this.x, required this.l});
  @override
  Widget build(BuildContext context) {
    final sd = x.sig == Sig.buy ? 1 : (x.sig == Sig.sell ? -1 : 0);
    final tone = C.tone(sd);
    final inds = <(String, String, int)>[
      (tr(l, 'trend'), x.trend > 0 ? '↑' : (x.trend < 0 ? '↓' : '→'), x.trend),
      ('MA 20', x.aboveMa20 ? '↑' : '↓', x.aboveMa20 ? 1 : -1),
      ('RSI', x.rsi.round().toString(), x.rsi > 70 ? -1 : (x.rsi < 30 ? 1 : 0)),
      ('USD', x.dxyChg < 0 ? '↓' : (x.dxyChg > 0 ? '↑' : '→'), x.dxyChg < 0 ? 1 : (x.dxyChg > 0 ? -1 : 0)),
    ];
    return Glass(
      glow: x.flipped ? [BoxShadow(color: tone.withValues(alpha: 0.18), blurRadius: 40)] : null,
      borderColor: x.flipped ? tone.withValues(alpha: 0.4) : null,
      child: Column(children: [
        Row(children: [
          Semantics(
            label: 'Confidence ${x.conf} percent',
            child: SizedBox(
              width: 64, height: 64,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: x.conf / 100), duration: const Duration(milliseconds: 700), curve: Curves.easeOutCubic,
                builder: (_, v, _) => CustomPaint(
                  painter: _Ring(v, tone),
                  child: Center(child: Text('${x.conf}', style: inter(14, w: FontWeight.w600))),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(tr(l, 'signal').toUpperCase(), style: label()),
                if (x.flipped) ...[const SizedBox(width: 8), dot(tone, 6)],
              ]),
              const SizedBox(height: 6),
              Text(tr(l, x.sig.name), style: serif(42, c: tone)),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          for (final (k, v, s) in inds)
            Expanded(
              child: Container(
                margin: const EdgeInsetsDirectional.only(end: 8),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: const Color(0x0DFFFFFF)),
                child: Column(children: [
                  Text(v, style: inter(16, w: FontWeight.w600, c: s == 0 ? C.mute : C.tone(s))),
                  const SizedBox(height: 4),
                  Text(k, style: inter(11, c: C.mute), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _Ring extends CustomPainter {
  final double v;
  final Color c;
  _Ring(this.v, this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(3, 3, s.width - 6, s.height - 6);
    canvas.drawArc(r, 0, 2 * pi, false, Paint()..color = const Color(0x14FFFFFF)..style = PaintingStyle.stroke..strokeWidth = 5);
    canvas.drawArc(r, -pi / 2, 2 * pi * v, false, Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 5..strokeCap = StrokeCap.round);
  }
  @override
  bool shouldRepaint(_Ring o) => o.v != v || o.c != c;
}

class _WhyCard extends StatefulWidget {
  final Snapshot x;
  final String l;
  const _WhyCard({required this.x, required this.l});
  @override
  State<_WhyCard> createState() => _WhyCardState();
}

class _WhyCardState extends State<_WhyCard> {
  int? open;

  @override
  void didUpdateWidget(_WhyCard old) {
    super.didUpdateWidget(old);
    if (old.x.metal != widget.x.metal) open = null;
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.x, l = widget.l;
    final chg = x.eventChg;
    final calm = chg.abs() < 0.002;
    final ev = calm ? tr(l, 'calm') : '${chg >= 0 ? '+' : '−'}${pct(chg)} · ${x.eventIsHour ? '1h' : '24h'}';
    return Glass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(tr(l, 'why').toUpperCase(), style: label())),
          Directionality(textDirection: TextDirection.ltr, child: Text(ev, style: inter(13, w: FontWeight.w600, c: calm ? C.mute : C.tone(chg)))),
        ]),
        const SizedBox(height: 8),
        for (var i = 0; i < x.reasons.length; i++)
          Semantics(
            button: true, expanded: open == i,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => open = open == i ? null : i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: open == i ? const Color(0x0FFFFFFF) : const Color(0x00000000)),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220), curve: Curves.easeOut, alignment: Alignment.topCenter,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(tr(l, x.reasons[i].key), style: inter(15))),
                      Semantics(
                        label: ['', 'Low', 'Medium', 'High'][x.reasons[i].level] + ' likelihood',
                        child: Row(children: [
                          for (var k = 1; k <= 3; k++)
                            Container(width: 14, height: 4, margin: const EdgeInsetsDirectional.only(start: 3),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(2),
                                color: k <= x.reasons[i].level ? C.text : const Color(0x24FFFFFF))),
                        ]),
                      ),
                    ]),
                    if (open == i) ...[
                      const SizedBox(height: 6),
                      Text(tr(l, '${x.reasons[i].key}_x'), style: inter(13, c: const Color(0xFFB4BAC4), h: 1.45)),
                      if (x.reasons[i].headline != null) ...[
                        const SizedBox(height: 6),
                        Text('“${x.reasons[i].headline}”', style: inter(12, c: C.mute, h: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
