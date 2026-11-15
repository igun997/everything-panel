import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/models.dart';
import '../services/auth_service.dart';
import '../services/vault_service.dart';
import 'app_state.dart';

enum SyncState {
  /// Not signed in with Google, or Firebase is not configured.
  off,
  checking,
  needsSetup,
  locked,
  unlocked,
  error,
}

typedef VaultFactory = VaultService Function(String uid, Future<String> Function() idToken);

/// Mirrors the user's servers to their own encrypted Firestore vault.
/// Entirely optional: with no Google account the app never touches the network for this.
class SyncController extends ChangeNotifier {
  SyncController({
    required this.app,
    required this.auth,
    FlutterSecureStorage? secure,
    VaultFactory? vaultFactory,
  })  : _secure = secure ?? const FlutterSecureStorage(),
        _vaultFactory = vaultFactory ?? _defaultVault;

  static VaultService _defaultVault(String uid, Future<String> Function() token) =>
      VaultService(uid: uid, idToken: token);

  static const minPassphraseLength = 10;

  final AppState app;
  final AuthService auth;
  final FlutterSecureStorage _secure;
  final VaultFactory _vaultFactory;

  SyncState state = SyncState.off;
  String? error;
  bool busy = false;
  DateTime? lastSync;

  String? _uid;
  VaultService? _vault;
  VaultMeta? _meta;
  Uint8List? _key;

  String _keySlot(String uid) => 'vault.key.$uid';

  void attach() {
    app.onServerAdded = _mirrorAdd;
    app.onServerRemoved = _mirrorRemove;
    auth.addListener(_onAuth);
    _onAuth();
  }

  void _onAuth() {
    final uid = auth.user?.uid;
    if (uid == _uid) return;
    _uid = uid;
    _vault?.close();
    _vault = null;
    _meta = null;
    _key = null;
    error = null;
    if (uid == null) {
      state = SyncState.off;
      notifyListeners();
      return;
    }
    _vault = _vaultFactory(uid, () async {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) throw VaultException('You are signed out.');
      return token;
    });
    unawaited(refreshStatus());
  }

  /// Looks up whether this account has a vault and whether this device holds its key.
  Future<void> refreshStatus() async {
    final v = _vault;
    final uid = _uid;
    if (v == null || uid == null) return;
    state = SyncState.checking;
    error = null;
    notifyListeners();
    try {
      _meta = await v.fetchMeta();
      final cached = await _secure.read(key: _keySlot(uid));
      if (_meta == null) {
        await _secure.delete(key: _keySlot(uid));
        state = SyncState.needsSetup;
      } else if (cached != null) {
        _key = base64.decode(cached);
        state = SyncState.unlocked;
        notifyListeners();
        await sync();
        return;
      } else {
        state = SyncState.locked;
      }
    } on VaultException catch (e) {
      error = e.message;
      state = SyncState.error;
    }
    notifyListeners();
  }

  /// Creates the vault with a new passphrase and uploads the servers on this device.
  /// Returns an error message, or null on success.
  Future<String?> setup(String passphrase) async {
    final v = _vault;
    final uid = _uid;
    if (v == null || uid == null) return 'Sign in with Google first.';
    if (passphrase.length < minPassphraseLength) {
      return 'Use at least $minPassphraseLength characters.';
    }
    return _guard(() async {
      final key = await v.createVault(passphrase);
      await _secure.write(key: _keySlot(uid), value: base64.encode(key));
      _key = key;
      _meta = await v.fetchMeta();
      state = SyncState.unlocked;
      await _syncInner();
    });
  }

  /// Returns an error message (including "wrong passphrase"), or null on success.
  Future<String?> unlock(String passphrase) async {
    final v = _vault;
    final uid = _uid;
    final meta = _meta;
    if (v == null || uid == null || meta == null) return 'Nothing to unlock yet.';
    return _guard(() async {
      final key = await v.unlock(passphrase, meta);
      if (key == null) throw VaultException('That passphrase does not match.');
      await _secure.write(key: _keySlot(uid), value: base64.encode(key));
      _key = key;
      state = SyncState.unlocked;
      await _syncInner();
    });
  }

  Future<String?> sync() => _guard(_syncInner);

  /// Forgets the key on this device; the cloud copy stays and can be unlocked again.
  Future<void> lock() async {
    final uid = _uid;
    if (uid != null) await _secure.delete(key: _keySlot(uid));
    _key = null;
    if (state == SyncState.unlocked) state = SyncState.locked;
    notifyListeners();
  }

  /// Deletes the cloud copy. Servers on this device are untouched.
  Future<String?> resetCloud() async {
    final v = _vault;
    final uid = _uid;
    if (v == null || uid == null) return null;
    return _guard(() async {
      await v.reset();
      await _secure.delete(key: _keySlot(uid));
      _key = null;
      _meta = null;
      state = SyncState.needsSetup;
    });
  }

  Future<String?> _guard(Future<void> Function() body) async {
    if (busy) return 'Sync is already running.';
    busy = true;
    error = null;
    notifyListeners();
    try {
      await body();
      return null;
    } on VaultException catch (e) {
      error = e.message;
      return e.message;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  static int _createdAtMs(String id) => (int.tryParse(id, radix: 36) ?? 0) ~/ 1000;

  Future<void> _syncInner() async {
    final v = _vault, key = _key;
    if (v == null || key == null) return;
    final snap = await v.pull(key);

    // Deletions made on another device, unless the server was created after them.
    for (final s in List.of(app.sessions)) {
      final at = snap.deleted[s.profile.id];
      if (at != null && _createdAtMs(s.profile.id) < at) {
        await app.removeServer(s.profile, mirror: false);
      }
    }

    // Servers added on another device.
    final remote = <String>{};
    for (final r in snap.records) {
      remote.add(r.profile.id);
      await app.importServer(r.profile, r.secrets);
    }

    // Servers that exist only here.
    for (final s in app.sessions) {
      if (remote.contains(s.profile.id) || snap.deleted.containsKey(s.profile.id)) continue;
      final secrets = await app.readSecrets(s.profile.id);
      if (secrets != null) await v.putServer(key, s.profile, secrets);
    }
    lastSync = DateTime.now();
  }

  void _mirrorAdd(ServerProfile p, Map<String, String> secrets) {
    final v = _vault, key = _key;
    if (state != SyncState.unlocked || v == null || key == null) return;
    unawaited(v.putServer(key, p, secrets).then((_) {
      lastSync = DateTime.now();
      notifyListeners();
    }, onError: (Object e) {
      error = '$e';
      notifyListeners();
    }));
  }

  void _mirrorRemove(ServerProfile p) {
    final v = _vault;
    if (state != SyncState.unlocked || v == null) return;
    unawaited(v.deleteServer(p.id).then((_) {
      lastSync = DateTime.now();
      notifyListeners();
    }, onError: (Object e) {
      error = '$e';
      notifyListeners();
    }));
  }

  @override
  void dispose() {
    auth.removeListener(_onAuth);
    _vault?.close();
    super.dispose();
  }
}
