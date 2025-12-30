import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Log levels for categorizing messages
enum LogLevel { debug, info, warning, error }

/// A single log entry with timestamp and metadata
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
  });

  String get formatted {
    final levelStr = level.name.toUpperCase().padRight(5);
    final timeStr = timestamp.toIso8601String().substring(
      11,
      23,
    ); // HH:mm:ss.SSS
    final errorStr = error != null ? '\n  Error: $error' : '';
    final stackStr = stackTrace != null ? '\n  Stack: $stackTrace' : '';
    return '[$timeStr] $levelStr [$tag] $message$errorStr$stackStr';
  }

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'tag': tag,
    'message': message,
    if (error != null) 'error': error.toString(),
  };
}

/// Centralized logging service with:
/// - Rolling in-memory buffer (last 500 entries)
/// - Local file logging (flushed periodically)
class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();

  /// Maximum entries to keep in memory
  static const int maxBufferSize = 500;

  /// How often to flush logs to file (in debug/file mode)
  static const Duration flushInterval = Duration(minutes: 5);

  /// Maximum log file size before rotation (1MB)
  static const int maxLogFileSize = 1024 * 1024;

  /// Number of old log files to keep
  static const int maxLogFiles = 5;

  /// In-memory log buffer (circular)
  final Queue<LogEntry> _buffer = Queue<LogEntry>();

  /// File for local logging
  File? _logFile;

  /// Timer for periodic file flush
  Timer? _flushTimer;

  /// Pending logs to write to file
  final List<LogEntry> _pendingFileWrites = [];

  /// Initialize the logging service
  Future<void> initialize({
    String? sentryDsn, // Kept for API compatibility, ignored
    String? environment,
    String? release,
  }) async {
    // Initialize local file logging
    await _initializeFileLogging();

    // Start periodic flush timer
    _flushTimer = Timer.periodic(flushInterval, (_) => flushToFile());

    info('LoggingService', 'Logging service initialized (file logging only)');
  }

  Future<void> _initializeFileLogging() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final logsDir = Directory('${directory.path}/logs');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      final today = DateTime.now().toIso8601String().substring(0, 10);
      _logFile = File('${logsDir.path}/parachute_$today.log');

      // Rotate old logs if needed
      await _rotateLogsIfNeeded(logsDir);

      debugPrint(
        '[LoggingService] File logging initialized: ${_logFile!.path}',
      );
    } catch (e) {
      debugPrint('[LoggingService] Failed to initialize file logging: $e');
    }
  }

  Future<void> _rotateLogsIfNeeded(Directory logsDir) async {
    try {
      final logFiles = await logsDir
          .list()
          .where((f) => f is File && f.path.endsWith('.log'))
          .cast<File>()
          .toList();

      // Sort by modification time (newest first)
      logFiles.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );

      // Delete old files beyond the limit
      if (logFiles.length > maxLogFiles) {
        for (var i = maxLogFiles; i < logFiles.length; i++) {
          await logFiles[i].delete();
          debugPrint(
            '[LoggingService] Deleted old log file: ${logFiles[i].path}',
          );
        }
      }

      // Check if current log file is too large
      if (_logFile != null && await _logFile!.exists()) {
        final size = await _logFile!.length();
        if (size > maxLogFileSize) {
          // Rename current file with timestamp
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final newPath = _logFile!.path.replaceAll('.log', '_$timestamp.log');
          await _logFile!.rename(newPath);
          _logFile = File(_logFile!.path); // Create new file
        }
      }
    } catch (e) {
      debugPrint('[LoggingService] Error rotating logs: $e');
    }
  }

  /// Log a message at the specified level
  void log(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );

    // Add to in-memory buffer
    _buffer.add(entry);
    while (_buffer.length > maxBufferSize) {
      _buffer.removeFirst();
    }

    // Add to pending file writes
    _pendingFileWrites.add(entry);

    // Print to console in debug mode
    if (!kReleaseMode) {
      debugPrint(entry.formatted);
    }
  }

  /// Convenience methods for each log level
  void debug(String tag, String message) => log(LogLevel.debug, tag, message);
  void info(String tag, String message) => log(LogLevel.info, tag, message);
  void warning(String tag, String message, {Object? error}) =>
      log(LogLevel.warning, tag, message, error: error);
  void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => log(LogLevel.error, tag, message, error: error, stackTrace: stackTrace);

  /// Capture an exception (logs locally)
  Future<void> captureException(
    Object exception, {
    StackTrace? stackTrace,
    String? tag,
    Map<String, dynamic>? extras,
  }) async {
    // Log locally
    error(
      tag ?? 'Exception',
      exception.toString(),
      error: exception,
      stackTrace: stackTrace,
    );
  }

  /// Flush pending logs to file
  Future<void> flushToFile() async {
    if (_pendingFileWrites.isEmpty || _logFile == null) return;

    try {
      final entries = List<LogEntry>.from(_pendingFileWrites);
      _pendingFileWrites.clear();

      final content = '${entries.map((e) => e.formatted).join('\n')}\n';
      await _logFile!.writeAsString(content, mode: FileMode.append);
    } catch (e) {
      debugPrint('[LoggingService] Failed to flush logs to file: $e');
    }
  }

  /// Get recent logs (for debugging UI or crash reports)
  List<LogEntry> getRecentLogs({int count = 100}) {
    return _buffer.toList().reversed.take(count).toList();
  }

  /// Get path to current log file
  String? get logFilePath => _logFile?.path;

  /// Get all log file paths
  Future<List<String>> getLogFilePaths() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final logsDir = Directory('${directory.path}/logs');
      if (!await logsDir.exists()) return [];

      final files = await logsDir
          .list()
          .where((f) => f is File && f.path.endsWith('.log'))
          .map((f) => f.path)
          .toList();

      files.sort((a, b) => b.compareTo(a)); // Newest first
      return files;
    } catch (e) {
      return [];
    }
  }

  /// Clean up resources
  Future<void> dispose() async {
    _flushTimer?.cancel();
    await flushToFile();
  }
}

/// Global logging instance for convenience
final logger = LoggingService();
