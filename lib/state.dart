import 'dart:async';
import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'analysis.dart';
import 'market.dart';

class Target {
  final Metal metal;
  final bool above;
  final double usd;
  const Target(this.metal, this.above, this.usd);
  String get id => '${metal.name}_${above ? 'a' : 'b'}_${usd.toStringAsFixed(2)}';
  Map<String, dynamic> toJson() => {'m': metal.index, 'a': above, 'u': usd};
  factory Target.fromJson(Map<String, dynamic> j) => Target(Metal.values[j['m']], j['a'], (j['u'] as num).toDouble());
}

class Settings {
  Set<Metal> watch = {Metal.gold, Metal.silver, Metal.platinum};
  bool rise = true, fall = true, flip = true, spike = true, quiet = false;
  int riseDays = 2, fallDays = 2;
  double spikePct = 1.0;
  int level = 1; // 0 normal, 1 important, 2 critical — applied to priority events
  Set<String> pri = {'flip', 'big'};
  List<Target> targets = [];
  String cur = 'USD';
  String lang = 'en';
  bool local = true; // INR: show India price incl. import duty + GST

  Map<String, dynamic> toJson() => {
        'w': watch.map((e) => e.index).toList(), 'r': rise, 'f': fall, 'fl': flip, 's': spike, 'q': quiet,
        'rd': riseDays, 'fd': fallDays, 'sp': spikePct, 'lv': level, 'p': pri.toList(),
        't': targets.map((e) => e.toJson()).toList(), 'c': cur, 'l': lang, 'lo': local,
      };

  static Settings fromJson(Map<String, dynamic> j) => Settings()
    ..watch = (j['w'] as List).map((e) => Metal.values[e as int]).toSet()
    ..rise = j['r'] ?? true
    ..fall = j['f'] ?? true
    ..flip = j['fl'] ?? true
    ..spike = j['s'] ?? true
    ..quiet = j['q'] ?? false
    ..riseDays = j['rd'] ?? 2
    ..fallDays = j['fd'] ?? 2
    ..spikePct = (j['sp'] as num?)?.toDouble() ?? 1.0
    ..level = j['lv'] ?? 1
    ..pri = Set<String>.from(j['p'] ?? const ['flip', 'big'])
    ..targets = ((j['t'] as List?) ?? const []).map((e) => Target.fromJson(Map<String, dynamic>.from(e))).toList()
    ..cur = j['c'] ?? 'USD'
    ..lang = j['l'] ?? 'en'
    ..local = j['lo'] ?? true;

  static Future<Settings> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('settings');
    if (raw == null) return Settings();
    try { return fromJson(jsonDecode(raw)); } catch (_) { return Settings(); }
  }

  Future<void> save() async => (await SharedPreferences.getInstance()).setString('settings', jsonEncode(toJson()));
}

/// Troy ounce → grams. Sources quote per oz; the app shows per gram.
const ozG = 31.1034768;

/// India landed price = spot × (1 + customs duty) × (1 + 3% GST). Duty since 13 May 2026:
/// gold & silver ~15%, platinum 15.4%.
const indiaDuty = {Metal.gold: 0.15, Metal.silver: 0.15, Metal.platinum: 0.154};
/// India factor: measured market premium when available, else duty + GST formula.
double localFactor(Settings s, Metal m, [Map<String, double> prem = const {}]) =>
    (s.cur == 'INR' && s.local) ? (prem[m.name] ?? (1 + indiaDuty[m]!) * 1.03) : 1.0;

const currencies = <(String, String)>[('USD', '\$'), ('INR', '₹')];

class AppState extends ChangeNotifier {
  Settings s = Settings();
  Map<String, double> rates = {'USD': 1};
  final Map<Metal, Snapshot> snaps = {};
  final Map<String, Series> charts = {}; // key: metal|range
  Metal metal = Metal.gold;
  String range = '1W';
  bool offline = false, loading = false;
  Timer? _timer;

  String get sym => currencies.firstWhere((c) => c.$1 == s.cur).$2;
  double get rate => rates[s.cur] ?? 1;
  Map<String, double> premiums = {};
  double factor(Metal m) => localFactor(s, m, premiums);
  /// Display price per gram in the chosen currency (USD-per-oz in).
  double perGram(double usdOz, Metal m) => usdOz / ozG * factor(m);

  Future<void> load() async {
    s = await Settings.load();
    if (!currencies.any((c) => c.$1 == s.cur)) s.cur = 'USD';
    s.lang = 'en'; // English only
    final p = await SharedPreferences.getInstance();
    try {
      final r = p.getString('rates');
      if (r != null) rates = Map<String, double>.from((jsonDecode(r) as Map).map((k, v) => MapEntry(k, (v as num).toDouble())));
      final sn = p.getString('snaps');
      if (sn != null) {
        for (final e in (jsonDecode(sn) as List)) {
          final x = Snapshot.fromJson(Map<String, dynamic>.from(e));
          snaps[x.metal] = x;
        }
      }
    } catch (_) {}
    refresh();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => refresh(quiet: true));
  }

  Future<void> refresh({bool quiet = false}) async {
    if (loading) return;
    loading = true;
    if (!quiet) notifyListeners();
    try {
      final macro = await fetchMacro();
      final res = await Future.wait(Metal.values.map((m) => fetchSnapshot(m, dxy: macro.$1, tnx: macro.$2)));
      for (final x in res) { snaps[x.metal] = x; }
      offline = false;
      final p = await SharedPreferences.getInstance();
      p.setString('snaps', jsonEncode(res.map((e) => e.toJson()).toList()));
      try { premiums = await Market.indiaPremiums(); } catch (_) {}
      try {
        rates = await Market.rates();
        p.setString('rates', jsonEncode(rates));
      } catch (_) {}
      for (final m in Metal.values) { await loadChart(m: m, force: true); }
    } catch (_) {
      offline = true;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> loadChart({Metal? m, bool force = false}) async {
    final mm = m ?? metal;
    final key = '${mm.name}|$range';
    if (!force && charts.containsKey(key)) return;
    try {
      final spec = rangeSpec[range]!;
      charts[key] = await Market.chart(mm.yahoo, spec[0], spec[1]);
      notifyListeners();
    } catch (_) {}
  }

  Series? chartFor(Metal m) => charts['${m.name}|$range'];

  void pickMetal(Metal m) { if (m == metal) return; metal = m; notifyListeners(); loadChart(); }
  void pickRange(String r) {
    range = r; notifyListeners();
    for (final m in Metal.values) { loadChart(m: m); }
  }
  void update(void Function(Settings) f) { f(s); s.save(); notifyListeners(); }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
}
