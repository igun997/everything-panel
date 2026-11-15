import 'package:flutter/foundation.dart';

import 'services/auth_service.dart';
import 'services/push_service.dart';
import 'state/app_state.dart';
import 'state/sync_controller.dart';

/// Starts the app's services. Notifications and Google sign-in are optional extras: if
/// either fails to start, the app still loads its servers instead of waiting forever on
/// the splash screen.
Future<void> bootApp({
  required PushService push,
  required AuthService auth,
  required AppState app,
  required SyncController sync,
}) async {
  await _optional('notifications', push.init);
  await _optional('google sign-in', () => auth.init(firebaseReady: push.firebaseReady));
  await app.load();
  // After the local servers are loaded, so a restored vault merges into them.
  sync.attach();
}

Future<void> _optional(String what, Future<void> Function() start) async {
  try {
    await start();
  } catch (e, st) {
    debugPrint('$what failed to start, continuing without it: $e\n$st');
  }
}
