import 'models.dart';

/// What every supported control panel must offer. The UI only knows this.
abstract class PanelBackend {
  /// Throws [PanelException] when the address or token is wrong.
  Future<void> verify();

  Future<List<ServiceInfo>> services();

  Future<SystemStats?> systemStats();

  Future<void> perform(ServiceInfo service, ServiceAction action);

  /// Recent builds, deployments and other recorded actions for a service, newest first.
  Future<List<ActivityEntry>> activity(ServiceInfo service, {int limit = 30});

  /// Full text of one activity entry (for example a build log).
  Future<String> activityLog(String id);

  /// Runtime (stdout/stderr) log lines. Throws [LogsUnavailable] when the panel is not
  /// collecting logs.
  Future<List<LogLine>> runtimeLogs(ServiceInfo service, {String? search, int limit = 200});

  void close();
}
