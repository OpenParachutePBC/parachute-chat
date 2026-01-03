import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Status of the managed server process
enum ServerState {
  stopped,
  starting,
  running,
  stopping,
  failed,
  restarting,
  unknown;

  static ServerState fromString(String? value) {
    if (value == null) return unknown;
    return ServerState.values.firstWhere(
      (e) => e.name == value,
      orElse: () => unknown,
    );
  }
}

/// Information about the supervisor and server status
class SupervisorStatus {
  final bool supervisorRunning;
  final ServerState serverState;
  final int? pid;
  final DateTime? startedAt;
  final DateTime? lastHealthCheck;
  final int restartCount;
  final String? lastError;
  final double uptimeSeconds;
  final String? vaultPath;
  final int? serverPort;
  final String? serverHost;

  SupervisorStatus({
    required this.supervisorRunning,
    required this.serverState,
    this.pid,
    this.startedAt,
    this.lastHealthCheck,
    this.restartCount = 0,
    this.lastError,
    this.uptimeSeconds = 0,
    this.vaultPath,
    this.serverPort,
    this.serverHost,
  });

  factory SupervisorStatus.fromJson(Map<String, dynamic> json) {
    final server = json['server'] as Map<String, dynamic>?;
    final config = json['config'] as Map<String, dynamic>?;

    return SupervisorStatus(
      supervisorRunning: json['supervisor'] == 'running',
      serverState: ServerState.fromString(server?['state'] as String?),
      pid: server?['pid'] as int?,
      startedAt: server?['started_at'] != null
          ? DateTime.tryParse(server!['started_at'] as String)
          : null,
      lastHealthCheck: server?['last_health_check'] != null
          ? DateTime.tryParse(server!['last_health_check'] as String)
          : null,
      restartCount: server?['restart_count'] as int? ?? 0,
      lastError: server?['last_error'] as String?,
      uptimeSeconds: (server?['uptime_seconds'] as num?)?.toDouble() ?? 0,
      vaultPath: config?['vault_path'] as String?,
      serverPort: config?['port'] as int?,
      serverHost: config?['host'] as String?,
    );
  }

  factory SupervisorStatus.unavailable() {
    return SupervisorStatus(
      supervisorRunning: false,
      serverState: ServerState.unknown,
    );
  }

  String get uptimeFormatted {
    if (uptimeSeconds <= 0) return '-';
    final duration = Duration(seconds: uptimeSeconds.toInt());
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }
}

/// Result of a supervisor action (start/stop/restart)
class SupervisorActionResult {
  final bool success;
  final ServerState? serverState;
  final String? error;

  SupervisorActionResult({
    required this.success,
    this.serverState,
    this.error,
  });

  factory SupervisorActionResult.fromJson(Map<String, dynamic> json) {
    final server = json['server'] as Map<String, dynamic>?;
    return SupervisorActionResult(
      success: json['success'] as bool? ?? false,
      serverState: ServerState.fromString(server?['state'] as String?),
    );
  }

  factory SupervisorActionResult.failure(String error) {
    return SupervisorActionResult(
      success: false,
      error: error,
    );
  }
}

/// Service for communicating with the Parachute Supervisor
class SupervisorService {
  final String supervisorUrl;
  final http.Client _client;

  static const _timeout = Duration(seconds: 10);

  SupervisorService({required this.supervisorUrl}) : _client = http.Client();

  /// Derive supervisor URL from server URL (port 3333 -> 3330)
  static String supervisorUrlFromServerUrl(String serverUrl) {
    final uri = Uri.parse(serverUrl);
    // Supervisor runs on port 3330, server on 3333
    final supervisorPort = uri.port == 3333 ? 3330 : uri.port - 3;
    return '${uri.scheme}://${uri.host}:$supervisorPort';
  }

  /// Get supervisor and server status
  Future<SupervisorStatus> getStatus() async {
    try {
      final response = await _client.get(
        Uri.parse('$supervisorUrl/supervisor/status'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint('[SupervisorService] Status failed: ${response.statusCode}');
        return SupervisorStatus.unavailable();
      }

      return SupervisorStatus.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('[SupervisorService] Error getting status: $e');
      return SupervisorStatus.unavailable();
    }
  }

  /// Start the server
  Future<SupervisorActionResult> startServer() async {
    return _performAction('start');
  }

  /// Stop the server
  Future<SupervisorActionResult> stopServer() async {
    return _performAction('stop');
  }

  /// Restart the server
  Future<SupervisorActionResult> restartServer() async {
    return _performAction('restart');
  }

  Future<SupervisorActionResult> _performAction(String action) async {
    try {
      final response = await _client.post(
        Uri.parse('$supervisorUrl/supervisor/$action'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(_timeout);

      if (response.statusCode != 200) {
        return SupervisorActionResult.failure(
          'Server returned ${response.statusCode}',
        );
      }

      return SupervisorActionResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('[SupervisorService] Error performing $action: $e');
      return SupervisorActionResult.failure(e.toString());
    }
  }

  /// Check if supervisor is reachable
  Future<bool> isAvailable() async {
    try {
      final response = await _client.get(
        Uri.parse('$supervisorUrl/supervisor/status'),
      ).timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _client.close();
  }
}
