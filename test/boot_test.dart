import 'package:everything_panel/boot.dart';
import 'package:everything_panel/services/auth_service.dart';
import 'package:everything_panel/services/push_service.dart';
import 'package:everything_panel/state/app_state.dart';
import 'package:everything_panel/state/sync_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A notification plugin that cannot start, as happened in a release build whose shrunk
/// resources lacked the notification icon.
class _BrokenPush extends PushService {
  @override
  Future<void> init() async => throw PlatformException(code: 'invalid_icon', message: 'resource not found');
}

class _BrokenAuth extends AuthService {
  @override
  Future<void> init({required bool firebaseReady}) async => throw StateError('sign-in failed to start');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> boot(PushService push, AuthService auth) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final app = AppState(pollInterval: const Duration(hours: 1));
    final sync = SyncController(app: app, auth: auth);
    addTearDown(() {
      sync.dispose();
      app.dispose();
    });
    await bootApp(push: push, auth: auth, app: app, sync: sync);
    return app;
  }

  test('the app still loads when notifications cannot start', () async {
    final app = await boot(_BrokenPush(), AuthService());
    expect(app.ready, isTrue, reason: 'a failed optional service must not leave the app on the splash screen');
  });

  test('the app still loads when Google sign-in cannot start', () async {
    final app = await boot(PushService(), _BrokenAuth());
    expect(app.ready, isTrue);
  });
}
