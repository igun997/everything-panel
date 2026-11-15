import 'package:flutter/widgets.dart';

import '../services/auth_service.dart';
import '../services/push_service.dart';
import 'app_state.dart';
import 'sync_controller.dart';

/// Hands the long-lived objects to the tree. They are listenable, so screens
/// wrap themselves in a [ListenableBuilder] on the ones they read.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.app,
    required this.auth,
    required this.push,
    required this.sync,
    required super.child,
  });

  final AppState app;
  final AuthService auth;
  final PushService push;
  final SyncController sync;

  static AppScope of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(s != null, 'AppScope missing above this widget');
    return s!;
  }

  @override
  bool updateShouldNotify(AppScope old) =>
      app != old.app || auth != old.auth || push != old.push || sync != old.sync;
}

extension AppScopeContext on BuildContext {
  AppState get app => AppScope.of(this).app;
  AuthService get auth => AppScope.of(this).auth;
  PushService get push => AppScope.of(this).push;
  SyncController get sync => AppScope.of(this).sync;
}
