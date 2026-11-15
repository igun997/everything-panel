import 'package:flutter/foundation.dart';

/// Which kind of control panel a server profile talks to.
/// Easypanel is the first backend; others plug in behind `PanelBackend`.
enum PanelKind {
  easypanel('Easypanel');

  const PanelKind(this.label);
  final String label;

  static PanelKind parse(String? v) =>
      PanelKind.values.firstWhere((k) => k.name == v, orElse: () => PanelKind.easypanel);
}

/// A saved server. The token itself lives in secure storage, never here.
@immutable
class ServerProfile {
  const ServerProfile({
    required this.id,
    required this.name,
    required this.url,
    this.kind = PanelKind.easypanel,
  });

  final String id;
  final String name;
  final String url;
  final PanelKind kind;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'url': url, 'kind': kind.name};

  factory ServerProfile.fromJson(Map<String, dynamic> j) => ServerProfile(
        id: j['id'] as String,
        name: j['name'] as String,
        url: j['url'] as String,
        kind: PanelKind.parse(j['kind'] as String?),
      );
}

enum ServiceKind {
  app('App', 'app'),
  compose('Compose', 'compose'),
  box('Box', 'box'),
  wordpress('WordPress', 'wordpress'),
  mysql('MySQL', 'mysql'),
  mariadb('MariaDB', 'mariadb'),
  postgres('Postgres', 'postgres'),
  mongo('MongoDB', 'mongo'),
  redis('Redis', 'redis'),
  other('Service', 'other');

  const ServiceKind(this.label, this.raw);
  final String label;
  final String raw;

  static ServiceKind parse(String? v) {
    final s = (v ?? '').toLowerCase();
    return ServiceKind.values.firstWhere(
      (k) => k.raw == s || (s == 'mongodb' && k == ServiceKind.mongo),
      orElse: () => ServiceKind.other,
    );
  }

  bool get isDatabase => const {mysql, mariadb, postgres, mongo, redis}.contains(this);

  /// Easypanel exposes start/stop/restart for these kinds only.
  bool get canControl => const {app, compose, box, wordpress}.contains(this);

  /// Only apps and compose stacks can be (re)deployed from source.
  bool get canDeploy => this == app || this == compose;
}

enum ServiceAction {
  start('Start', 'start'),
  stop('Stop', 'stop'),
  restart('Restart', 'restart'),
  deploy('Deploy', 'deploy');

  const ServiceAction(this.label, this.verb);
  final String label;
  final String verb;

  /// Interrupts a running workload; ask before doing it.
  bool get isDisruptive => this != start;
}

/// Live resource numbers for one service (summed over its containers).
@immutable
class ServiceUsage {
  const ServiceUsage({required this.cpuPercent, required this.memPercent, required this.containers});
  final double cpuPercent;
  final double memPercent;
  final int containers;
}

@immutable
class ServiceInfo {
  const ServiceInfo({
    required this.project,
    required this.name,
    required this.kind,
    this.usage,
  });

  final String project;
  final String name;
  final ServiceKind kind;
  final ServiceUsage? usage;

  String get key => '$project/$name';
  bool get isRunning => (usage?.containers ?? 0) > 0;

  ServiceInfo withUsage(ServiceUsage? u) => ServiceInfo(project: project, name: name, kind: kind, usage: u);
}

@immutable
class SystemStats {
  const SystemStats({
    required this.cpuPercent,
    required this.cpuCores,
    required this.load,
    required this.memPercent,
    required this.memUsedMb,
    required this.memTotalMb,
    required this.diskPercent,
    required this.diskUsedGb,
    required this.diskTotalGb,
    required this.netInMb,
    required this.netOutMb,
    required this.uptime,
  });

  final double cpuPercent;
  final int cpuCores;
  final List<double> load;
  final double memPercent;
  final double memUsedMb;
  final double memTotalMb;
  final double diskPercent;
  final double diskUsedGb;
  final double diskTotalGb;
  final double netInMb;
  final double netOutMb;
  final Duration uptime;
}

class PanelException implements Exception {
  PanelException(this.message, {this.unauthorized = false});
  final String message;
  final bool unauthorized;
  @override
  String toString() => message;
}

/// One line of a service's runtime log.
@immutable
class LogLine {
  const LogLine({required this.message, this.time, this.level, this.stream});
  final String message;
  final DateTime? time;
  final String? level;
  final String? stream;
}

/// A recorded action on a service: a build, deployment, start, stop, settings change.
@immutable
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.type,
    required this.status,
    required this.description,
    required this.createdAt,
    required this.hasLog,
  });
  final String id;
  final String type;
  final String status;
  final String description;
  final DateTime? createdAt;
  final bool hasLog;
}

/// Runtime logs exist but the panel has not been set up to collect them.
class LogsUnavailable extends PanelException {
  LogsUnavailable(super.message);
}
