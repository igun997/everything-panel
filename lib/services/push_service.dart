import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifications for everything-panel.
///
/// * Local alerts (a service went down while the app was watching) always work.
/// * Remote push (FCM) works once the Firebase project is configured; until
///   then [firebaseReady] is false and the UI says so instead of failing.
class PushService extends ChangeNotifier {
  PushService();

  static const _channelId = 'service_alerts';
  static const _channelName = 'Service alerts';

  final _local = FlutterLocalNotificationsPlugin();
  bool _localReady = false;
  int _nextId = 1;

  /// True when `Firebase.initializeApp()` succeeded (google-services.json present).
  bool firebaseReady = false;
  String? registrationId;
  bool permissionGranted = false;
  StreamSubscription<RemoteMessage>? _onMessage;
  StreamSubscription<String>? _onToken;

  Future<void> init() async {
    try {
      await Firebase.initializeApp();
      firebaseReady = true;
    } catch (e) {
      firebaseReady = false;
      debugPrint('Firebase not configured, remote push disabled: $e');
    }

    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_panel'),
      ),
    );
    _localReady = true;

    if (firebaseReady) {
      _onMessage = FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null) show(n.title ?? 'everything-panel', n.body ?? '');
      });
      _onToken = FirebaseMessaging.instance.onRegistered.listen((t) {
        registrationId = t;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  /// Asks for permission (Android 13+) and, when Firebase is ready, fetches the token.
  Future<bool> enable() async {
    var granted = false;
    if (firebaseReady) {
      final s = await FirebaseMessaging.instance.requestPermission();
      granted = s.authorizationStatus == AuthorizationStatus.authorized ||
          s.authorizationStatus == AuthorizationStatus.provisional;
      if (granted) await FirebaseMessaging.instance.register();
    } else {
      final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      granted = (await android?.requestNotificationsPermission()) ?? false;
    }
    permissionGranted = granted;
    notifyListeners();
    return granted;
  }

  Future<void> subscribe(String topic) async {
    if (firebaseReady && permissionGranted) await FirebaseMessaging.instance.subscribeToTopic(topic);
  }

  Future<void> unsubscribe(String topic) async {
    if (firebaseReady) await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
  }

  Future<void> show(String title, String body) async {
    if (!_localReady) return;
    await _local.show(
      id: _nextId++,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Tells you when a service stops running.',
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_panel',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _onMessage?.cancel();
    _onToken?.cancel();
    super.dispose();
  }
}
