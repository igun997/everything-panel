import 'dart:convert';

import 'package:everything_panel/data/easypanel_backend.dart';
import 'package:everything_panel/data/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  group('EasypanelBackend', () {
    test('lists services with usage and sends the bearer token', () async {
      final seen = <http.Request>[];
      final client = MockClient((req) async {
        seen.add(req);
        return switch (req.url.path) {
          '/api/listProjectsAndServices' => json({
              'projects': [
                {'name': 'shop'},
              ],
              'services': [
                {'projectName': 'shop', 'name': 'web', 'type': 'app'},
                {'projectName': 'shop', 'name': 'db', 'type': 'postgres'},
                {'projectName': 'shop', 'name': 'blog', 'type': 'wordpress'},
              ],
            }),
          '/api/getMonitorTableData' => json([
              {
                'projectName': 'shop',
                'serviceName': 'web',
                'stats': {
                  'cpu': {'percent': 1.5},
                  'memory': {'percent': 20},
                },
              },
              {
                'projectName': 'shop',
                'serviceName': 'web',
                'stats': {
                  'cpu': {'percent': 0.5},
                  'memory': {'percent': 10},
                },
              },
            ]),
          _ => json({'message': 'not found'}, 404),
        };
      });

      final b = EasypanelBackend(url: 'panel.example.com/', token: 'tok', client: client);
      final services = await b.services();

      expect(seen.first.url.toString(), 'https://panel.example.com/api/listProjectsAndServices');
      expect(seen.first.headers['Authorization'], 'Bearer tok');

      final web = services.firstWhere((s) => s.name == 'web');
      expect(web.kind, ServiceKind.app);
      expect(web.isRunning, isTrue);
      expect(web.usage!.containers, 2);
      expect(web.usage!.cpuPercent, closeTo(2.0, 1e-9));
      expect(web.usage!.memPercent, closeTo(30, 1e-9));

      expect(services.firstWhere((s) => s.name == 'blog').isRunning, isFalse);
      expect(services.firstWhere((s) => s.name == 'db').kind, ServiceKind.postgres);
    });

    test('a failing monitor does not hide the service list', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/listProjectsAndServices') {
          return json({
            'services': [
              {'projectName': 'p', 'name': 'a', 'type': 'app'},
            ],
          });
        }
        return json({'message': 'boom'}, 500);
      });
      final services = await EasypanelBackend(url: 'https://x.test', token: 't', client: client).services();
      expect(services, hasLength(1));
      expect(services.single.isRunning, isFalse);
    });

    test('a rejected token is reported as unauthorized', () async {
      final client = MockClient((_) async => json({'message': 'Invalid token'}, 401));
      final b = EasypanelBackend(url: 'https://x.test', token: 'bad', client: client);
      await expectLater(
        b.verify(),
        throwsA(isA<PanelException>().having((e) => e.unauthorized, 'unauthorized', isTrue)),
      );
    });

    test('actions map to the right operation and body', () async {
      http.Request? sent;
      final client = MockClient((req) async {
        sent = req;
        return json({});
      });
      final b = EasypanelBackend(url: 'https://x.test', token: 't', client: client);

      await b.perform(
        const ServiceInfo(project: 'shop', name: 'web', kind: ServiceKind.app),
        ServiceAction.restart,
      );
      expect(sent!.method, 'POST');
      expect(sent!.url.path, '/api/restartAppService');
      expect(jsonDecode(sent!.body), {'projectName': 'shop', 'serviceName': 'web'});

      await b.perform(
        const ServiceInfo(project: 'shop', name: 'blog', kind: ServiceKind.wordpress),
        ServiceAction.stop,
      );
      expect(sent!.url.path, '/api/stopWordPressService');

      await b.perform(
        const ServiceInfo(project: 'shop', name: 'stack', kind: ServiceKind.compose),
        ServiceAction.deploy,
      );
      expect(sent!.url.path, '/api/deployComposeService');
      expect(jsonDecode(sent!.body)['forceRebuild'], false);
    });

    test('refuses actions Easypanel does not offer', () async {
      final b = EasypanelBackend(
        url: 'https://x.test',
        token: 't',
        client: MockClient((_) async => fail('must not call the network')),
      );
      await expectLater(
        b.perform(const ServiceInfo(project: 'p', name: 'db', kind: ServiceKind.postgres), ServiceAction.stop),
        throwsA(isA<PanelException>()),
      );
      await expectLater(
        b.perform(const ServiceInfo(project: 'p', name: 'box', kind: ServiceKind.box), ServiceAction.deploy),
        throwsA(isA<PanelException>()),
      );
    });

    test('login returns the token wherever the server nests it', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/api/login');
        expect(jsonDecode(req.body), {'email': 'a@b.co', 'password': 'pw'});
        return json({
          'result': {
            'data': {'session': 'x', 'token': 'abc123'},
          },
        });
      });
      final token = await EasypanelBackend.login(url: 'https://x.test', email: 'a@b.co', password: 'pw', client: client);
      expect(token, 'abc123');
    });

    test('maps system stats including string-typed disk values', () async {
      final client = MockClient((_) async => json({
            'cpuInfo': {'count': 4, 'loadavg': [0.1, 0.2, 0.3], 'usedPercentage': 12.5},
            'memInfo': {'totalMemMb': 8000, 'usedMemMb': 2000, 'usedMemPercentage': 25},
            'diskInfo': {'totalGb': '100.0', 'usedGb': '40.0', 'usedPercentage': '40'},
            'network': {'inputMb': 5, 'outputMb': 7},
            'uptime': 3600,
          }));
      final st = (await EasypanelBackend(url: 'https://x.test', token: 't', client: client).systemStats())!;
      expect(st.cpuCores, 4);
      expect(st.diskPercent, 40);
      expect(st.diskTotalGb, 100);
      expect(st.uptime, const Duration(hours: 1));
    });
  });
}
