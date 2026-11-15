import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import '../data/models.dart';

/// A server profile together with its secrets: the plaintext of one vault entry.
class ServerRecord {
  const ServerRecord(this.profile, this.secrets, {required this.updatedAt});
  final ServerProfile profile;
  final Map<String, String> secrets;

  /// Milliseconds since epoch, as last written.
  final int updatedAt;
}

class VaultMeta {
  const VaultMeta({required this.salt, required this.iterations, required this.check, required this.checkNonce});
  final Uint8List salt;
  final int iterations;
  final Uint8List check;
  final Uint8List checkNonce;
}

class VaultSnapshot {
  const VaultSnapshot(this.records, this.deleted);
  final List<ServerRecord> records;

  /// Server id -> when it was deleted on another device.
  final Map<String, int> deleted;
}

class VaultException implements Exception {
  VaultException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// End-to-end encrypted sync of server profiles through the signed-in user's own
/// Firestore documents (`users/{uid}/...`).
///
/// * The key is derived on the device from a passphrase (PBKDF2-HMAC-SHA256) and
///   never leaves it. Firestore only ever stores salt, iteration count and
///   AES-256-GCM ciphertext.
/// * Each entry is bound to its owner and id as AEAD associated data, so a
///   blob cannot be moved to another entry or account undetected.
/// * Talks to Firestore over REST with the user's Firebase ID token, so it adds
///   no native dependency and stays inside the free Spark quota.
class VaultService {
  VaultService({
    required this.uid,
    required this.idToken,
    this.projectId = 'everything-panel',
    this.iterations = 310000,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String uid;
  final Future<String> Function() idToken;
  final String projectId;

  /// Used when creating a vault; an existing vault keeps the count in its meta.
  final int iterations;
  final http.Client _client;

  static const _checkText = 'everything-panel/vault/v1';
  static final _aes = AesGcm.with256bits();

  String get _base => 'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/users/$uid';

  // ---------------------------------------------------------------- crypto

  Future<SecretKey> _derive(String passphrase, List<int> salt, int iter) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iter, bits: 256)
          .deriveKeyFromPassword(password: passphrase, nonce: salt);

  List<int> _aad(String id) => utf8.encode('$uid/$id');

  Future<(Uint8List nonce, Uint8List sealed)> _seal(SecretKey key, List<int> plain, List<int> aad) async {
    final box = await _aes.encrypt(plain, secretKey: key, aad: aad);
    return (Uint8List.fromList(box.nonce), Uint8List.fromList([...box.cipherText, ...box.mac.bytes]));
  }

  Future<List<int>> _open(SecretKey key, Uint8List nonce, Uint8List sealed, List<int> aad) {
    if (sealed.length < 16) throw VaultException('Corrupt vault entry.');
    final box = SecretBox(
      sealed.sublist(0, sealed.length - 16),
      nonce: nonce,
      mac: Mac(sealed.sublist(sealed.length - 16)),
    );
    return _aes.decrypt(box, secretKey: key, aad: aad);
  }

  // ------------------------------------------------------------- key setup

  /// Creates the vault for this account and returns the raw key to cache on this device.
  Future<Uint8List> createVault(String passphrase) async {
    final salt = Uint8List.fromList(SecretKeyData.random(length: 16).bytes);
    final key = await _derive(passphrase, salt, iterations);
    final (nonce, sealed) = await _seal(key, utf8.encode(_checkText), _aad('meta'));
    await _patch('meta/vault', {
      'v': _int(1),
      'salt': _str(base64.encode(salt)),
      'iter': _int(iterations),
      'check': _str(base64.encode(sealed)),
      'checkNonce': _str(base64.encode(nonce)),
      'updatedAt': _int(DateTime.now().millisecondsSinceEpoch),
    }, mustNotExist: true);
    return Uint8List.fromList(await key.extractBytes());
  }

  /// Returns the raw key if [passphrase] is right, otherwise null.
  Future<Uint8List?> unlock(String passphrase, VaultMeta meta) async {
    final key = await _derive(passphrase, meta.salt, meta.iterations);
    try {
      final plain = await _open(key, meta.checkNonce, meta.check, _aad('meta'));
      if (utf8.decode(plain) != _checkText) return null;
    } on SecretBoxAuthenticationError {
      return null;
    }
    return Uint8List.fromList(await key.extractBytes());
  }

  Future<VaultMeta?> fetchMeta() async {
    final doc = await _get('meta/vault');
    if (doc == null) return null;
    final f = doc['fields'] as Map<String, dynamic>;
    return VaultMeta(
      salt: base64.decode(_readStr(f, 'salt')),
      iterations: int.parse(_readInt(f, 'iter')),
      check: base64.decode(_readStr(f, 'check')),
      checkNonce: base64.decode(_readStr(f, 'checkNonce')),
    );
  }

  // --------------------------------------------------------------- entries

  Future<void> putServer(Uint8List rawKey, ServerProfile profile, Map<String, String> secrets) async {
    final key = SecretKey(rawKey);
    final plain = utf8.encode(jsonEncode({'profile': profile.toJson(), 'secrets': secrets}));
    final (nonce, sealed) = await _seal(key, plain, _aad('server/${profile.id}'));
    await _patch('servers/${profile.id}', {
      'v': _int(1),
      'nonce': _str(base64.encode(nonce)),
      'ct': _str(base64.encode(sealed)),
      'updatedAt': _int(DateTime.now().millisecondsSinceEpoch),
      'deleted': {'booleanValue': false},
    });
  }

  /// Leaves a tombstone so other devices learn about the deletion.
  Future<void> deleteServer(String id) => _patch('servers/$id', {
        'v': _int(1),
        'nonce': _str(''),
        'ct': _str(''),
        'updatedAt': _int(DateTime.now().millisecondsSinceEpoch),
        'deleted': {'booleanValue': true},
      });

  Future<VaultSnapshot> pull(Uint8List rawKey) async {
    final key = SecretKey(rawKey);
    final records = <ServerRecord>[];
    final deleted = <String, int>{};
    String? page;
    do {
      final res = await _send('GET', '$_base/servers?pageSize=300${page == null ? '' : '&pageToken=$page'}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      for (final d in (body['documents'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        final id = (d['name'] as String).split('/').last;
        final f = d['fields'] as Map<String, dynamic>;
        final at = int.parse(_readInt(f, 'updatedAt'));
        if ((f['deleted'] as Map?)?['booleanValue'] == true) {
          deleted[id] = at;
          continue;
        }
        try {
          final plain = await _open(
            key,
            base64.decode(_readStr(f, 'nonce')),
            base64.decode(_readStr(f, 'ct')),
            _aad('server/$id'),
          );
          final j = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
          records.add(ServerRecord(
            ServerProfile.fromJson(j['profile'] as Map<String, dynamic>),
            (j['secrets'] as Map).map((k, v) => MapEntry('$k', '$v')),
            updatedAt: at,
          ));
        } on SecretBoxAuthenticationError {
          // An entry we cannot open (tampered or from another key) is skipped, never trusted.
        }
      }
      page = body['nextPageToken'] as String?;
    } while (page != null);
    return VaultSnapshot(records, deleted);
  }

  /// Deletes the whole cloud copy. Local servers are untouched.
  Future<void> reset() async {
    final res = await _send('GET', '$_base/servers?pageSize=300');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    for (final d in (body['documents'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      await _send('DELETE', 'https://firestore.googleapis.com/v1/${d['name']}');
    }
    await _send('DELETE', '$_base/meta/vault');
  }

  // ------------------------------------------------------------------ REST

  static Map<String, dynamic> _str(String v) => {'stringValue': v};
  static Map<String, dynamic> _int(int v) => {'integerValue': '$v'};

  static String _readStr(Map<String, dynamic> f, String k) {
    final v = (f[k] as Map?)?['stringValue'];
    if (v is! String) throw VaultException('Vault entry is missing "$k".');
    return v;
  }

  static String _readInt(Map<String, dynamic> f, String k) {
    final v = (f[k] as Map?)?['integerValue'];
    if (v == null) throw VaultException('Vault entry is missing "$k".');
    return '$v';
  }

  Future<Map<String, dynamic>?> _get(String path) async {
    final res = await _send('GET', '$_base/$path', allow404: true);
    if (res.statusCode == 404) return null;
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> _patch(String path, Map<String, dynamic> fields, {bool mustNotExist = false}) async {
    final q = mustNotExist ? '?currentDocument.exists=false' : '';
    await _send('PATCH', '$_base/$path$q', body: jsonEncode({'fields': fields}));
  }

  Future<http.Response> _send(String method, String url, {String? body, bool allow404 = false}) async {
    final token = await idToken();
    final req = http.Request(method, Uri.parse(url))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json';
    if (body != null) req.body = body;
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(const Duration(seconds: 20)));
    } on Exception catch (e) {
      throw VaultException('Cannot reach the sync service: $e');
    }
    if (res.statusCode == 404 && allow404) return res;
    if (res.statusCode == 409 || (res.statusCode == 400 && res.body.contains('ALREADY_EXISTS'))) {
      throw VaultException('Encrypted sync is already set up for this account. Unlock it instead.');
    }
    if (res.statusCode == 403 || res.statusCode == 401) {
      throw VaultException('The sync service refused this account (${res.statusCode}).');
    }
    if (res.statusCode >= 400) throw VaultException('Sync failed (${res.statusCode}).');
    return res;
  }

  void close() => _client.close();
}
