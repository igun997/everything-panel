import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show FontLoader;

import 'package:everything_panel/data/models.dart';
import 'package:everything_panel/data/openapi.dart';
import 'package:everything_panel/data/panel_backend.dart';
import 'package:everything_panel/screens/root.dart';
import 'package:everything_panel/services/auth_service.dart';
import 'package:everything_panel/services/push_service.dart';
import 'package:everything_panel/state/app_state.dart';
import 'package:everything_panel/state/scope.dart';
import 'package:everything_panel/state/sync_controller.dart';
import 'package:everything_panel/theme/brand.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A panel that answers from memory. Every call is recorded so tests can check what the
/// screens actually asked for.
class FakeBackend implements PanelBackend, ApiExplorerBackend {
  FakeBackend(this.token, this.catalog);
  final String token;

  @override
  final ApiCatalog catalog;

  final calls = <String>[];
  final invocations = <(String, Map<String, Object?>)>[];

  static const web = ServiceInfo(
    project: 'shop',
    name: 'web',
    kind: ServiceKind.app,
    usage: ServiceUsage(cpuPercent: 1.5, memPercent: 20, containers: 1),
  );
  static const api = ServiceInfo(project: 'shop', name: 'api', kind: ServiceKind.app);
  static const db = ServiceInfo(project: 'data', name: 'pg', kind: ServiceKind.postgres);

  @override
  Future<void> verify() async {
    if (token == 'bad') throw PanelException('Token rejected: Invalid token', unauthorized: true);
  }

  @override
  Future<List<ServiceInfo>> services() async => const [web, api, db];

  @override
  Future<SystemStats?> systemStats() async => const SystemStats(
        cpuPercent: 12,
        cpuCores: 4,
        load: [0.1, 0.2, 0.3],
        memPercent: 25,
        memUsedMb: 2048,
        memTotalMb: 8192,
        diskPercent: 40,
        diskUsedGb: 40,
        diskTotalGb: 100,
        netInMb: 5,
        netOutMb: 7,
        uptime: Duration(hours: 30),
      );

  @override
  Future<void> perform(ServiceInfo service, ServiceAction action) async => calls.add('${action.verb} ${service.key}');

  @override
  Future<List<ActivityEntry>> activity(ServiceInfo service, {int limit = 30}) async => [
        ActivityEntry(
          id: 'a1',
          type: 'deployment',
          status: 'done',
          description: 'Deployed web',
          createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
          hasLog: true,
        ),
      ];

  @override
  Future<String> activityLog(String id) async => 'build step one\nbuild step two';

  @override
  Future<List<LogLine>> runtimeLogs(ServiceInfo service, {String? search, int limit = 200}) async =>
      throw LogsUnavailable('Runtime logs are off on this panel.');

  @override
  Future<Object?> invoke(ApiOperation op, Map<String, Object?> input) async {
    invocations.add((op.id, input));
    return {'ok': true, 'op': op.id};
  }

  @override
  void close() {}
}

class Harness {
  Harness(this.app, this.auth, this.push, this.sync, this.backends);
  final AppState app;
  final AuthService auth;
  final PushService push;
  final SyncController sync;
  final List<FakeBackend> backends;
}

ApiCatalog loadCatalog() => ApiCatalog.parse(File('assets/api/easypanel.openapi.json').readAsStringSync());

/// Pumps the whole app at [size] (logical pixels) with an empty device and a fake panel.
Future<Harness> pumpApp(WidgetTester tester, {Size size = const Size(412, 892)}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  useBrandFonts = false;
  // Fonts are loaded once in setUpAll (see loadTestFonts); loading inside a test's fake
  // async zone never completes.

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final catalog = loadCatalog();
  final backends = <FakeBackend>[];
  final app = AppState(
    pollInterval: const Duration(hours: 1),
    factory: (profile, secrets) {
      final b = FakeBackend(secrets['token'] ?? '', catalog);
      backends.add(b);
      return b;
    },
  );
  await app.load();
  final auth = AuthService();
  final push = PushService();
  final sync = SyncController(app: app, auth: auth);
  addTearDown(app.dispose);

  await tester.pumpWidget(
    AppScope(
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
  );
  await settle(tester);
  return Harness(app, auth, push, sync, backends);
}

/// The app never goes idle (ambient motion), so advance time instead of pumpAndSettle.
Future<void> settle(WidgetTester tester, {int ms = 1500}) async {
  for (var t = 0; t < ms; t += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapText(WidgetTester tester, String text, {int index = 0}) async {
  final f = find.text(text);
  expect(f, findsAtLeastNWidgets(index + 1), reason: 'no "$text" on screen');
  await tester.ensureVisible(f.at(index));
  await tester.tap(f.at(index), warnIfMissed: false);
  await settle(tester);
}

/// Loads Roboto from the Flutter SDK so layout is measured with real glyph metrics.
/// (The default test font is a wide, blocky box that makes everything overflow.)
Future<void> loadTestFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  final loader = FontLoader('Roboto');
  var any = false;
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    final file = File('$dir/$f');
    if (file.existsSync()) {
      loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      any = true;
    }
  }
  if (any) {
    await loader.load();
    fallbackFontFamily = 'Roboto';
  }
}
