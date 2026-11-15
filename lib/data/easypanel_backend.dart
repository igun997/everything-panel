import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'models.dart';
import 'openapi.dart';
import 'panel_backend.dart';

/// Easypanel REST API (https://easypanel.io/docs/api).
///
/// Operations are flat: `GET|POST {url}/api/{operationId}` with
/// `Authorization: Bearer <token>`. Queries take URL parameters, mutations a
/// JSON body.
class EasypanelBackend implements PanelBackend, ApiExplorerBackend {
  EasypanelBackend({required String url, required this.token, http.Client? client, ApiCatalog? catalog})
      : _base = _normalize(url),
        _client = client ?? http.Client(),
        _catalog = catalog;

  final String _base;
  final String token;
  final http.Client _client;
  final ApiCatalog? _catalog;

  /// The documented API, loaded once at startup from the bundled OpenAPI file.
  static ApiCatalog? bundledCatalog;

  @override
  ApiCatalog get catalog => _catalog ?? bundledCatalog ?? (throw PanelException('The API catalog is not loaded.'));

  static const _timeout = Duration(seconds: 20);

  static String _normalize(String url) {
    var u = url.trim();
    if (!u.contains('://')) u = 'https://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.endsWith('/api')) u = u.substring(0, u.length - 4);
    return u;
  }

  /// Exchanges email/password for a token. Credentials are never stored.
  static Future<String> login({
    required String url,
    required String email,
    required String password,
    String? code,
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    try {
      final res = await c
          .post(
            Uri.parse('${_normalize(url)}/api/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'password': password,
              if (code != null && code.isNotEmpty) 'code': code,
            }),
          )
          .timeout(_timeout);
      final body = _decode(res);
      final token = _findToken(body);
      if (token == null) {
        throw PanelException('Login succeeded but the server returned no token.');
      }
      return token;
    } finally {
      if (client == null) c.close();
    }
  }

  static String? _findToken(Object? v) {
    if (v is Map) {
      final t = v['token'];
      if (t is String && t.isNotEmpty) return t;
      for (final value in v.values) {
        final nested = _findToken(value);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

  Future<Object?> _get(String op, [Map<String, String>? query]) async {
    final uri = Uri.parse('$_base/api/$op').replace(queryParameters: query);
    return _send(() => _client.get(uri, headers: _headers));
  }

  Future<Object?> _post(String op, Map<String, Object?> body) async {
    final uri = Uri.parse('$_base/api/$op');
    return _send(() => _client.post(
          uri,
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ));
  }

  Future<Object?> _send(Future<http.Response> Function() call) async {
    try {
      return _decode(await call().timeout(_timeout));
    } on PanelException {
      rethrow;
    } on FormatException {
      throw PanelException('That address did not answer like an Easypanel server.');
    } on Exception catch (e) {
      throw PanelException('Cannot reach the server: ${_short(e)}');
    }
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}...' : s;
  }

  /// Unwraps `{result: {data: {json: x}}}`-style envelopes if a server adds them.
  static Object? _unwrap(Object? v) {
    var cur = v;
    for (final key in const ['result', 'data', 'json']) {
      if (cur is Map && cur.length == 1 && cur.containsKey(key)) cur = cur[key];
    }
    return cur;
  }

  static Object? _decode(http.Response res) {
    Object? json;
    if (res.body.isNotEmpty) {
      try {
        json = jsonDecode(utf8.decode(res.bodyBytes));
      } on FormatException {
        if (res.statusCode >= 400) {
          throw PanelException('Server error ${res.statusCode}.', unauthorized: res.statusCode == 401);
        }
        rethrow;
      }
    }
    if (res.statusCode >= 400) {
      final msg = _errorMessage(json) ?? 'Server error ${res.statusCode}.';
      throw PanelException(
        res.statusCode == 401 || res.statusCode == 403 ? 'Token rejected: $msg' : msg,
        unauthorized: res.statusCode == 401 || res.statusCode == 403,
      );
    }
    return _unwrap(json);
  }

  static String? _errorMessage(Object? json) {
    if (json is Map) {
      for (final k in const ['message', 'error']) {
        final v = json[k];
        if (v is String && v.isNotEmpty) return v;
        if (v is Map) {
          final nested = _errorMessage(v);
          if (nested != null) return nested;
        }
      }
    }
    return null;
  }

  @override
  Future<List<ServiceInfo>> services() async {
    final data = await _get('listProjectsAndServices');
    final list = data is Map ? data['services'] : null;
    if (list is! List) throw PanelException('Unexpected response while listing services.');
    final services = <ServiceInfo>[
      for (final s in list.whereType<Map>())
        if (s['name'] is String && s['projectName'] is String)
          ServiceInfo(
            project: s['projectName'] as String,
            name: s['name'] as String,
            kind: ServiceKind.parse(s['type'] as String?),
          ),
    ];

    // Usage is best effort: a failing monitor must not hide the service list.
    final usage = await _usageByService().catchError((_) => <String, ServiceUsage>{});
    return [for (final s in services) s.withUsage(usage[s.key])];
  }

  Future<Map<String, ServiceUsage>> _usageByService() async {
    final data = await _get('getMonitorTableData');
    if (data is! List) return {};
    final acc = <String, List<double>>{}; // key -> [cpu, mem, count]
    for (final row in data.whereType<Map>()) {
      final project = row['projectName'], name = row['serviceName'];
      if (project is! String || name is! String) continue;
      final stats = row['stats'];
      final cpu = _num(stats is Map ? (stats['cpu'] is Map ? (stats['cpu'] as Map)['percent'] : null) : null);
      final mem = _num(stats is Map ? (stats['memory'] is Map ? (stats['memory'] as Map)['percent'] : null) : null);
      final a = acc.putIfAbsent('$project/$name', () => [0, 0, 0]);
      a[0] += cpu;
      a[1] += mem;
      a[2] += 1;
    }
    return {
      for (final e in acc.entries)
        e.key: ServiceUsage(cpuPercent: e.value[0], memPercent: e.value[1], containers: e.value[2].toInt()),
    };
  }

  @override
  Future<SystemStats?> systemStats() async {
    final d = await _get('getLegacyMonitorSystemStats');
    if (d is! Map) return null;
    final cpu = d['cpuInfo'] is Map ? d['cpuInfo'] as Map : const {};
    final mem = d['memInfo'] is Map ? d['memInfo'] as Map : const {};
    final disk = d['diskInfo'] is Map ? d['diskInfo'] as Map : const {};
    final net = d['network'] is Map ? d['network'] as Map : const {};
    return SystemStats(
      cpuPercent: _num(cpu['usedPercentage']),
      cpuCores: _num(cpu['count']).toInt(),
      load: [
        if (cpu['loadavg'] is List) for (final l in cpu['loadavg'] as List) _num(l),
      ],
      memPercent: _num(mem['usedMemPercentage']),
      memUsedMb: _num(mem['usedMemMb']),
      memTotalMb: _num(mem['totalMemMb']),
      diskPercent: _num(disk['usedPercentage']),
      diskUsedGb: _num(disk['usedGb']),
      diskTotalGb: _num(disk['totalGb']),
      netInMb: _num(net['inputMb']),
      netOutMb: _num(net['outputMb']),
      uptime: Duration(seconds: _num(d['uptime']).toInt()),
    );
  }

  static double _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static String? _typeSuffix(ServiceKind k) => switch (k) {
        ServiceKind.app => 'App',
        ServiceKind.compose => 'Compose',
        ServiceKind.box => 'Box',
        ServiceKind.wordpress => 'WordPress',
        _ => null,
      };

  @override
  Future<void> perform(ServiceInfo service, ServiceAction action) async {
    final suffix = _typeSuffix(service.kind);
    final supported = action == ServiceAction.deploy ? service.kind.canDeploy : service.kind.canControl;
    if (suffix == null || !supported) {
      throw PanelException('${action.label} is not available for ${service.kind.label} services.');
    }
    await _post('${action.verb}${suffix}Service', {
      'projectName': service.project,
      'serviceName': service.name,
      if (action == ServiceAction.deploy) 'forceRebuild': false,
    });
  }

  @override
  Future<void> verify() async {
    // The cheapest authenticated call; throws PanelException on a bad token.
    await _get('getUser');
  }

  /// Easypanel sends timestamps like `2026-11-15T07:44:11` without a zone; they are UTC.
  static DateTime? _utc(String s) {
    if (s.isEmpty) return null;
    final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
    return DateTime.tryParse(hasZone ? s : '${s}Z');
  }

  @override
  Future<List<ActivityEntry>> activity(ServiceInfo service, {int limit = 30}) async {
    final data = await _get('listActions', {
      'limit': '$limit',
      'projectName': service.project,
      'serviceName': service.name,
    });
    if (data is! List) return const [];
    return [
      for (final a in data.whereType<Map>())
        if (a['id'] is String)
          ActivityEntry(
            id: a['id'] as String,
            type: '${a['type'] ?? 'action'}',
            status: '${a['status'] ?? ''}',
            description: '${a['description'] ?? ''}',
            createdAt: _utc('${a['createdAt'] ?? ''}'),
            hasLog: a['noLogs'] != true,
          ),
    ];
  }

  @override
  Future<String> activityLog(String id) async {
    final data = await _get('getAction', {'id': id});
    final log = data is Map ? data['log'] : null;
    return log is String ? log : '';
  }

  @override
  Future<List<LogLine>> runtimeLogs(ServiceInfo service, {String? search, int limit = 200}) async {
    // Runtime logs come from Loki, which Easypanel only deploys when log aggregation is on.
    final settings = await _get('getLogsSettings');
    if (settings is Map && settings['enabled'] == false) {
      throw LogsUnavailable(
        'Runtime logs are off on this panel. Turn on log aggregation in Easypanel (Settings, Logs) to see them here. '
        'The Activity tab works without it.',
      );
    }
    final op = service.kind == ServiceKind.compose ? 'queryComposeServiceLogs' : 'queryServiceLogs';
    final data = await _get(op, {
      'projectName': service.project,
      'serviceName': service.name,
      'limit': '$limit',
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    });
    return parseLogs(data);
  }

  /// Accepts the shapes a log query is likely to return: a list of strings, a list of
  /// objects, either of those under a common key, or Loki's `result[].values` streams.
  /// The result is sorted oldest to newest when timestamps are present.
  @visibleForTesting
  static List<LogLine> parseLogs(Object? data) {
    Object? list = data;
    if (list is Map) {
      for (final k in const ['logs', 'entries', 'lines', 'data', 'result']) {
        if (list is Map && list.containsKey(k)) {
          list = list[k];
          if (list is Map && list.containsKey('result')) list = list['result'];
          break;
        }
      }
    }
    if (list is! List) return const [];

    DateTime? time(Object? v) {
      if (v is num) {
        // Loki uses nanoseconds, others seconds or milliseconds.
        final n = v.toDouble();
        final ms = n > 1e17 ? n / 1e6 : (n > 1e11 ? n : n * 1000);
        return DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
      }
      if (v is String) {
        final asNum = num.tryParse(v);
        return asNum != null ? time(asNum) : DateTime.tryParse(v);
      }
      return null;
    }

    final out = <LogLine>[];
    for (final e in list) {
      if (e is String) {
        out.add(LogLine(message: e));
      } else if (e is Map && e['values'] is List) {
        // Loki stream: {stream: {labels}, values: [[ns, line], ...]}
        final labels = e['stream'] is Map ? e['stream'] as Map : const {};
        for (final v in (e['values'] as List).whereType<List>()) {
          if (v.length >= 2) {
            out.add(LogLine(
              message: '${v[1]}',
              time: time(v[0]),
              level: labels['level']?.toString(),
              stream: labels['stream']?.toString(),
            ));
          }
        }
      } else if (e is Map) {
        final msg = e['message'] ?? e['line'] ?? e['log'] ?? e['text'] ?? e['msg'];
        if (msg == null) continue;
        out.add(LogLine(
          message: '$msg',
          time: time(e['timestamp'] ?? e['time'] ?? e['ts'] ?? e['date']),
          level: (e['level'] ?? e['severity'])?.toString(),
          stream: e['stream']?.toString(),
        ));
      }
    }
    if (out.isNotEmpty && out.every((l) => l.time != null)) {
      out.sort((a, b) => a.time!.compareTo(b.time!));
    }
    return out;
  }

  @override
  void close() => _client.close();

  @override
  Future<Object?> invoke(ApiOperation op, Map<String, Object?> input) async {
    if (op.isRead) {
      final query = <String, List<String>>{};
      for (final f in op.fields.where((f) => f.inQuery)) {
        final v = input[f.name];
        if (v == null || (v is String && v.isEmpty)) continue;
        query[f.name] = v is List ? [for (final e in v) '$e'] : ['$v'];
      }
      final uri = Uri.parse('$_base/api/${op.id}').replace(queryParameters: query.isEmpty ? null : query);
      return _send(() => _client.get(uri, headers: _headers));
    }
    final body = <String, Object?>{
      for (final f in op.fields)
        if (input[f.name] != null && !(input[f.name] is String && (input[f.name] as String).isEmpty)) f.name: input[f.name],
    };
    return _post(op.id, body);
  }
}
