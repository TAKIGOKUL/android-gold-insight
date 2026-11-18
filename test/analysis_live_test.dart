import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:insight/analysis.dart';
import 'package:insight/market.dart';
import 'package:insight/state.dart';

void main() {
  test('live snapshot for all metals', () async {
    SharedPreferences.setMockInitialValues({});
    final macro = await fetchMacro();
    for (final m in Metal.values) {
      final x = await fetchSnapshot(m, dxy: macro.$1, tnx: macro.$2);
      // ignore: avoid_print
      print('${m.name}: \$${x.price.toStringAsFixed(2)} day ${(x.dayChg*100).toStringAsFixed(2)}% hour ${x.hourChg == null ? '-' : (x.hourChg!*100).toStringAsFixed(2)} streak ${x.streak} sig ${x.sig.name} (${x.conf}) prev ${x.prevSig.name} rsi ${x.rsi.round()} reasons ${x.reasons.map((r) => '${r.key}:${r.level}').join(', ')}');
      expect(x.price, greaterThan(0));
    }
    final r = await Market.rates();
    expect(r['INR'], isNotNull);
    final st = Settings()..cur = 'INR';
    final prem = await Market.indiaPremiums();
    for (final m in Metal.values) {
      final x = await fetchSnapshot(m, dxy: macro.$1, tnx: macro.$2);
      final spotG = x.price / ozG * r['INR']!;
      // ignore: avoid_print
      print('${m.name} INR/g spot ${spotG.toStringAsFixed(2)}  India ${(spotG * localFactor(st, m, prem)).toStringAsFixed(2)}  premium ${prem[m.name]}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
