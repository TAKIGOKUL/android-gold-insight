import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum Metal { gold, silver, platinum }

extension MetalInfo on Metal {
  String get sym => const ['XAU', 'XAG', 'XPT'][index];
  String get yahoo => const ['GC=F', 'SI=F', 'PL=F'][index];
  String get news => const ['gold price', 'silver price', 'platinum price'][index];
  int get dot => const [0xFFE3C68C, 0xFFC8CDD6, 0xFFA9C4D4][index];
  int get glow => const [0xFF8A6A2E, 0xFF4A5260, 0xFF2F5566][index];
  bool get industrial => this != Metal.gold;
}

class Series {
  final List<DateTime> t;
  final List<double> c;
  const Series(this.t, this.c);
  bool get isEmpty => c.isEmpty;
  Map<String, dynamic> toJson() => {'t': t.map((e) => e.millisecondsSinceEpoch).toList(), 'c': c};
  factory Series.fromJson(Map<String, dynamic> j) => Series(
      (j['t'] as List).map((e) => DateTime.fromMillisecondsSinceEpoch(e as int)).toList(),
      (j['c'] as List).map((e) => (e as num).toDouble()).toList());
}

const _ua = {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) Insight/1.0'};
const _timeout = Duration(seconds: 15);

/// Chart ranges shown in the UI → Yahoo range/interval.
const rangeSpec = {
  '1D': ['1d', '5m'],
  '1W': ['5d', '30m'],
  '1M': ['1mo', '1d'],
  '6M': ['6mo', '1d'],
  '1Y': ['1y', '1wk'],
};

/// Free sources with limits are fetched at most 3×/day (every 8 h) and cached.
const limitedTtl = Duration(hours: 8);

Future<T> _cached<T>(String key, Duration ttl, Future<T> Function() fetch, T Function(dynamic) decode) async {
  final p = await SharedPreferences.getInstance();
  final at = p.getInt('c_at_$key') ?? 0;
  final raw = p.getString('c_$key');
  final fresh = DateTime.now().millisecondsSinceEpoch - at < ttl.inMilliseconds;
  if (raw != null && fresh) return decode(jsonDecode(raw));
  try {
    final v = await fetch();
    await p.setString('c_$key', jsonEncode(v));
    await p.setInt('c_at_$key', DateTime.now().millisecondsSinceEpoch);
    return v;
  } catch (e) {
    if (raw != null) return decode(jsonDecode(raw));
    rethrow;
  }
}

class Market {
  static Future<Series> chart(String symbol, String range, String interval) async {
    final uri = Uri.https('query1.finance.yahoo.com', '/v8/finance/chart/$symbol',
        {'range': range, 'interval': interval});
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    if ((p.getInt('yahoo_block_until') ?? 0) > now) throw Exception('rate limited');
    final r = await http.get(uri, headers: _ua).timeout(_timeout);
    if (r.statusCode == 429) {
      // Rate-limited: back off to 3 checks a day.
      await p.setInt('yahoo_block_until', now + limitedTtl.inMilliseconds);
      throw Exception('rate limited');
    }
    if (r.statusCode != 200) throw Exception('chart ${r.statusCode}');
    final res = (jsonDecode(r.body)['chart']['result'] as List).first;
    final ts = (res['timestamp'] as List?) ?? const [];
    final cl = (res['indicators']['quote'] as List).first['close'] as List? ?? const [];
    final t = <DateTime>[], c = <double>[];
    for (var i = 0; i < ts.length && i < cl.length; i++) {
      final v = cl[i];
      if (v == null) continue;
      t.add(DateTime.fromMillisecondsSinceEpoch((ts[i] as int) * 1000));
      c.add((v as num).toDouble());
    }
    // Make the last point the live price when Yahoo provides it.
    final live = (res['meta']?['regularMarketPrice'] as num?)?.toDouble();
    if (live != null && c.isNotEmpty) c[c.length - 1] = live;
    return Series(t, c);
  }

  /// Live international spot price (USD per troy oz) from gold-api.com.
  static Future<double> spot(String sym) async {
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    if ((p.getInt('spot_block_until') ?? 0) > now) throw Exception('rate limited');
    final r = await http.get(Uri.parse('https://api.gold-api.com/price/$sym'), headers: _ua).timeout(_timeout);
    if (r.statusCode == 429) {
      await p.setInt('spot_block_until', now + limitedTtl.inMilliseconds);
      throw Exception('rate limited');
    }
    if (r.statusCode != 200) throw Exception('spot ${r.statusCode}');
    final v = (jsonDecode(r.body)['price'] as num).toDouble();
    if (v <= 0) throw Exception('bad spot');
    return v;
  }

  /// India market premium per metal = Indian per-gram rate ÷ (spot per gram × USD/INR).
  /// Scraped Indian rate pages are a limited source → fetched at most 3×/day (cached 8 h).
  static Future<Map<String, double>> indiaPremiums() =>
      _cached('india_prem_v2', limitedTtl, _indiaPremiums, (j) => (j as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())));

  static String _text(String html) => html
      .replaceAll(RegExp(r'<script.*?</script>|<style.*?</style>', dotAll: true), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&#8377;', '₹')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  static double? _num(String? s) => s == null ? null : double.tryParse(s.replaceAll(',', ''));

  /// Indian per-gram reference rates. Gold follows Paytm's published 24K rate (falls back to Groww);
  /// silver follows Groww; platinum follows the Indian market rate (StockeZee). Paytm/PhonePe do not
  /// publish silver or platinum. Output: premium over spot per metal, plus 'gold_paytm' = 1 when Paytm was used.
  static Future<Map<String, double>> _indiaPremiums() async {
    final inr = (await chart('USDINR=X', '1d', '5m')).c.last;
    Future<String> page(String u) async => _text((await http.get(Uri.parse(u), headers: _ua).timeout(_timeout)).body);
    final firstRupee = RegExp(r'₹\s?([0-9][0-9,]*(?:\.[0-9]+)?)');
    final local = <String, double>{};
    final out = <String, double>{};
    try {
      final t = await page('https://paytm.com/tools/gold-rates/gold-rates-india/');
      final v = _num(RegExp(r'24K Gold\s*/g\s*₹\s*([0-9][0-9,]*(?:\.[0-9]+)?)').firstMatch(t)?.group(1));
      if (v != null) { local['gold'] = v; out['gold_paytm'] = 1; }
    } catch (_) {}
    if (!local.containsKey('gold')) {
      try { final v = _num(firstRupee.firstMatch(await page('https://groww.in/gold-rates'))?.group(1)); if (v != null) local['gold'] = v; } catch (_) {}
    }
    try { final v = _num(firstRupee.firstMatch(await page('https://groww.in/silver-rates'))?.group(1)); if (v != null) local['silver'] = v; } catch (_) {}
    try { final v = _num(firstRupee.firstMatch(await page('https://www.stockezee.com/platinum-price-today'))?.group(1)); if (v != null) local['platinum'] = v; } catch (_) {}
    const syms = {'gold': 'XAU', 'silver': 'XAG', 'platinum': 'XPT'};
    for (final e in local.entries) {
      try {
        final spotG = await spot(syms[e.key]!) / 31.1034768 * inr;
        final prem = e.value / spotG;
        if (prem > 0.9 && prem < 1.7) out[e.key] = prem; // sanity check
      } catch (_) {}
    }
    if (!out.keys.any((k) => syms.containsKey(k))) throw Exception('no india rates');
    return out;
  }

  /// USD-based exchange rates, e.g. {'EUR': 0.94, 'INR': 84.4}.
  static Future<Map<String, double>> rates() => _cached('rates', limitedTtl, _rates,
      (j) => (j as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())));

  static Future<Map<String, double>> _rates() async {
    final r = await http.get(Uri.parse('https://open.er-api.com/v6/latest/USD')).timeout(_timeout);
    final j = jsonDecode(r.body);
    return (j['rates'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()));
  }

  /// Recent news headlines for a query (Google News RSS).
  static Future<List<String>> headlines(String query) =>
      _cached('news_$query', limitedTtl, () => _headlines(query), (j) => List<String>.from(j as List));

  static Future<List<String>> _headlines(String query) async {
    final uri = Uri.https('news.google.com', '/rss/search',
        {'q': '$query when:2d', 'hl': 'en-US', 'gl': 'US', 'ceid': 'US:en'});
    final r = await http.get(uri, headers: _ua).timeout(_timeout);
    final out = <String>[];
    for (final m in RegExp(r'<item>.*?<title>(.*?)</title>', dotAll: true).allMatches(r.body)) {
      out.add(_unescape(m.group(1)!.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '')));
      if (out.length >= 25) break;
    }
    return out;
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}
