// Renders Play Store screenshots from the real screens with made-up demo data, so nothing
// from a real server can end up in them. Not part of `flutter test` (it lives in test_driver/
// and is run on purpose). The brand fonts are read from build/fonts (see store-screenshots.yml).
// Run:
//
//   flutter test test_driver/store_screenshots_test.dart
//
// Output: build/store_shots/{phone,tablet7,tablet10}/NN-name.png
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:everything_panel/data/models.dart';
import 'package:everything_panel/data/panel_backend.dart';
import 'package:everything_panel/screens/root.dart';
import 'package:everything_panel/services/auth_service.dart';
import 'package:everything_panel/services/push_service.dart';
import 'package:everything_panel/state/app_state.dart';
import 'package:everything_panel/state/scope.dart';
import 'package:everything_panel/state/sync_controller.dart';
import 'package:everything_panel/theme/brand.dart';
import 'package:everything_panel/ui/glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DemoBackend implements PanelBackend {
  DemoBackend(this.variant);
  final int variant; // 0 = production, 1 = staging

  static ServiceInfo _s(String p, String n, ServiceKind k, {double cpu = 0, double mem = 0, int c = 0}) =>
      ServiceInfo(project: p, name: n, kind: k, usage: c == 0 ? null : ServiceUsage(cpuPercent: cpu, memPercent: mem, containers: c));

  @override
  Future<void> verify() async {}

  @override
  Future<List<ServiceInfo>> services() async => variant == 0
      ? [
          _s('apps', 'storefront', ServiceKind.app, cpu: 3.4, mem: 18.2, c: 2),
          _s('apps', 'checkout-api', ServiceKind.app, cpu: 1.1, mem: 22.7, c: 1),
          _s('apps', 'order-worker', ServiceKind.app, cpu: 0.6, mem: 9.4, c: 1),
          _s('apps', 'blog', ServiceKind.wordpress, cpu: 0.4, mem: 12.0, c: 1),
          _s('data', 'orders-db', ServiceKind.postgres, cpu: 1.9, mem: 31.5, c: 1),
          _s('data', 'sessions', ServiceKind.redis, cpu: 0.3, mem: 4.1, c: 1),
          _s('internal', 'admin', ServiceKind.app),
          _s('internal', 'status-page', ServiceKind.compose, cpu: 0.2, mem: 6.3, c: 3),
        ]
      : [
          _s('app', 'preview', ServiceKind.app, cpu: 0.8, mem: 11.0, c: 1),
          _s('app', 'docs', ServiceKind.app, cpu: 0.2, mem: 5.5, c: 1),
          _s('db', 'staging-db', ServiceKind.postgres, cpu: 0.7, mem: 14.8, c: 1),
        ];

  @override
  Future<SystemStats?> systemStats() async => variant == 0
      ? const SystemStats(
          cpuPercent: 18,
          cpuCores: 8,
          load: [0.74, 0.62, 0.55],
          memPercent: 47,
          memUsedMb: 7700,
          memTotalMb: 16384,
          diskPercent: 38,
          diskUsedGb: 76,
          diskTotalGb: 200,
          netInMb: 2410,
          netOutMb: 5230,
          uptime: Duration(days: 41, hours: 6),
        )
      : const SystemStats(
          cpuPercent: 6,
          cpuCores: 4,
          load: [0.11, 0.14, 0.09],
          memPercent: 29,
          memUsedMb: 2340,
          memTotalMb: 8192,
          diskPercent: 22,
          diskUsedGb: 22,
          diskTotalGb: 100,
          netInMb: 310,
          netOutMb: 480,
          uptime: Duration(days: 9, hours: 14),
        );

  @override
  Future<void> perform(ServiceInfo service, ServiceAction action) async {}

  @override
  Future<List<ActivityEntry>> activity(ServiceInfo service, {int limit = 30}) async {
    final now = DateTime.now().toUtc();
    return [
      ActivityEntry(id: 'a1', type: 'deployment', status: 'done', description: 'Deployed from main (4f2c9e1)', createdAt: now.subtract(const Duration(minutes: 12)), hasLog: true),
      ActivityEntry(id: 'a2', type: 'build', status: 'done', description: 'Built image', createdAt: now.subtract(const Duration(minutes: 14)), hasLog: true),
      ActivityEntry(id: 'a3', type: 'start', status: 'done', description: 'Started service', createdAt: now.subtract(const Duration(days: 2)), hasLog: false),
      ActivityEntry(id: 'a4', type: 'deployment', status: 'done', description: 'Deployed from main (b81d07a)', createdAt: now.subtract(const Duration(days: 3)), hasLog: true),
    ];
  }

  @override
  Future<String> activityLog(String id) async => '''
[10:41:02] Cloning repository
[10:41:04] Installing dependencies
[10:41:19] Running build
[10:41:47] Build finished in 28s
[10:41:49] Pushing image to registry
[10:41:55] Rolling update: 1/2 healthy
[10:42:03] Rolling update: 2/2 healthy
[10:42:03] Deployment complete''';

  @override
  Future<List<LogLine>> runtimeLogs(ServiceInfo service, {String? search, int limit = 200}) async =>
      throw LogsUnavailable('Runtime logs are off on this panel.');

  @override
  void close() {}
}

Future<void> _settle(WidgetTester tester, {int ms = 1500}) async {
  for (var t = 0; t < ms; t += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    // Lists build lazily; scroll until the target exists.
    try {
      await tester.dragUntilVisible(f.first, find.byType(CustomScrollView).first, const Offset(0, -160), maxIteration: 40);
    } catch (_) {}
  }
  if (f.evaluate().isEmpty) {
    // Leave a picture of what is on screen so a failed run can be diagnosed from the artifact.
    await _shot(tester, 'debug', 'missing-${DateTime.now().millisecondsSinceEpoch}');
    throw TestFailure('Nothing on screen matches $f');
  }
  await tester.ensureVisible(f.first);
  // Let any scroll finish before aiming the tap.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(f.first, warnIfMissed: false);
  await _settle(tester, ms: 1100);
}

Future<void> _tab(WidgetTester tester, String label) async {
  final nav = find.byWidgetPredicate((w) => w is GlassNavBar || w is GlassNavRail);
  await _tap(tester, find.descendant(of: nav, matching: find.text(label)));
}

/// Wraps the whole app so sheets and dialogs (separate overlay routes) are in the picture too.
final _rootKey = GlobalKey();

/// Google sign-in looks available in the pictures, as it is in an official build.
class _StoreAuth extends AuthService {
  _StoreAuth() {
    available = true;
  }
}

Future<void> _shot(WidgetTester tester, String set, String name) async {
  // Give the last animation frame a moment to settle before capturing.
  await _settle(tester, ms: 600);
  final boundary = _rootKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('build/store_shots/$set')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

Future<AppState> _launch(WidgetTester tester, Size physical, double dpr) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = physical;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  var next = 0;
  final app = AppState(pollInterval: const Duration(hours: 1), factory: (p, s) => DemoBackend(next++ % 2));
  await app.load();
  final auth = _StoreAuth();
  final push = PushService();
  final sync = SyncController(app: app, auth: auth);
  addTearDown(app.dispose);

  await tester.pumpWidget(RepaintBoundary(
    key: _rootKey,
    child: AppScope(
      app: app,
      auth: auth,
      push: push,
      sync: sync,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.dark,
        home: const RootScreen(),
      ),
    ),
  ));
  // Images decode off the test clock; load the art before the first frame is captured.
  await tester.runAsync(() async {
    final ctx = tester.element(find.byType(RootScreen));
    for (final a in ['hero', 'empty', 'splash', 'logo']) {
      await precacheImage(AssetImage('assets/images/$a.webp'), ctx);
    }
  });
  await _settle(tester, ms: 1800);
  return app;
}

Future<void> _storyboard(WidgetTester tester, String set, Size physical, double dpr) async {
  final app = await _launch(tester, physical, dpr);
  await _shot(tester, set, '01-welcome');

  await app.addServer(kind: PanelKind.easypanel, name: 'Production', url: 'https://panel.example.com', secrets: {'token': 'demo'});
  await app.addServer(kind: PanelKind.easypanel, name: 'Staging', url: 'https://staging.example.com', secrets: {'token': 'demo'});
  await app.select(app.sessions.first.profile.id);
  await _settle(tester, ms: 2500);
  await _shot(tester, set, '02-fleet');

  await _tab(tester, 'Services');
  await _shot(tester, set, '03-services');

  await _tap(tester, find.text('checkout-api'));
  await _shot(tester, set, '04-service');

  await _tap(tester, find.text('Logs and activity'));
  await _tap(tester, find.text('Activity'));
  await _tap(tester, find.text('Deployed from main (4f2c9e1)'));
  await _shot(tester, set, '05-activity');
  await tester.pageBack();
  await _settle(tester, ms: 1200);

  await _tab(tester, 'System');
  await _shot(tester, set, '06-system');
}

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  var any = false;
  for (final path in files) {
    final f = File(path);
    if (f.existsSync()) {
      loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      any = true;
    }
  }
  if (any) await loader.load();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root != null) {
      await _loadFont('MaterialIcons', ['$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
    }
    await _loadFont('DMSans', [
      'build/fonts/dmsans-400.ttf',
      'build/fonts/dmsans-500.ttf',
      'build/fonts/dmsans-600.ttf',
      'build/fonts/dmsans-700.ttf',
    ]);
    await _loadFont('SpaceMono', ['build/fonts/spacemono-400.ttf']);
    useBrandFonts = false;
    fallbackFontFamily = 'DMSans';
    fallbackMonoFontFamily = 'SpaceMono';
  });

  testWidgets('phone 1080x1920', (tester) => _storyboard(tester, 'phone', const Size(1080, 1920), 2.625));
  testWidgets('tablet 7in 1200x1920', (tester) => _storyboard(tester, 'tablet7', const Size(1200, 1920), 2));
  testWidgets('tablet 10in 2560x1600', (tester) => _storyboard(tester, 'tablet10', const Size(2560, 1600), 2));
}
