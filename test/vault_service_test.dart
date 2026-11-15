import 'dart:convert';
import 'dart:typed_data';

import 'package:everything_panel/data/models.dart';
import 'package:everything_panel/services/vault_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Minimal in-memory Firestore REST double: documents by full path, with the
/// create-only precondition the vault relies on.
class FakeFirestore {
  final docs = <String, Map<String, dynamic>>{};
  final seenAuth = <String?>[];

  http.Response handle(http.Request req) {
    seenAuth.add(req.headers['Authorization']);
    const root = '/v1/projects/everything-panel/databases/(default)/documents/';
    final path = req.url.path.substring(root.length);
    final name = 'projects/everything-panel/databases/(default)/documents/$path';

    switch (req.method) {
      case 'GET':
        final isCollection = !docs.containsKey(path) && !path.endsWith('vault');
        if (isCollection) {
          final found = [
            for (final e in docs.entries)
              if (e.key.startsWith('$path/'))
                {'name': 'projects/everything-panel/databases/(default)/documents/${e.key}', 'fields': e.value},
          ];
          return http.Response(jsonEncode({if (found.isNotEmpty) 'documents': found}), 200);
        }
        if (!docs.containsKey(path)) return http.Response('{"error":{"status":"NOT_FOUND"}}', 404);
        return http.Response(jsonEncode({'name': name, 'fields': docs[path]}), 200);
      case 'PATCH':
        if (req.url.queryParameters['currentDocument.exists'] == 'false' && docs.containsKey(path)) {
          return http.Response('{"error":{"status":"ALREADY_EXISTS"}}', 409);
        }
        docs[path] = (jsonDecode(req.body) as Map)['fields'] as Map<String, dynamic>;
        return http.Response(jsonEncode({'name': name}), 200);
      case 'DELETE':
        docs.remove(path);
        return http.Response('{}', 200);
    }
    return http.Response('', 405);
  }
}

VaultService vaultFor(FakeFirestore fs, {String uid = 'alice'}) => VaultService(
      uid: uid,
      idToken: () async => 'id-token',
      iterations: 1000, // production uses 310k; keep the pure-Dart test fast
      client: MockClient((r) async => fs.handle(r)),
    );

const profile = ServerProfile(id: 'abc123', name: 'Prod', url: 'https://panel.example.com');
const secrets = {'token': 'super-secret-token-value'};

void main() {
  test('the right passphrase unlocks and a wrong one is rejected', () async {
    final fs = FakeFirestore();
    final v = vaultFor(fs);
    final key = await v.createVault('correct horse battery');
    final meta = (await v.fetchMeta())!;

    expect(await v.unlock('correct horse battery', meta), key);
    expect(await v.unlock('wrong passphrase!!', meta), isNull);
  });

  test('servers round-trip and the cloud never holds plaintext', () async {
    final fs = FakeFirestore();
    final v = vaultFor(fs);
    final key = await v.createVault('correct horse battery');

    await v.putServer(key, profile, secrets);

    final stored = jsonEncode(fs.docs);
    expect(stored, isNot(contains('super-secret-token-value')));
    expect(stored, isNot(contains('panel.example.com')));
    expect(stored, isNot(contains('Prod')));
    expect(fs.seenAuth.every((a) => a == 'Bearer id-token'), isTrue);

    final snap = await v.pull(key);
    expect(snap.records, hasLength(1));
    expect(snap.records.single.profile.id, 'abc123');
    expect(snap.records.single.profile.url, 'https://panel.example.com');
    expect(snap.records.single.secrets, secrets);
  });

  test('an entry copied under another id is not trusted', () async {
    final fs = FakeFirestore();
    final v = vaultFor(fs);
    final key = await v.createVault('correct horse battery');
    await v.putServer(key, profile, secrets);

    final path = fs.docs.keys.firstWhere((k) => k.startsWith('users/alice/servers/'));
    fs.docs['users/alice/servers/other'] = fs.docs[path]!;

    final snap = await v.pull(key);
    expect(snap.records.map((r) => r.profile.id), ['abc123']);
  });

  test('a different key cannot read the vault entries', () async {
    final fs = FakeFirestore();
    final v = vaultFor(fs);
    final key = await v.createVault('correct horse battery');
    await v.putServer(key, profile, secrets);

    final wrong = List<int>.from(key)..[0] ^= 0xff;
    final snap = await v.pull(Uint8List.fromList(wrong));
    expect(snap.records, isEmpty);
  });

  test('deleting leaves a tombstone other devices can see', () async {
    final fs = FakeFirestore();
    final v = vaultFor(fs);
    final key = await v.createVault('correct horse battery');
    await v.putServer(key, profile, secrets);
    await v.deleteServer('abc123');

    final snap = await v.pull(key);
    expect(snap.records, isEmpty);
    expect(snap.deleted.keys, ['abc123']);
  });

  test('creating a second vault is refused instead of overwriting', () async {
    final fs = FakeFirestore();
    final v = vaultFor(fs);
    await v.createVault('correct horse battery');
    await expectLater(v.createVault('another passphrase'), throwsA(isA<VaultException>()));
    // The original still opens.
    expect(await v.unlock('correct horse battery', (await v.fetchMeta())!), isNotNull);
  });

  test('reset removes every cloud document', () async {
    final fs = FakeFirestore();
    final v = vaultFor(fs);
    final key = await v.createVault('correct horse battery');
    await v.putServer(key, profile, secrets);
    await v.reset();
    expect(fs.docs, isEmpty);
    expect(await v.fetchMeta(), isNull);
  });
}
