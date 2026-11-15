import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/panel_backend.dart';
import '../data/providers.dart';

typedef BackendFactory = PanelBackend Function(ServerProfile profile, Map<String, String> secrets);
typedef AlertSink = void Function(String title, String body);

PanelBackend _defaultFactory(ServerProfile p, Map<String, String> secrets) => specFor(p.kind).build(p, secrets);

/// Live state of one connected server (any provider).
class ServerSession {
  ServerSession(this.profile, this.backend);

  final ServerProfile profile;
  PanelBackend? backend;
  List<ServiceInfo> services = const [];
  SystemStats? stats;
  bool loading = false;
  bool loadedOnce = false;
  String? error;
  bool authFailed = false;
  DateTime? lastUpdated;

  int get total => services.length;
  int get running => services.where((s) => s.isRunning).length;

  /// Controllable workloads that are not running. Databases are excluded
  /// because their state is not reported reliably by every provider.
  List<ServiceInfo> get down => [
        for (final s in services)
          if (!s.isRunning && s.kind.canControl) s,
      ];
}

/// Everything is stored on this device only: profile metadata in shared
/// preferences, secrets in the platform keystore.
class AppState extends ChangeNotifier {
  AppState({
    SharedPreferences? prefs,
    FlutterSecureStorage? secure,
    BackendFactory? factory,
    this.pollInterval = const Duration(seconds: 20),
  })  : _prefs = prefs,
        _secure = secure ?? const FlutterSecureStorage(),
        _factory = factory ?? _defaultFactory;

  static const _profilesKey = 'profiles.v1';
  static const _activeKey = 'profiles.active';
  static const _onboardedKey = 'onboarded';
  static const _alertsKey = 'alerts.enabled';

  final Duration pollInterval;
  SharedPreferences? _prefs;
  final FlutterSecureStorage _secure;
  final BackendFactory _factory;

  AlertSink? alertSink;

  /// Called after a server is added or removed by the user, so encrypted sync can mirror it.
  void Function(ServerProfile profile, Map<String, String> secrets)? onServerAdded;
  void Function(ServerProfile profile)? onServerRemoved;

  bool ready = false;
  bool onboarded = false;
  bool alertsEnabled = false;
  List<ServerSession> sessions = const [];
  String? activeId;
  Timer? _poll;

  ServerSession? get active {
    for (final s in sessions) {
      if (s.profile.id == activeId) return s;
    }
    return sessions.isEmpty ? null : sessions.first;
  }

  bool get hasServers => sessions.isNotEmpty;

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    onboarded = _prefs!.getBool(_onboardedKey) ?? false;
    alertsEnabled = _prefs!.getBool(_alertsKey) ?? false;

    final raw = _prefs!.getString(_profilesKey);
    final profiles = <ServerProfile>[];
    if (raw != null) {
      for (final j in (jsonDecode(raw) as List).whereType<Map<String, dynamic>>()) {
        profiles.add(ServerProfile.fromJson(j));
      }
    }
    activeId = _prefs!.getString(_activeKey);

    final built = <ServerSession>[];
    for (final p in profiles) {
      built.add(await _openSession(p));
    }
    sessions = built;
    if (active == null) activeId = null;
    ready = true;
    notifyListeners();

    unawaited(refreshAll());
    _startPolling();
  }

  Future<ServerSession> _openSession(ServerProfile p) async {
    final secrets = await _readSecrets(p.id);
    final s = ServerSession(p, null);
    if (secrets == null) {
      s.error = 'The saved credentials for ${p.name} are missing. Remove the server and add it again.';
      s.authFailed = true;
    } else {
      s.backend = _factory(p, secrets);
    }
    return s;
  }

  static String _secretKey(String id) => 'secrets.$id';

  Future<Map<String, String>?> readSecrets(String id) async {
    final raw = await _secure.read(key: _secretKey(id));
    if (raw == null) return null;
    return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
  }

  Future<Map<String, String>?> _readSecrets(String id) => readSecrets(id);

  Future<void> _persist() async {
    await _prefs!.setString(_profilesKey, jsonEncode([for (final s in sessions) s.profile.toJson()]));
    final id = activeId;
    if (id == null) {
      await _prefs!.remove(_activeKey);
    } else {
      await _prefs!.setString(_activeKey, id);
    }
  }

  Future<void> markOnboarded() async {
    onboarded = true;
    await _prefs!.setBool(_onboardedKey, true);
    notifyListeners();
  }

  Future<void> setAlerts(bool on) async {
    alertsEnabled = on;
    await _prefs!.setBool(_alertsKey, on);
    notifyListeners();
  }

  /// Verifies the credentials against the server first; only a working server is saved.
  Future<ServerProfile> addServer({
    required PanelKind kind,
    required String name,
    required String url,
    required Map<String, String> secrets,
  }) async {
    final draft = ServerProfile(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      name: name.trim().isEmpty ? _hostOf(url) : name.trim(),
      url: url.trim(),
      kind: kind,
    );
    final backend = _factory(draft, secrets);
    try {
      await backend.verify();
    } catch (_) {
      backend.close();
      rethrow;
    }
    await _secure.write(key: _secretKey(draft.id), value: jsonEncode(secrets));
    final session = ServerSession(draft, backend);
    sessions = [...sessions, session];
    activeId = draft.id;
    await _persist();
    await markOnboarded();
    notifyListeners();
    unawaited(_refresh(session));
    _startPolling();
    onServerAdded?.call(draft, secrets);
    return draft;
  }

  /// Adds a server that came from the encrypted vault. It was verified when it was
  /// first added, so it is not verified again. Returns false if it already exists.
  Future<bool> importServer(ServerProfile profile, Map<String, String> secrets) async {
    if (sessions.any((s) => s.profile.id == profile.id)) return false;
    await _secure.write(key: _secretKey(profile.id), value: jsonEncode(secrets));
    final session = ServerSession(profile, _factory(profile, secrets));
    sessions = [...sessions, session];
    activeId ??= profile.id;
    await _persist();
    await markOnboarded();
    notifyListeners();
    unawaited(_refresh(session));
    _startPolling();
    return true;
  }

  /// [mirror] false when the removal itself came from the vault.
  Future<void> removeServer(ServerProfile p, {bool mirror = true}) async {
    await _secure.delete(key: _secretKey(p.id));
    for (final s in sessions.where((s) => s.profile.id == p.id)) {
      s.backend?.close();
    }
    sessions = [for (final s in sessions) if (s.profile.id != p.id) s];
    if (activeId == p.id) activeId = sessions.firstOrNull?.profile.id;
    await _persist();
    if (sessions.isEmpty) _poll?.cancel();
    notifyListeners();
    if (mirror) onServerRemoved?.call(p);
  }

  Future<void> select(String id) async {
    if (activeId == id) return;
    activeId = id;
    notifyListeners();
    await _persist();
  }

  void _startPolling() {
    _poll?.cancel();
    if (sessions.isEmpty) return;
    _poll = Timer.periodic(pollInterval, (_) => refreshAll(quiet: true));
  }

  Future<void> refreshAll({bool quiet = false}) =>
      Future.wait([for (final s in List.of(sessions)) _refresh(s, quiet: quiet)]);

  Future<void> refresh({bool quiet = false}) async {
    final s = active;
    if (s != null) await _refresh(s, quiet: quiet);
  }

  Future<void> _refresh(ServerSession s, {bool quiet = false}) async {
    final b = s.backend;
    if (b == null) return;
    if (!quiet) {
      s.loading = true;
      notifyListeners();
    }
    try {
      final results = await Future.wait<Object?>([
        b.services(),
        b.systemStats().catchError((_) => null),
      ]);
      if (!identical(b, s.backend) || !sessions.contains(s)) return;
      final before = {for (final x in s.services) x.key: x.isRunning};
      s.services = results[0] as List<ServiceInfo>;
      s.stats = results[1] as SystemStats?;
      s.error = null;
      s.authFailed = false;
      s.lastUpdated = DateTime.now();
      if (s.loadedOnce) _alertForDown(s, before);
      s.loadedOnce = true;
    } on PanelException catch (e) {
      s.error = e.message;
      s.authFailed = e.unauthorized;
    } finally {
      s.loading = false;
      notifyListeners();
    }
  }

  // Services the user stopped or restarted on purpose; they must not alert.
  final _userStopped = <String>{};
  String _stopKey(ServerSession s, ServiceInfo svc) => '${s.profile.id}/${svc.key}';

  /// Only a service seen running that is no longer running raises an alert,
  /// so a stopped service the user already knows about stays quiet.
  void _alertForDown(ServerSession s, Map<String, bool> before) {
    if (!alertsEnabled || alertSink == null) return;
    for (final svc in s.services) {
      final k = _stopKey(s, svc);
      if (svc.isRunning) {
        _userStopped.remove(k);
      } else if (svc.kind.canControl && before[svc.key] == true && !_userStopped.contains(k)) {
        alertSink!('${svc.name} is down', '${svc.project} on ${s.profile.name} stopped running.');
      }
    }
  }

  /// Runs an action and refreshes. Throws [PanelException] for the UI to show.
  Future<void> perform(ServerSession s, ServiceInfo service, ServiceAction action) async {
    final b = s.backend;
    if (b == null) throw PanelException('This server is not connected.');
    await b.perform(service, action);
    if (action == ServiceAction.stop || action == ServiceAction.restart) {
      _userStopped.add(_stopKey(s, service));
    }
    // Containers take a moment to come or go; refresh now and once more shortly.
    await _refresh(s, quiet: true);
    unawaited(Future<void>.delayed(const Duration(seconds: 3), () => _refresh(s, quiet: true)));
  }

  static String _hostOf(String url) {
    final u = Uri.tryParse(url.contains('://') ? url : 'https://$url');
    return (u?.host.isNotEmpty ?? false) ? u!.host : url;
  }

  @override
  void dispose() {
    _poll?.cancel();
    for (final s in sessions) {
      s.backend?.close();
    }
    super.dispose();
  }
}
