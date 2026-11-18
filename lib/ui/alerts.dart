import 'package:material_ui/material_ui.dart';
import '../i18n.dart';
import '../market.dart';
import '../notify.dart';
import '../state.dart';
import 'glass.dart';
import 'today.dart' show money, ElementTile;

class AlertsPage extends StatelessWidget {
  final AppState a;
  const AlertsPage({super.key, required this.a});

  @override
  Widget build(BuildContext context) {
    final s = a.s, l = s.lang;
    Widget section(String k) => Padding(padding: const EdgeInsets.fromLTRB(4, 22, 4, 10), child: Text(tr(l, k).toUpperCase(), style: label()));

    final rules = <(String icon, Color c, String key, bool on, String? val, VoidCallback? dec, VoidCallback? inc, ValueChanged<bool> set)>[
      ('▲', C.up, 'rising', s.rise, '${s.riseDays} d', () => a.update((x) => x.riseDays = (x.riseDays - 1).clamp(1, 7)),
        () => a.update((x) => x.riseDays = (x.riseDays + 1).clamp(1, 7)), (v) => a.update((x) => x.rise = v)),
      ('▼', C.down, 'falling', s.fall, '${s.fallDays} d', () => a.update((x) => x.fallDays = (x.fallDays - 1).clamp(1, 7)),
        () => a.update((x) => x.fallDays = (x.fallDays + 1).clamp(1, 7)), (v) => a.update((x) => x.fall = v)),
      ('⇅', C.gold, 'flip', s.flip, null, null, null, (v) => a.update((x) => x.flip = v)),
      ('ϟ', C.gold, 'sudden', s.spike, '${s.spikePct.toStringAsFixed(1)}%/h',
        () => a.update((x) => x.spikePct = (x.spikePct - 0.5).clamp(0.5, 5.0)),
        () => a.update((x) => x.spikePct = (x.spikePct + 0.5).clamp(0.5, 5.0)), (v) => a.update((x) => x.spike = v)),
      ('☾', C.mute, 'quiet', s.quiet, null, null, null, (v) => a.update((x) => x.quiet = v)),
    ];

    const lvColor = C.gold;
    final lvTag = 'Insight · ${tr(l, 'important')}';
    final g = a.snaps[Metal.gold];

    return ListView(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 130),
      children: [
        SizedBox(height: 44, child: Align(alignment: AlignmentDirectional.centerStart, child: Text(tr(l, 'alerts'), style: inter(17, w: FontWeight.w600)))),
        const SizedBox(height: 14),

        // Live preview of how a notification will look at the chosen importance.
        Glass(
          radius: 24, padding: const EdgeInsets.all(14),
          borderColor: lvColor.withValues(alpha: 0.5),
                    child: Row(children: [
            const ElementTile(size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(lvTag, style: inter(12, w: FontWeight.w600, c: lvColor)),
                const SizedBox(height: 2),
                Text(g == null ? tr(l, 'nRise', {'m': tr(l, 'gold'), 'n': '2'}) : tr(l, 'nFlip', {'m': tr(l, 'gold'), 's': tr(l, g.sig.name)}),
                  style: inter(14, w: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            Pill(
              height: 36, selected: false,
              onTap: () async {
                await Notifier.requestPermissions();
                await Notifier.show(1, tr(l, 'nFlip', {'m': tr(l, 'gold'), 's': tr(l, g?.sig.name ?? 'buy')}),
                  g == null ? tr(l, 'nTap') : '${money(a.perGram(g.price, Metal.gold), a)}/g · ${tr(l, g.reasons.first.key)}', 1);
              },
              child: Text(tr(l, 'test')),
            ),
          ]),
        ),

        section('watch'),
        Row(children: [
          for (final m in Metal.values)
            Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(end: m == Metal.platinum ? 0 : 8),
                child: Pill(
                  selected: s.watch.contains(m),
                  onTap: () => a.update((x) => x.watch.contains(m) ? x.watch.remove(m) : x.watch.add(m)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [dot(Color(m.dot)), const SizedBox(width: 8),
                    Flexible(child: Text(tr(l, m.name), maxLines: 1, overflow: TextOverflow.ellipsis))]),
                ),
              ),
            ),
        ]),

        section('notify'),
        Glass(
          radius: 24, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [
            for (var i = 0; i < rules.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(border: i < rules.length - 1 ? const Border(bottom: BorderSide(color: C.line)) : null),
                child: Row(children: [
                  Container(width: 32, height: 32, alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0x0FFFFFFF), borderRadius: BorderRadius.circular(10)),
                    child: Text(rules[i].$1, style: inter(14, c: rules[i].$2))),
                  const SizedBox(width: 12),
                  Expanded(child: Text(tr(l, rules[i].$3), style: inter(15))),
                  if (rules[i].$5 != null)
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200), opacity: rules[i].$4 ? 1 : 0.35,
                      child: Row(children: [
                        _Step('−', rules[i].$6!),
                        SizedBox(width: 56, child: Text(rules[i].$5!, textAlign: TextAlign.center, style: inter(13))),
                        _Step('+', rules[i].$7!),
                      ]),
                    ),
                  GlassSwitch(value: rules[i].$4, onChanged: rules[i].$8, label: tr(l, rules[i].$3)),
                ]),
              ),
          ]),
        ),

        section('targets'),
        Glass(
          radius: 24, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [
            for (final t in s.targets)
              Container(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.line))),
                child: Row(children: [
                  dot(Color(t.metal.dot)), const SizedBox(width: 10),
                  Expanded(child: Text('${tr(l, t.metal.name)} ${t.above ? '≥' : '≤'} ${money(a.perGram(t.usd, t.metal), a)} / g', style: inter(15))),
                  Semantics(
                    button: true, label: 'Remove',
                    child: GestureDetector(
                      onTap: () => a.update((x) => x.targets.remove(t)),
                      child: const SizedBox(width: 44, height: 48, child: Center(child: Text('×', style: TextStyle(fontSize: 20, color: C.mute)))),
                    ),
                  ),
                ]),
              ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _addTarget(context),
              child: SizedBox(height: 52, child: Align(alignment: AlignmentDirectional.centerStart,
                child: Text(tr(l, 'addTarget'), style: inter(15, w: FontWeight.w500, c: C.gold)))),
            ),
          ]),
        ),
      ],
    );
  }

  void _addTarget(BuildContext context) {
    final l = a.s.lang;
    var metal = a.metal;
    var above = true;
    final ctrl = TextEditingController(text: a.snaps[metal] == null ? '' : (a.perGram(a.snaps[metal]!.price, metal) * a.rate).toStringAsFixed(2));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0x00000000),
      barrierColor: const Color(0x66000000),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Glass(
            radius: 32,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, children: [
                for (final m in Metal.values)
                  Pill(selected: metal == m, onTap: () => set(() {
                    metal = m;
                    if (a.snaps[m] != null) ctrl.text = (a.perGram(a.snaps[m]!.price, m) * a.rate).toStringAsFixed(2);
                  }), child: Text(tr(l, m.name))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Pill(selected: above, onTap: () => set(() => above = true), child: Text('≥ ${tr(l, 'above')}')),
                const SizedBox(width: 8),
                Pill(selected: !above, onTap: () => set(() => above = false), child: Text('≤ ${tr(l, 'below')}')),
              ]),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl, autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: serif(40), cursorColor: C.gold,
                decoration: InputDecoration(
                  labelText: tr(l, 'price'), labelStyle: inter(13, c: C.mute),
                  prefixText: '${a.sym} ', suffixText: '/ g', suffixStyle: inter(16, c: C.mute), prefixStyle: serif(40, c: C.gold),
                  border: InputBorder.none,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: Pill(
                  height: 52, selected: true, accent: C.gold,
                  onTap: () {
                    final v = double.tryParse(ctrl.text.replaceAll(',', ''));
                    if (v == null || v <= 0) return;
                    a.update((x) => x.targets.add(Target(metal, above, v / a.rate / a.factor(metal) * ozG)));
                    Navigator.of(ctx).pop();
                  },
                  child: Text(tr(l, 'save')),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String t;
  final VoidCallback onTap;
  const _Step(this.t, this.onTap);
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: t == '+' ? 'Increase' : 'Decrease',
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 36, height: 44,
            child: Center(child: Container(width: 30, height: 30, alignment: Alignment.center,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x14FFFFFF)),
              child: Text(t, style: inter(16, w: FontWeight.w500)))),
          ),
        ),
      );
}
