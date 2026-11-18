import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:workmanager/workmanager.dart';
import 'i18n.dart';
import 'market.dart';
import 'notify.dart';
import 'state.dart';
import 'ui/alerts.dart';
import 'ui/glass.dart';
import 'ui/today.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0x00000000),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await Notifier.init();
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    'insight-check', 'check',
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
  await scheduleNextDigest();
  final state = AppState();
  await state.load();
  runApp(InsightApp(a: state));
  Notifier.requestPermissions();
}

class InsightApp extends StatelessWidget {
  final AppState a;
  const InsightApp({super.key, required this.a});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Insight',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: C.bg, colorSchemeSeed: C.gold),
        home: Shell(a: a),
      );
}

class Shell extends StatefulWidget {
  final AppState a;
  const Shell({super.key, required this.a});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.a,
        builder: (context, _) {
          final a = widget.a, l = a.s.lang;
          return Directionality(
            textDirection: TextDirection.ltr,
            child: Scaffold(
              backgroundColor: C.bg,
              body: Ambient(
                glow: Color(a.metal.glow),
                child: Stack(children: [
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      child: tab == 0 ? TodayPage(key: const ValueKey(0), a: a) : AlertsPage(key: const ValueKey(1), a: a),
                    ),
                  ),
                  Positioned(
                    left: 0, right: 0, bottom: MediaQuery.of(context).padding.bottom + 20,
                    child: Center(
                      child: SizedBox(
                        width: 250,
                        child: Glass(
                          radius: 30, padding: const EdgeInsets.all(6),
                          child: Row(children: [
                            for (var i = 0; i < 2; i++)
                              Expanded(
                                child: Semantics(
                                  selected: tab == i, button: true,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () { HapticFeedback.selectionClick(); setState(() => tab = i); },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 250),
                                      height: 48, alignment: Alignment.center,
                                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
                                        color: tab == i ? const Color(0x1FFFFFFF) : const Color(0x00000000)),
                                      child: Text(tr(l, i == 0 ? 'today' : 'alerts'),
                                        style: inter(14, w: FontWeight.w500, c: tab == i ? C.text : C.mute)),
                                    ),
                                  ),
                                ),
                              ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      );
}
