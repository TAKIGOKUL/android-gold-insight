import 'dart:ui' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'analysis.dart';
import 'i18n.dart';
import 'market.dart';
import 'state.dart';

const _channels = [
  ('insight_normal', 'Normal alerts', Importance.defaultImportance),
  ('insight_important', 'Important alerts', Importance.high),
  ('insight_critical', 'Critical alerts', Importance.max),
];

class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_stat_insight')),
      );
    } catch (_) {
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      );
    }
    for (final (id, name, imp) in _channels) {
      final critical = imp == Importance.max;
      await _android?.createNotificationChannel(AndroidNotificationChannel(
        id, name,
        importance: imp,
        bypassDnd: critical,
        audioAttributesUsage: critical ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
        vibrationPattern: null,
      ));
    }
    _ready = true;
  }

  static Future<void> requestPermissions({bool critical = false}) async {
    await _android?.requestNotificationsPermission();
    if (critical) await _android?.requestNotificationPolicyAccess();
  }

  /// level: 0 normal, 1 important, 2 critical
  static Future<void> show(int id, String title, String body, int level) async {
    await init();
    final (ch, name, imp) = _channels[level.clamp(0, 2)];
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          ch, name,
          icon: '@drawable/ic_stat_insight',
          importance: imp,
          priority: level >= 1 ? Priority.high : Priority.defaultPriority,
          color: const Color(0xFFE3C68C),
          category: level == 2 ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.recommendation,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
    );
  }
}

/// usd is per troy ounce; shown per gram.
String _fmt(double usd, double rate, String sym, [double f = 1]) {
  final v = usd / ozG * rate * f;
  return '$sym${v.toStringAsFixed(v >= 10000 ? 0 : 2)}';
}

String _pct(double f) => '${f >= 0 ? '+' : '−'}${(f.abs() * 100).toStringAsFixed(1)}%';

/// Evaluate all alert rules for fresh snapshots and post notifications (deduplicated).
Future<int> runCheck() async {
  final s = await Settings.load();
  final p = await SharedPreferences.getInstance();
  const l = 'en';
  final rate = s.cur == 'INR' ? (await _rate(p, 'INR')) : 1.0;
  final sym = currencies.firstWhere((c) => c.$1 == s.cur, orElse: () => currencies.first).$2;
  final now = DateTime.now();
  final day = '${now.year}-${now.month}-${now.day}';
  final quietNow = s.quiet && (now.hour >= 22 || now.hour < 7);
  var sent = 0;

  final macro = await fetchMacro();
  Map<String, double> prem = {};
  if (s.cur == 'INR') { try { prem = await Market.indiaPremiums(); } catch (_) {} }
  for (final m in s.watch) {
    Snapshot x;
    try { x = await fetchSnapshot(m, dxy: macro.$1, tnx: macro.$2); } catch (_) { continue; }
    final name = tr(l, m.name);
    final f = localFactor(s, m, prem);
    final why = x.reasons.isEmpty ? '' : '\n${tr(l, x.reasons.first.key)} · ${tr(l, 'nTap')}';
    final events = <(String key, String title, String body, bool priority)>[];

    if (s.rise && x.streak >= s.riseDays) {
      events.add(('rise_${m.name}_$day', tr(l, 'nRise', {'m': name, 'n': '${x.streak}'}), '${_fmt(x.price, rate, sym, f)} · ${_pct(x.dayChg)}$why', false));
    }
    if (s.fall && -x.streak >= s.fallDays) {
      events.add(('fall_${m.name}_$day', tr(l, 'nFall', {'m': name, 'n': '${-x.streak}'}), '${_fmt(x.price, rate, sym, f)} · ${_pct(x.dayChg)}$why', false));
    }
    if (s.flip) {
      final last = p.getInt('sig_${m.name}');
      if (last != null && last != x.sig.index) {
        events.add(('flip_${m.name}_${now.millisecondsSinceEpoch}', tr(l, 'nFlip', {'m': name, 's': tr(l, x.sig.name)}),
            '${x.conf}% · ${_fmt(x.price, rate, sym, f)}$why', s.pri.contains('flip')));
      }
      await p.setInt('sig_${m.name}', x.sig.index);
    }
    final h = x.hourChg;
    if (s.spike && h != null && h.abs() * 100 >= s.spikePct) {
      events.add(('spike_${m.name}_${day}_${now.hour}', tr(l, 'nSpike', {'m': name, 'c': _pct(h)}), '${_fmt(x.price, rate, sym, f)}$why',
          s.pri.contains('big') && h.abs() >= 0.03));
    }
    for (final t in s.targets.where((t) => t.metal == m)) {
      final hit = t.above ? x.price >= t.usd : x.price <= t.usd;
      final was = p.getBool('tgt_${t.id}') ?? false;
      if (hit && !was) {
        events.add(('tgt_${t.id}_$day', tr(l, 'nTarget', {'m': name, 'p': _fmt(t.usd, rate, sym, f)}), _fmt(x.price, rate, sym, f), s.pri.contains('target')));
      }
      await p.setBool('tgt_${t.id}', hit);
    }

    for (final (key, title, body, pri) in events) {
      if (p.getBool('sent_$key') ?? false) continue;
      const level = 1; // all alerts are sent as Important
      if (quietNow) continue;
      await Notifier.show(key.hashCode & 0x7fffffff, title, body, level);
      await p.setBool('sent_$key', true);
      sent++;
    }
  }
  return sent;
}

Future<double> _rate(SharedPreferences p, String cur) async {
  try {
    final r = await Market.rates();
    return r[cur] ?? 1;
  } catch (_) {
    return 1;
  }
}

/// Which brief slot (9 AM / 9 PM) is due now, if any. A slot stays due until 3 h later,
/// so a delayed background run still delivers it (deduplicated per day).
String? dueDigest(DateTime now) {
  if (now.hour >= 9 && now.hour < 12) return 'am';
  if (now.hour >= 21) return 'pm';
  return null;
}

/// Daily brief: one line per watched metal (price per gram, day change, signal).
Future<bool> sendDigest(String slot) async {
  final s = await Settings.load();
  final p = await SharedPreferences.getInstance();
  final now = DateTime.now();
  final key = 'digest_${slot}_${now.year}-${now.month}-${now.day}';
  if (p.getBool(key) ?? false) return false;
  final rate = s.cur == 'INR' ? (await _rate(p, 'INR')) : 1.0;
  final sym = currencies.firstWhere((c) => c.$1 == s.cur, orElse: () => currencies.first).$2;
  Map<String, double> prem = {};
  if (s.cur == 'INR') { try { prem = await Market.indiaPremiums(); } catch (_) {} }
  final macro = await fetchMacro();
  final lines = <String>[];
  for (final m in Metal.values.where(s.watch.contains)) {
    try {
      final x = await fetchSnapshot(m, dxy: macro.$1, tnx: macro.$2);
      final arrow = x.dayChg >= 0 ? '▲' : '▼';
      lines.add('${tr('en', m.name)}  ${_fmt(x.price, rate, sym, localFactor(s, m, prem))}/g  $arrow${(x.dayChg.abs() * 100).toStringAsFixed(2)}%  · ${tr('en', x.sig.name)}');
    } catch (_) {}
  }
  if (lines.isEmpty) return false;
  await Notifier.show(slot == 'am' ? 9009 : 2121, slot == 'am' ? 'Morning brief · 9 AM' : 'Evening brief · 9 PM', lines.join('\n'), 1);
  await p.setBool(key, true);
  return true;
}

/// Schedule a one-off task at the next 9:00 or 21:00 (precise trigger; periodic check is the fallback).
Future<void> scheduleNextDigest() async {
  final now = DateTime.now();
  final targets = [
    DateTime(now.year, now.month, now.day, 9),
    DateTime(now.year, now.month, now.day, 21),
    DateTime(now.year, now.month, now.day + 1, 9),
  ];
  final next = targets.firstWhere((t) => t.isAfter(now.add(const Duration(minutes: 1))));
  await Workmanager().registerOneOffTask(
    'insight-digest', 'digest',
    initialDelay: next.difference(now),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      if (task == 'digest') {
        final slot = dueDigest(DateTime.now());
        if (slot != null) await sendDigest(slot);
        await scheduleNextDigest();
      } else {
        await runCheck();
        final slot = dueDigest(DateTime.now());
        if (slot != null) await sendDigest(slot);
      }
    } catch (_) {}
    return true;
  });
}
