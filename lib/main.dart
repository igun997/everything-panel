import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/root.dart';
import 'services/auth_service.dart';
import 'services/push_service.dart';
import 'state/app_state.dart';
import 'state/scope.dart';
import 'state/sync_controller.dart';
import 'theme/brand.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final app = AppState();
  final auth = AuthService();
  final push = PushService();
  final sync = SyncController(app: app, auth: auth);
  app.alertSink = push.show;

  runApp(EverythingPanelApp(app: app, auth: auth, push: push, sync: sync));
}

class EverythingPanelApp extends StatefulWidget {
  const EverythingPanelApp({
    super.key,
    required this.app,
    required this.auth,
    required this.push,
    required this.sync,
  });
  final AppState app;
  final AuthService auth;
  final PushService push;
  final SyncController sync;

  @override
  State<EverythingPanelApp> createState() => _EverythingPanelAppState();
}

class _EverythingPanelAppState extends State<EverythingPanelApp> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await widget.push.init();
    await widget.auth.init(firebaseReady: widget.push.firebaseReady);
    await widget.app.load();
    // After the local servers are loaded, so a restored vault merges into them.
    widget.sync.attach();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      app: widget.app,
      auth: widget.auth,
      push: widget.push,
      sync: widget.sync,
      child: MaterialApp(
        title: 'everything-panel',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        builder: (context, child) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
              systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            ),
            child: child!,
          );
        },
        home: const RootScreen(),
      ),
    );
  }
}
