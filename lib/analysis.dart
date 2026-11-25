import 'dart:math';
import 'market.dart';

enum Sig { buy, hold, sell }

class Reason {
  final String key; // i18n key, e.g. 'd_usd_down'
  final int level; // 1..3 likelihood
  final String? headline; // supporting headline, if any
  const Reason(this.key, this.level, [this.headline]);
  Map<String, dynamic> toJson() => {'k': key, 'l': level, 'h': headline};
  factory Reason.fromJson(Map<String, dynamic> j) => Reason(j['k'], j['l'], j['h']);
}

class Snapshot {
  final Metal metal;
  final double price; // USD per oz
  final double dayChg; // fraction
  final double? hourChg; // fraction over the last hour
  final int streak; // +n up days in a row, -n down days
  final List<int> last7; // +1 / -1 per day
  final Sig sig, prevSig;
  final int conf; // 0..100
  final double rsi;
  final int trend; // -1, 0, 1
  final bool aboveMa20;
  final bool maCross; // 20-day average above 50-day
  final double dxyChg;
  final List<Reason> reasons;
  final DateTime at;

  const Snapshot({
    required this.metal, required this.price, required this.dayChg, required this.hourChg,
    required this.streak, required this.last7, required this.sig, required this.prevSig,
    required this.conf, required this.rsi, required this.trend, required this.aboveMa20, this.maCross = false,
    required this.dxyChg, required this.reasons, required this.at,
  });

  bool get flipped => sig != prevSig;

  /// The move shown in "Why it moved": the last hour if it was sharp, else today.
  double get eventChg => (hourChg != null && hourChg!.abs() >= 0.008) ? hourChg! : dayChg;
  bool get eventIsHour => hourChg != null && hourChg!.abs() >= 0.008;

  Map<String, dynamic> toJson() => {
        'm': metal.index, 'p': price, 'd': dayChg, 'h': hourChg, 's': streak, 'l7': last7,
        'sg': sig.index, 'ps': prevSig.index, 'c': conf, 'r': rsi, 't': trend, 'a': aboveMa20, 'mx': maCross,
        'x': dxyChg, 'rs': reasons.map((e) => e.toJson()).toList(), 'at': at.millisecondsSinceEpoch,
      };
  factory Snapshot.fromJson(Map<String, dynamic> j) => Snapshot(
        metal: Metal.values[j['m']], price: (j['p'] as num).toDouble(), dayChg: (j['d'] as num).toDouble(),
        hourChg: (j['h'] as num?)?.toDouble(), streak: j['s'], last7: List<int>.from(j['l7']),
        sig: Sig.values[j['sg']], prevSig: Sig.values[j['ps']], conf: j['c'], rsi: (j['r'] as num).toDouble(),
        trend: j['t'], aboveMa20: j['a'], maCross: j['mx'] ?? false, dxyChg: (j['x'] as num).toDouble(),
        reasons: (j['rs'] as List).map((e) => Reason.fromJson(Map<String, dynamic>.from(e))).toList(),
        at: DateTime.fromMillisecondsSinceEpoch(j['at']),
      );
}

double _sma(List<double> c, int n) {
  if (c.length < n) return c.isEmpty ? 0 : c.reduce((a, b) => a + b) / c.length;
  return c.sublist(c.length - n).reduce((a, b) => a + b) / n;
}

double rsi14(List<double> c) {
  if (c.length < 15) return 50;
  double g = 0, l = 0;
  for (var i = c.length - 14; i < c.length; i++) {
    final d = c[i] - c[i - 1];
    if (d > 0) g += d; else l -= d;
  }
  if (l == 0) return 100;
  return 100 - 100 / (1 + g / l);
}

double _chg(List<double> c) => c.length < 2 || c[c.length - 2] == 0 ? 0 : c.last / c[c.length - 2] - 1;

/// Score-based signal. Positive = bullish.
(Sig, int, int, bool) signalFor(List<double> c, double dxyChg) {
  final ma20 = _sma(c, 20), ma50 = _sma(c, 50), r = rsi14(c);
  final above = c.last > ma20;
  final ma20Prev = c.length > 25 ? _sma(c.sublist(0, c.length - 5), 20) : ma20;
  final trend = ma20 > ma20Prev * 1.002 ? 1 : (ma20 < ma20Prev * 0.998 ? -1 : 0);
  var s = 0.0;
  s += above ? 1 : -1;
  s += ma20 > ma50 ? 1 : -1;
  s += trend * 0.5;
  if (r > 70) s -= 1; else if (r < 30) s += 1; else s += r >= 50 ? 0.5 : -0.5;
  s += dxyChg < -0.002 ? 0.5 : (dxyChg > 0.002 ? -0.5 : 0);
  final sig = s >= 1.5 ? Sig.buy : (s <= -1.5 ? Sig.sell : Sig.hold);
  final conf = (50 + min(s.abs(), 4.5) / 4.5 * 45).round();
  return (sig, conf, trend, above);
}

/// Keyword drivers. dir: expected effect on the metal (+1 up / -1 down / 0 either).
const _drivers = <(String, int, List<String>, bool)>[
  ('d_rates_up', 1, ['rate cut', 'rate-cut', 'dovish', 'easing', 'cut rates', 'cuts rates'], false),
  ('d_rates_down', -1, ['hawkish', 'rate hike', 'higher for longer', 'hike rates', 'hawk'], false),
  ('d_infl', 0, ['inflation', 'cpi', 'pce', 'consumer prices'], false),
  ('d_geo', 1, ['war', 'conflict', 'tension', 'attack', 'missile', 'sanction', 'geopolit', 'safe haven', 'safe-haven', 'crisis'], false),
  ('d_cb', 1, ['central bank', 'pboc', 'reserves', 'rbi buys', 'central-bank'], false),
  ('d_ind_up', 1, ['solar', 'industrial demand', 'ev demand', 'pmi rises', 'factory activity expands', 'deficit'], true),
  ('d_ind_down', -1, ['factory', 'pmi', 'auto sales', 'car sales', 'slowdown', 'weak demand', 'industrial'], true),
  ('d_supply', 0, ['mine', 'mining', 'supply', 'output', 'strike', 'south africa', 'production'], false),
  ('d_profit', -1, ['profit-taking', 'profit taking', 'pullback', 'correction', 'retreat'], false),
  ('d_trade', 0, ['tariff', 'trade war', 'trade deal', 'trade talks'], false),
  ('d_etf', 0, ['etf', 'inflows', 'outflows', 'holdings'], false),
];

List<Reason> reasonsFor(Metal m, double move, double dxyChg, double tnxChg, List<String> news) {
  final dir = move >= 0 ? 1 : -1;
  final scores = <String, double>{};
  final heads = <String, String>{};

  // Quantitative cross-asset evidence (strongest).
  if (dxyChg.abs() > 0.0015 && (dxyChg < 0) == (dir > 0)) {
    final k = dxyChg < 0 ? 'd_usd_down' : 'd_usd_up';
    scores[k] = 2 + min(dxyChg.abs() * 300, 2);
  }
  if (tnxChg.abs() > 0.008 && (tnxChg < 0) == (dir > 0)) {
    final k = tnxChg < 0 ? 'd_yield_down' : 'd_yield_up';
    scores[k] = 1.5 + min(tnxChg.abs() * 40, 1.5);
  }

  // Headline evidence: count keyword hits, keep drivers consistent with the move.
  for (final h in news) {
    final low = h.toLowerCase();
    for (final (key, d, words, industrialOnly) in _drivers) {
      if (industrialOnly && !m.industrial) continue;
      if (d != 0 && d != dir) continue;
      if (words.any(low.contains)) {
        scores[key] = (scores[key] ?? 0) + 1;
        heads.putIfAbsent(key, () => h);
      }
      if (low.contains('dollar') && scores.containsKey(dir > 0 ? 'd_usd_down' : 'd_usd_up')) {
        heads.putIfAbsent(dir > 0 ? 'd_usd_down' : 'd_usd_up', () => h);
      }
    }
  }

  if (scores.isEmpty) scores['d_tech'] = 1;
  if (dir < 0 && move.abs() > 0.01 && !scores.containsKey('d_profit')) scores['d_profit'] = 0.6;

  final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final top = ranked.first.value;
  return ranked.take(3).map((e) {
    final rel = e.value / top;
    final lvl = rel > 0.8 ? 3 : (rel > 0.45 ? 2 : 1);
    return Reason(e.key, lvl, heads[e.key]);
  }).toList();
}

Snapshot analyze({
  required Metal metal,
  required Series daily,
  Series? intraday,
  Series? dxy,
  Series? tnx,
  List<String> news = const [],
}) {
  final c = daily.c;
  final dxyChg = dxy == null || dxy.isEmpty ? 0.0 : _chg(dxy.c);
  final tnxChg = tnx == null || tnx.isEmpty ? 0.0 : _chg(tnx.c);

  // Streak of consecutive up/down closes.
  var streak = 0;
  for (var i = c.length - 1; i > 0; i--) {
    final d = c[i] > c[i - 1] ? 1 : (c[i] < c[i - 1] ? -1 : 0);
    if (d == 0) break;
    if (streak == 0 || d.sign == streak.sign) { streak += d; } else { break; }
  }
  final last7 = <int>[];
  for (var i = max(1, c.length - 7); i < c.length; i++) { last7.add(c[i] >= c[i - 1] ? 1 : -1); }

  double? hourChg;
  if (intraday != null && intraday.c.length > 13) {
    final ic = intraday.c;
    final cut = intraday.t.last.subtract(const Duration(hours: 1));
    var j = ic.length - 1;
    while (j > 0 && intraday.t[j].isAfter(cut)) { j--; }
    if (ic[j] != 0) hourChg = ic.last / ic[j] - 1;
  }

  final (sig, conf, trend, above) = signalFor(c, dxyChg);
  final (prev, _, _, _) = c.length > 21 ? signalFor(c.sublist(0, c.length - 1), 0) : (sig, 0, 0, false);
  final dayChg = _chg(c);
  final move = (hourChg != null && hourChg.abs() >= 0.008) ? hourChg : dayChg;

  return Snapshot(
    metal: metal, price: c.last, dayChg: dayChg, hourChg: hourChg, streak: streak, last7: last7,
    sig: sig, prevSig: prev, conf: conf, rsi: rsi14(c), trend: trend, aboveMa20: above, maCross: _sma(c, 20) > _sma(c, 50), dxyChg: dxyChg,
    reasons: reasonsFor(metal, move, dxyChg, tnxChg, news), at: DateTime.now(),
  );
}

/// Fetch everything needed for one metal and analyze it.
Future<Snapshot> fetchSnapshot(Metal m, {Series? dxy, Series? tnx}) async {
  final results = await Future.wait([
    Market.chart(m.yahoo, '6mo', '1d'),
    Market.spot(m.sym).then<double?>((v) => v).catchError((_) => null),
    Market.chart(m.yahoo, '1d', '5m').then<Series?>((v) => v).catchError((_) => null),
    Market.headlines(m.news).catchError((_) => <String>[]),
  ]);
  var daily = results[0] as Series;
  var intraday = results[2] as Series?;
  // Futures trade at a small premium to spot. Re-base the futures series onto the live
  // spot price so the headline price is spot while % moves and indicators stay intact.
  final spot = results[1] as double?;
  if (spot != null && daily.c.isNotEmpty && daily.c.last > 0) {
    final k = spot / daily.c.last;
    if ((k - 1).abs() < 0.05) {
      daily = Series(daily.t, daily.c.map((v) => v * k).toList());
      if (intraday != null) intraday = Series(intraday.t, intraday.c.map((v) => v * k).toList());
    }
  }
  return analyze(
    metal: m, daily: daily, intraday: intraday,
    dxy: dxy, tnx: tnx, news: results[3] as List<String>,
  );
}

Future<(Series?, Series?)> fetchMacro() async {
  Future<Series?> safe(String s) => Market.chart(s, '5d', '1d').then<Series?>((v) => v).catchError((_) => null);
  final r = await Future.wait([safe('DX-Y.NYB'), safe('^TNX')]);
  return (r[0], r[1]);
}
