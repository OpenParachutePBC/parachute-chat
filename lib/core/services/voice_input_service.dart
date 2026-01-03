import 'dart:async';
import 'package:flutter/foundation.dart';

import 'audio_service.dart';
import 'transcription_service.dart';

/// Voice input states
enum VoiceInputState {
  idle,
  recording,
  transcribing,
  error,
}

/// Combined service for voice input in chat
///
/// Handles recording audio and transcribing it to text.
class VoiceInputService {
  final AudioService _audioService = AudioService();
  final TranscriptionService _transcriptionService = TranscriptionService();

  final _stateController = StreamController<VoiceInputState>.broadcast();
  final _transcriptController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();

  VoiceInputState _state = VoiceInputState.idle;
  Timer? _durationTimer;

  VoiceInputState get state => _state;
  Stream<VoiceInputState> get stateStream => _stateController.stream;
  Stream<String> get transcriptStream => _transcriptController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<Duration> get durationStream => _durationController.stream;

  bool get isRecording => _state == VoiceInputState.recording;
  bool get isTranscribing => _state == VoiceInputState.transcribing;
  bool get isIdle => _state == VoiceInputState.idle;

  /// Initialize the voice input service
  Future<void> initialize() async {
    await _audioService.initialize();
    // Transcription service initializes lazily on first use
  }

  /// Start recording voice input
  Future<bool> startRecording() async {
    if (_state != VoiceInputState.idle) {
      debugPrint('[VoiceInputService] Cannot start: state is $_state');
      return false;
    }

    final success = await _audioService.startRecording();
    if (success) {
      _setState(VoiceInputState.recording);
      _startDurationUpdates();
      debugPrint('[VoiceInputService] Recording started');
    } else {
      _errorController.add('Failed to start recording. Check microphone permissions.');
    }
    return success;
  }

  /// Stop recording and transcribe
  ///
  /// Returns the transcribed text, or null if cancelled or failed.
  Future<String?> stopAndTranscribe() async {
    if (_state != VoiceInputState.recording) {
      debugPrint('[VoiceInputService] Cannot stop: state is $_state');
      return null;
    }

    _stopDurationUpdates();

    final audioPath = await _audioService.stopRecording();
    if (audioPath == null) {
      _setState(VoiceInputState.idle);
      _errorController.add('Recording failed');
      return null;
    }

    _setState(VoiceInputState.transcribing);

    try {
      debugPrint('[VoiceInputService] Transcribing: $audioPath');
      final result = await _transcriptionService.transcribeAudio(audioPath);
      final text = result.text.trim();

      debugPrint('[VoiceInputService] Transcribed: "$text"');
      _transcriptController.add(text);
      _setState(VoiceInputState.idle);

      return text;
    } catch (e) {
      debugPrint('[VoiceInputService] Transcription error: $e');
      _errorController.add('Transcription failed: $e');
      _setState(VoiceInputState.error);

      // Reset to idle after a delay
      Future.delayed(const Duration(seconds: 2), () {
        if (_state == VoiceInputState.error) {
          _setState(VoiceInputState.idle);
        }
      });

      return null;
    }
  }

  /// Cancel recording without transcribing
  Future<void> cancelRecording() async {
    if (_state != VoiceInputState.recording) return;

    _stopDurationUpdates();
    await _audioService.cancelRecording();
    _setState(VoiceInputState.idle);
    debugPrint('[VoiceInputService] Recording cancelled');
  }

  void _setState(VoiceInputState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void _startDurationUpdates() {
    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _durationController.add(_audioService.recordingDuration);
    });
  }

  void _stopDurationUpdates() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  /// Check if transcription is ready (models downloaded)
  Future<bool> isTranscriptionReady() async {
    return await _transcriptionService.isReady();
  }

  /// Pre-initialize transcription models (call at app startup)
  Future<void> preloadTranscription({
    Function(double)? onProgress,
    Function(String)? onStatus,
  }) async {
    try {
      await _transcriptionService.initialize(
        onProgress: onProgress,
        onStatus: onStatus,
      );
    } catch (e) {
      debugPrint('[VoiceInputService] Pre-load failed: $e');
    }
  }

  void dispose() {
    _durationTimer?.cancel();
    _stateController.close();
    _transcriptController.close();
    _errorController.close();
    _durationController.close();
    _audioService.dispose();
    _transcriptionService.dispose();
  }
}
