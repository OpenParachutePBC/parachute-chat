import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/voice_input_service.dart';
import '../services/audio_service.dart';
import '../services/transcription_service.dart';

/// Voice input service singleton
final voiceInputServiceProvider = Provider<VoiceInputService>((ref) {
  final service = VoiceInputService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Audio service singleton
final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Transcription service singleton
final transcriptionServiceProvider = Provider<TranscriptionService>((ref) {
  final service = TranscriptionService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Voice input state stream
final voiceInputStateProvider = StreamProvider<VoiceInputState>((ref) {
  final service = ref.watch(voiceInputServiceProvider);
  return service.stateStream;
});

/// Current voice input state
final voiceInputCurrentStateProvider = Provider<VoiceInputState>((ref) {
  return ref.watch(voiceInputStateProvider).when(
    data: (state) => state,
    loading: () => VoiceInputState.idle,
    error: (_, __) => VoiceInputState.idle,
  );
});

/// Recording duration stream
final voiceInputDurationProvider = StreamProvider<Duration>((ref) {
  final service = ref.watch(voiceInputServiceProvider);
  return service.durationStream;
});

/// Transcript stream (emits each transcription result)
final voiceInputTranscriptProvider = StreamProvider<String>((ref) {
  final service = ref.watch(voiceInputServiceProvider);
  return service.transcriptStream;
});

/// Error stream
final voiceInputErrorProvider = StreamProvider<String>((ref) {
  final service = ref.watch(voiceInputServiceProvider);
  return service.errorStream;
});

/// Whether transcription models are ready
final transcriptionReadyProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(transcriptionServiceProvider);
  return await service.isReady();
});
