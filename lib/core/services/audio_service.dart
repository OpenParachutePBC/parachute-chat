import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:path_provider/path_provider.dart';

enum RecordingState { stopped, recording, paused }

/// Audio recording service for voice input in chat
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();

  RecordingState _recordingState = RecordingState.stopped;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;
  bool _isInitialized = false;
  Completer<void>? _initCompleter;

  RecordingState get recordingState => _recordingState;
  Duration get recordingDuration => _recordingDuration;
  bool get isInitialized => _isInitialized;
  bool get isRecording => _recordingState == RecordingState.recording;

  /// Access the recorder for amplitude monitoring
  AudioRecorder get recorder => _recorder;

  /// Wait for initialization to complete
  Future<void> ensureInitialized() async {
    if (_isInitialized) return;
    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }
    await initialize();
  }

  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('[AudioService] Already initialized');
      return;
    }

    if (_initCompleter != null) {
      debugPrint('[AudioService] Already initializing, waiting...');
      await _initCompleter!.future;
      return;
    }

    _initCompleter = Completer<void>();

    try {
      debugPrint('[AudioService] Initializing...');

      if (await _recorder.hasPermission()) {
        debugPrint('[AudioService] Recording permissions granted');
      } else {
        debugPrint('[AudioService] Recording permissions not granted');
      }

      _isInitialized = true;
      _initCompleter!.complete();
      debugPrint('[AudioService] Initialized successfully');
    } catch (e, stackTrace) {
      debugPrint('[AudioService] Error initializing: $e');
      debugPrint('Stack trace: $stackTrace');
      _isInitialized = false;
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  Future<void> dispose() async {
    _durationTimer?.cancel();

    try {
      if (await WakelockPlus.enabled) {
        await WakelockPlus.disable();
      }
    } catch (e) {
      debugPrint('[AudioService] Error disabling wakelock: $e');
    }

    await _recorder.dispose();
    _isInitialized = false;
    debugPrint('[AudioService] Disposed');
  }

  Future<bool> requestPermissions() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      debugPrint('[AudioService] Permission check: $hasPermission');

      if (!hasPermission) {
        if (Platform.isAndroid) {
          try {
            final micPermission = await Permission.microphone.status;
            if (micPermission.isPermanentlyDenied) {
              await openAppSettings();
            }
          } catch (e) {
            debugPrint('[AudioService] Could not open settings: $e');
          }
        }
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('[AudioService] Error requesting permissions: $e');
      try {
        return await _recorder.hasPermission();
      } catch (e2) {
        return false;
      }
    }
  }

  Future<String> _getRecordingPath() async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${tempDir.path}/voice_input_$timestamp.wav';
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_recordingState == RecordingState.recording && _recordingStartTime != null) {
        _recordingDuration = DateTime.now().difference(_recordingStartTime!);
      }
    });
  }

  Future<bool> startRecording() async {
    debugPrint('[AudioService] startRecording called, state: $_recordingState');
    if (_recordingState != RecordingState.stopped) {
      debugPrint('[AudioService] Cannot start: state is $_recordingState');
      return false;
    }

    final hasPermission = await requestPermissions();
    if (!hasPermission) {
      debugPrint('[AudioService] Permission denied');
      return false;
    }

    try {
      if (!_isInitialized) {
        await initialize();
      }

      if (await _recorder.isRecording()) {
        debugPrint('[AudioService] Already recording');
        return false;
      }

      _currentRecordingPath = await _getRecordingPath();
      debugPrint('[AudioService] Recording to: $_currentRecordingPath');

      await WakelockPlus.enable();

      // Record as WAV at 16kHz mono (compatible with Parakeet)
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: _currentRecordingPath!,
      );

      _recordingStartTime = DateTime.now();
      _recordingState = RecordingState.recording;
      _recordingDuration = Duration.zero;
      _startDurationTimer();

      debugPrint('[AudioService] Recording started');
      return true;
    } catch (e, stackTrace) {
      debugPrint('[AudioService] Error starting recording: $e');
      debugPrint('Stack trace: $stackTrace');
      _recordingState = RecordingState.stopped;
      _currentRecordingPath = null;
      return false;
    }
  }

  Future<String?> stopRecording() async {
    if (_recordingState == RecordingState.stopped) return null;

    try {
      _durationTimer?.cancel();
      await WakelockPlus.disable();

      final path = await _recorder.stop();
      _recordingState = RecordingState.stopped;
      _currentRecordingPath = null;
      _recordingStartTime = null;

      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          final size = await file.length();
          debugPrint('[AudioService] Recording saved: $path (${size / 1024}KB)');
          return path;
        }
      }

      debugPrint('[AudioService] Recording stopped but file not found');
      return null;
    } catch (e) {
      debugPrint('[AudioService] Error stopping recording: $e');
      _recordingState = RecordingState.stopped;
      _durationTimer?.cancel();
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      return null;
    }
  }

  Future<bool> cancelRecording() async {
    if (_recordingState == RecordingState.stopped) return false;

    try {
      _durationTimer?.cancel();
      await WakelockPlus.disable();

      final path = await _recorder.stop();
      _recordingState = RecordingState.stopped;

      // Delete the recording file
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          debugPrint('[AudioService] Recording cancelled and deleted');
        }
      }

      _currentRecordingPath = null;
      _recordingStartTime = null;
      _recordingDuration = Duration.zero;

      return true;
    } catch (e) {
      debugPrint('[AudioService] Error cancelling recording: $e');
      _recordingState = RecordingState.stopped;
      return false;
    }
  }

  /// Get amplitude stream for visualizing recording
  Stream<Amplitude> get amplitudeStream {
    return Stream.periodic(const Duration(milliseconds: 100), (_) async {
      if (_recordingState == RecordingState.recording) {
        try {
          return await _recorder.getAmplitude();
        } catch (e) {
          return Amplitude(current: -160, max: -160);
        }
      }
      return Amplitude(current: -160, max: -160);
    }).asyncMap((event) => event);
  }
}
