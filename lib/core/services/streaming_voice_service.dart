import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'transcription_service.dart';
import 'vad/smart_chunker.dart';
import 'audio_processing/simple_noise_filter.dart';

/// Transcription model status
enum TranscriptionModelStatus {
  notInitialized, // Model not yet initialized
  initializing, // Model is loading
  ready, // Model ready for transcription
  error, // Initialization failed
}

/// Streaming transcription state for UI
class StreamingTranscriptionState {
  final List<String> confirmedSegments; // Finalized text segments
  final String? interimText; // Currently being transcribed (may change)
  final bool isRecording;
  final bool isProcessing;
  final Duration recordingDuration;
  final double vadLevel; // 0.0 to 1.0 speech energy level
  final TranscriptionModelStatus modelStatus; // Track model initialization

  const StreamingTranscriptionState({
    this.confirmedSegments = const [],
    this.interimText,
    this.isRecording = false,
    this.isProcessing = false,
    this.recordingDuration = Duration.zero,
    this.vadLevel = 0.0,
    this.modelStatus = TranscriptionModelStatus.notInitialized,
  });

  StreamingTranscriptionState copyWith({
    List<String>? confirmedSegments,
    String? interimText,
    bool? clearInterim,
    bool? isRecording,
    bool? isProcessing,
    Duration? recordingDuration,
    double? vadLevel,
    TranscriptionModelStatus? modelStatus,
  }) {
    return StreamingTranscriptionState(
      confirmedSegments: confirmedSegments ?? this.confirmedSegments,
      interimText: clearInterim == true ? null : (interimText ?? this.interimText),
      isRecording: isRecording ?? this.isRecording,
      isProcessing: isProcessing ?? this.isProcessing,
      recordingDuration: recordingDuration ?? this.recordingDuration,
      vadLevel: vadLevel ?? this.vadLevel,
      modelStatus: modelStatus ?? this.modelStatus,
    );
  }

  /// Get all text (confirmed + interim) for display
  /// Uses single newlines between segments for natural flow
  String get displayText {
    final confirmed = confirmedSegments.join('\n');
    if (interimText != null && interimText!.isNotEmpty) {
      return confirmed.isEmpty ? interimText! : '$confirmed\n$interimText';
    }
    return confirmed;
  }
}

/// Streaming voice input service for Chat
///
/// Provides real-time transcription feedback during recording:
/// 1. User starts recording → Continuous audio capture
/// 2. Audio → Noise filter → VAD → Rolling buffer (30s)
/// 3. Every 3s during speech → Re-transcribe last 15s → Stream interim text
/// 4. On 1s silence → Finalize chunk → Confirmed text
/// 5. On stop → Flush with 2s silence → Capture final words
class StreamingVoiceService {
  final TranscriptionService _transcriptionService;

  // Recording state
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  DateTime? _recordingStartTime;
  StreamSubscription<Uint8List>? _audioStreamSubscription;

  // Noise filtering & VAD
  SimpleNoiseFilter? _noiseFilter;
  SmartChunker? _chunker;

  // Rolling buffer for re-transcription (keeps last 30s of audio)
  List<int> _rollingAudioBuffer = [];
  static const int _rollingBufferMaxSamples = 16000 * 30; // 30 seconds
  static const int _reTranscriptionWindowSamples = 16000 * 15; // 15 seconds
  static const Duration _reTranscriptionInterval = Duration(seconds: 3);

  Timer? _reTranscriptionTimer;
  Timer? _recordingDurationTimer;
  String _interimText = '';
  bool _isReTranscribing = false;

  // Confirmed segments (finalized after silence detection)
  final List<String> _confirmedSegments = [];

  // Map from queued segment index to confirmed segment index
  final Map<int, int> _segmentToConfirmedIndex = {};

  // Segment processing
  int _nextSegmentIndex = 1;
  final List<_QueuedSegment> _processingQueue = [];
  bool _isProcessingQueue = false;

  // File management
  String? _audioFilePath;
  IOSink? _audioFileSink;
  int _totalSamplesWritten = 0;

  // Stream controllers
  final _streamingStateController =
      StreamController<StreamingTranscriptionState>.broadcast();
  final _interimTextController = StreamController<String>.broadcast();

  // Track transcription model status
  TranscriptionModelStatus _modelStatus = TranscriptionModelStatus.notInitialized;

  // Audio chunk tracking
  int _audioChunkCount = 0;

  Stream<StreamingTranscriptionState> get streamingStateStream =>
      _streamingStateController.stream;

  Stream<String> get interimTextStream => _interimTextController.stream;

  bool get isRecording => _isRecording;
  List<String> get confirmedSegments => List.unmodifiable(_confirmedSegments);
  String get interimText => _interimText;

  StreamingVoiceService(this._transcriptionService);

  /// Start streaming recording with real-time transcription
  Future<bool> startRecording({
    double vadEnergyThreshold = 200.0,
    Duration silenceThreshold = const Duration(seconds: 1),
    Duration minChunkDuration = const Duration(milliseconds: 500),
    Duration maxChunkDuration = const Duration(seconds: 30),
  }) async {
    if (_isRecording) {
      debugPrint('[StreamingVoice] Already recording');
      return false;
    }

    try {
      // Request permission
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          final status = await Permission.microphone.status;
          debugPrint('[StreamingVoice] Mic permission status: $status');
          if (!status.isGranted && !status.isLimited) {
            debugPrint('[StreamingVoice] Requesting microphone permission...');
            final requestResult = await Permission.microphone.request();
            debugPrint('[StreamingVoice] Permission request result: $requestResult');
          }
        } catch (e) {
          debugPrint('[StreamingVoice] Permission check failed: $e - proceeding anyway');
        }
      }

      // Initialize noise filter
      _noiseFilter = SimpleNoiseFilter(
        cutoffFreq: 80.0,
        sampleRate: 16000,
      );

      // Initialize SmartChunker
      _chunker = SmartChunker(
        config: SmartChunkerConfig(
          sampleRate: 16000,
          silenceThreshold: silenceThreshold,
          minChunkDuration: minChunkDuration,
          maxChunkDuration: maxChunkDuration,
          vadEnergyThreshold: vadEnergyThreshold,
          onChunkReady: _handleChunk,
        ),
      );

      // Set up temp file path
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _audioFilePath = '${tempDir.path}/streaming_voice_$timestamp.wav';

      // Initialize streaming WAV file
      await _initializeStreamingWavFile(_audioFilePath!);

      // Enable wakelock
      try {
        await WakelockPlus.enable();
      } catch (e) {
        debugPrint('[StreamingVoice] Failed to enable wakelock: $e');
      }

      // Start recording with stream
      debugPrint('[StreamingVoice] Starting audio stream...');
      Stream<Uint8List> stream;
      try {
        stream = await _recorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
            echoCancel: false,
            autoGain: true,
            noiseSuppress: false,
          ),
        );
        debugPrint('[StreamingVoice] Audio stream started successfully');
      } catch (e) {
        debugPrint('[StreamingVoice] Failed to start audio stream: $e');
        return false;
      }

      _isRecording = true;
      _recordingStartTime = DateTime.now();
      _audioChunkCount = 0;

      // Reset streaming state
      _rollingAudioBuffer = [];
      _interimText = '';
      _confirmedSegments.clear();
      _segmentToConfirmedIndex.clear();
      _nextSegmentIndex = 1;
      _processingQueue.clear();
      _totalSamplesWritten = 0;

      // Set initial model status
      final isModelReady = await _transcriptionService.isReady();
      _modelStatus = isModelReady
          ? TranscriptionModelStatus.ready
          : TranscriptionModelStatus.initializing;
      debugPrint('[StreamingVoice] Initial model status: $_modelStatus');

      // Start re-transcription loop
      _startReTranscriptionLoop();

      // Start recording duration timer
      _startRecordingDurationTimer();

      // Emit initial state
      _emitStreamingState();

      // Process audio stream
      _audioStreamSubscription = stream.listen(
        _processAudioChunk,
        onError: (error, stackTrace) {
          debugPrint('[StreamingVoice] STREAM ERROR: $error');
        },
        onDone: () {
          debugPrint('[StreamingVoice] Stream completed');
        },
        cancelOnError: false,
      );

      debugPrint('[StreamingVoice] Recording started with VAD');
      return true;
    } catch (e) {
      debugPrint('[StreamingVoice] Failed to start: $e');
      return false;
    }
  }

  /// Process incoming audio chunk from stream
  void _processAudioChunk(Uint8List audioBytes) {
    _audioChunkCount++;

    if (_audioChunkCount == 1) {
      debugPrint('[StreamingVoice] First audio chunk received! (${audioBytes.length} bytes)');
    }

    if (!_isRecording || _chunker == null || _noiseFilter == null) {
      return;
    }

    // Convert bytes to int16 samples
    final rawSamples = _bytesToInt16(audioBytes);
    if (rawSamples.isEmpty) return;

    // Apply noise filter
    final cleanSamples = _noiseFilter!.process(rawSamples);

    // Add to rolling buffer for streaming re-transcription
    _rollingAudioBuffer.addAll(cleanSamples);
    if (_rollingAudioBuffer.length > _rollingBufferMaxSamples) {
      _rollingAudioBuffer = _rollingAudioBuffer.sublist(
        _rollingAudioBuffer.length - _rollingBufferMaxSamples,
      );
    }

    // Stream audio to disk
    _streamAudioToDisk(cleanSamples);

    // Process through SmartChunker (VAD + auto-chunking)
    _chunker!.processSamples(cleanSamples);
  }

  /// Initialize WAV file for streaming audio data
  Future<void> _initializeStreamingWavFile(String path) async {
    final file = File(path);
    _audioFileSink = file.openWrite();

    // Write WAV header with placeholder size
    _audioFileSink!.add([0x52, 0x49, 0x46, 0x46]); // "RIFF"
    _audioFileSink!.add([0x00, 0x00, 0x00, 0x00]); // Placeholder file size
    _audioFileSink!.add([0x57, 0x41, 0x56, 0x45]); // "WAVE"

    // fmt chunk
    _audioFileSink!.add([0x66, 0x6D, 0x74, 0x20]); // "fmt "
    _audioFileSink!.add([0x10, 0x00, 0x00, 0x00]); // Chunk size (16)
    _audioFileSink!.add([0x01, 0x00]); // Audio format (1 = PCM)
    _audioFileSink!.add([0x01, 0x00]); // Num channels (1 = mono)
    _audioFileSink!.add([0x80, 0x3E, 0x00, 0x00]); // Sample rate (16000)
    _audioFileSink!.add([0x00, 0x7D, 0x00, 0x00]); // Byte rate (32000)
    _audioFileSink!.add([0x02, 0x00]); // Block align (2)
    _audioFileSink!.add([0x10, 0x00]); // Bits per sample (16)

    // data chunk header
    _audioFileSink!.add([0x64, 0x61, 0x74, 0x61]); // "data"
    _audioFileSink!.add([0x00, 0x00, 0x00, 0x00]); // Placeholder data size

    await _audioFileSink!.flush();
    _totalSamplesWritten = 0;
  }

  /// Stream audio samples to disk
  void _streamAudioToDisk(List<int> samples) {
    if (_audioFileSink == null) return;

    final bytes = Uint8List(samples.length * 2);
    for (int i = 0; i < samples.length; i++) {
      final sample = samples[i];
      bytes[i * 2] = sample & 0xFF;
      bytes[i * 2 + 1] = (sample >> 8) & 0xFF;
    }
    _audioFileSink!.add(bytes);
    _totalSamplesWritten += samples.length;
  }

  /// Finalize WAV file by updating header
  Future<void> _finalizeStreamingWavFile() async {
    if (_audioFileSink == null || _audioFilePath == null) return;

    await _audioFileSink!.flush();
    await _audioFileSink!.close();
    _audioFileSink = null;

    final file = File(_audioFilePath!);
    final raf = await file.open(mode: FileMode.writeOnlyAppend);

    final dataSize = _totalSamplesWritten * 2;
    final fileSize = dataSize + 36;

    // Update RIFF chunk size at offset 4
    await raf.setPosition(4);
    await raf.writeFrom([
      fileSize & 0xFF,
      (fileSize >> 8) & 0xFF,
      (fileSize >> 16) & 0xFF,
      (fileSize >> 24) & 0xFF,
    ]);

    // Update data chunk size at offset 40
    await raf.setPosition(40);
    await raf.writeFrom([
      dataSize & 0xFF,
      (dataSize >> 8) & 0xFF,
      (dataSize >> 16) & 0xFF,
      (dataSize >> 24) & 0xFF,
    ]);

    await raf.close();
    debugPrint('[StreamingVoice] Finalized WAV: ${dataSize ~/ 1024}KB');
  }

  /// Start the re-transcription loop for streaming feedback
  void _startReTranscriptionLoop() {
    _reTranscriptionTimer?.cancel();

    _reTranscriptionTimer = Timer.periodic(_reTranscriptionInterval, (_) async {
      if (!_isRecording) return;
      if (_chunker == null) return;

      // Check if model became ready
      if (_modelStatus == TranscriptionModelStatus.initializing) {
        final isReady = await _transcriptionService.isReady();
        if (isReady) {
          debugPrint('[StreamingVoice] Model became ready during recording!');
          _updateModelStatus(TranscriptionModelStatus.ready);
        }
      }

      final isSpeaking = _chunker!.stats.vadStats.isSpeaking;
      final hasSpeech = _chunker!.stats.vadStats.speechDuration > const Duration(milliseconds: 500);
      final bufferSeconds = _rollingAudioBuffer.length / 16000;

      if (isSpeaking || hasSpeech || bufferSeconds >= 3.0) {
        _transcribeRollingBuffer();
      }
    });
  }

  /// Stop re-transcription loop
  void _stopReTranscriptionLoop() {
    _reTranscriptionTimer?.cancel();
    _reTranscriptionTimer = null;
  }

  /// Start recording duration timer
  void _startRecordingDurationTimer() {
    _recordingDurationTimer?.cancel();

    _recordingDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isRecording) return;
      _emitStreamingState();
    });
  }

  /// Stop recording duration timer
  void _stopRecordingDurationTimer() {
    _recordingDurationTimer?.cancel();
    _recordingDurationTimer = null;
  }

  /// Transcribe the rolling buffer for interim text display
  Future<void> _transcribeRollingBuffer() async {
    if (_isReTranscribing) return;
    if (_rollingAudioBuffer.isEmpty) return;
    if (_rollingAudioBuffer.length < 16000) return;

    _isReTranscribing = true;

    try {
      final isReady = await _transcriptionService.isReady();
      if (!isReady) {
        if (_modelStatus != TranscriptionModelStatus.initializing) {
          _updateModelStatus(TranscriptionModelStatus.initializing);
        }
      }

      // Take last 15 seconds
      final samplesToTranscribe = _rollingAudioBuffer.length > _reTranscriptionWindowSamples
          ? _rollingAudioBuffer.sublist(_rollingAudioBuffer.length - _reTranscriptionWindowSamples)
          : List<int>.from(_rollingAudioBuffer);

      // Save to temp file
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/interim_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _saveSamplesToWav(samplesToTranscribe, tempPath);

      // Transcribe
      final result = await _transcriptionService.transcribeAudio(tempPath);

      // If we just finished initializing, update status
      if (_modelStatus != TranscriptionModelStatus.ready) {
        _updateModelStatus(TranscriptionModelStatus.ready);
      }

      // Clean up temp file
      try {
        await File(tempPath).delete();
      } catch (_) {}

      // Update interim text
      String newInterimText = result.text.trim();

      // Remove text already in confirmed segments
      if (newInterimText.isNotEmpty && _confirmedSegments.isNotEmpty) {
        final lastConfirmed = _confirmedSegments.last.trim().toLowerCase();
        final interimLower = newInterimText.toLowerCase();

        if (interimLower.startsWith(lastConfirmed)) {
          newInterimText = newInterimText.substring(lastConfirmed.length).trim();
        } else {
          // Check for partial overlap
          for (int i = min(lastConfirmed.length, 50); i >= 10; i--) {
            final suffix = lastConfirmed.substring(lastConfirmed.length - i);
            if (interimLower.startsWith(suffix)) {
              newInterimText = newInterimText.substring(i).trim();
              break;
            }
          }
        }
      }

      if (newInterimText.isNotEmpty && newInterimText != _interimText) {
        _interimText = newInterimText;

        if (!_interimTextController.isClosed) {
          _interimTextController.add(_interimText);
        }

        _emitStreamingState();
      } else if (newInterimText.isEmpty && _interimText.isNotEmpty) {
        _interimText = '';
        if (!_interimTextController.isClosed) {
          _interimTextController.add('');
        }
        _emitStreamingState();
      }
    } catch (e) {
      debugPrint('[StreamingVoice] Re-transcription failed: $e');
    } finally {
      _isReTranscribing = false;
    }
  }

  /// Final transcription on stop - optimized to capture final words
  /// Unlike _transcribeRollingBuffer which strips overlap, this preserves everything
  Future<void> _doFinalTranscription() async {
    if (_rollingAudioBuffer.isEmpty) return;
    if (_rollingAudioBuffer.length < 16000) return;

    try {
      debugPrint('[StreamingVoice] Final transcription with ${_rollingAudioBuffer.length} samples');

      // Take the entire rolling buffer (already includes silence padding)
      final samplesToTranscribe = List<int>.from(_rollingAudioBuffer);

      // Save to temp file
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/final_flush_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _saveSamplesToWav(samplesToTranscribe, tempPath);

      // Transcribe
      final result = await _transcriptionService.transcribeAudio(tempPath);

      // Clean up temp file
      try {
        await File(tempPath).delete();
      } catch (_) {}

      final fullTranscript = result.text.trim();
      debugPrint('[StreamingVoice] Final flush transcript: "$fullTranscript"');

      if (fullTranscript.isEmpty) {
        // Nothing new, just move interim to confirmed if present
        if (_interimText.isNotEmpty) {
          _confirmedSegments.add(_interimText);
          _interimText = '';
          debugPrint('[StreamingVoice] Moved interim text to confirmed');
        }
        return;
      }

      // Build what we already have confirmed
      final confirmedSoFar = _confirmedSegments.join(' ').trim();

      // If the full transcript contains more than what we've confirmed,
      // extract the new portion
      if (confirmedSoFar.isEmpty) {
        // Nothing confirmed yet - use entire transcript
        _confirmedSegments.clear();
        _confirmedSegments.add(fullTranscript);
        _interimText = '';
        debugPrint('[StreamingVoice] Final: used full transcript (nothing confirmed before)');
      } else {
        // Find where our confirmed text ends in the full transcript
        final confirmedLower = confirmedSoFar.toLowerCase();
        final fullLower = fullTranscript.toLowerCase();

        String newText = '';

        // Try to find the confirmed text within the full transcript
        final confirmedIndex = fullLower.indexOf(confirmedLower);
        if (confirmedIndex != -1) {
          // Extract everything after the confirmed portion
          final afterConfirmed = confirmedIndex + confirmedLower.length;
          if (afterConfirmed < fullTranscript.length) {
            newText = fullTranscript.substring(afterConfirmed).trim();
          }
        } else {
          // Try suffix matching - find longest suffix of confirmed that matches prefix of full
          for (int i = min(confirmedLower.length, 50); i >= 5; i--) {
            final suffix = confirmedLower.substring(confirmedLower.length - i);
            if (fullLower.startsWith(suffix)) {
              newText = fullTranscript.substring(i).trim();
              break;
            }
          }

          // If no match found, check if we're missing ending words
          if (newText.isEmpty && _interimText.isNotEmpty) {
            newText = _interimText;
          } else if (newText.isEmpty) {
            // Last resort: if full transcript is longer, take the difference
            // This handles cases where Parakeet produces slightly different text
            final fullWords = fullTranscript.split(RegExp(r'\s+'));
            final confirmedWords = confirmedSoFar.split(RegExp(r'\s+'));
            if (fullWords.length > confirmedWords.length) {
              newText = fullWords.sublist(confirmedWords.length).join(' ');
            }
          }
        }

        if (newText.isNotEmpty) {
          _confirmedSegments.add(newText);
          debugPrint('[StreamingVoice] Final: added new text "$newText"');
        } else if (_interimText.isNotEmpty) {
          _confirmedSegments.add(_interimText);
          debugPrint('[StreamingVoice] Final: moved interim "$_interimText" to confirmed');
        }
        _interimText = '';
      }

      _emitStreamingState();
    } catch (e) {
      debugPrint('[StreamingVoice] Final transcription failed: $e');
      // Still preserve any interim text
      if (_interimText.isNotEmpty) {
        _confirmedSegments.add(_interimText);
        _interimText = '';
      }
    }
  }

  /// Emit current streaming state to UI
  void _emitStreamingState() {
    if (_streamingStateController.isClosed) return;

    final state = StreamingTranscriptionState(
      confirmedSegments: List.unmodifiable(_confirmedSegments),
      interimText: _interimText.isNotEmpty ? _interimText : null,
      isRecording: _isRecording,
      isProcessing: _isProcessingQueue,
      recordingDuration: _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!)
          : Duration.zero,
      vadLevel: _chunker?.stats.vadStats.isSpeaking == true ? 1.0 : 0.0,
      modelStatus: _modelStatus,
    );

    _streamingStateController.add(state);
  }

  /// Update model status and emit state
  void _updateModelStatus(TranscriptionModelStatus status) {
    _modelStatus = status;
    _emitStreamingState();
  }

  /// Handle chunk ready from SmartChunker
  void _handleChunk(List<int> samples) {
    debugPrint('[StreamingVoice] Auto-chunk detected! (${samples.length} samples)');

    // Move current interim text to confirmed
    final confirmedIdx = _confirmedSegments.length;
    if (_interimText.isNotEmpty) {
      _confirmedSegments.add(_interimText);
      _interimText = '';

      if (!_interimTextController.isClosed) {
        _interimTextController.add('');
      }

      _emitStreamingState();
    } else {
      _confirmedSegments.add('');
    }

    // Keep 5 second overlap in rolling buffer
    const overlapSamples = 16000 * 5;
    if (_rollingAudioBuffer.length > overlapSamples) {
      _rollingAudioBuffer = _rollingAudioBuffer.sublist(
        _rollingAudioBuffer.length - overlapSamples,
      );
    } else {
      _rollingAudioBuffer.clear();
    }

    // Queue for official transcription
    final segmentIndex = _nextSegmentIndex++;
    _segmentToConfirmedIndex[segmentIndex] = confirmedIdx;
    _queueSegmentForProcessing(samples, segmentIndex);
  }

  /// Queue a segment for transcription
  void _queueSegmentForProcessing(List<int> samples, int segmentIndex) {
    _processingQueue.add(_QueuedSegment(
      index: segmentIndex,
      samples: samples,
    ));

    if (!_isProcessingQueue) {
      _processQueue();
    }
  }

  /// Process queued segments
  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    while (_processingQueue.isNotEmpty) {
      final segment = _processingQueue.removeAt(0);
      await _transcribeSegment(segment);
    }

    _isProcessingQueue = false;
  }

  /// Transcribe a single segment
  Future<void> _transcribeSegment(_QueuedSegment segment) async {
    try {
      // Save segment to temp file
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/segment_${segment.index}.wav';

      await _saveSamplesToWav(segment.samples, tempPath);

      // Transcribe
      final result = await _transcriptionService.transcribeAudio(tempPath);

      // Clean up
      try {
        await File(tempPath).delete();
      } catch (_) {}

      if (result.text.trim().isEmpty) return;

      final transcribedText = result.text.trim();

      // Update confirmed segment
      final confirmedIdx = _segmentToConfirmedIndex[segment.index];
      if (confirmedIdx != null && confirmedIdx < _confirmedSegments.length) {
        _confirmedSegments[confirmedIdx] = transcribedText;
      } else {
        _confirmedSegments.add(transcribedText);
      }

      _emitStreamingState();
      debugPrint('[StreamingVoice] Segment ${segment.index} done: "$transcribedText"');
    } catch (e) {
      debugPrint('[StreamingVoice] Failed to transcribe segment: $e');
    }
  }

  /// Save samples to WAV file
  Future<void> _saveSamplesToWav(List<int> samples, String filePath) async {
    const sampleRate = 16000;
    const numChannels = 1;
    const bitsPerSample = 16;

    final dataSize = samples.length * 2;
    final fileSize = 36 + dataSize;

    final bytes = BytesBuilder();

    // RIFF header
    bytes.add('RIFF'.codeUnits);
    bytes.add(_int32ToBytes(fileSize));
    bytes.add('WAVE'.codeUnits);

    // fmt chunk
    bytes.add('fmt '.codeUnits);
    bytes.add(_int32ToBytes(16));
    bytes.add(_int16ToBytes(1));
    bytes.add(_int16ToBytes(numChannels));
    bytes.add(_int32ToBytes(sampleRate));
    bytes.add(_int32ToBytes(sampleRate * numChannels * bitsPerSample ~/ 8));
    bytes.add(_int16ToBytes(numChannels * bitsPerSample ~/ 8));
    bytes.add(_int16ToBytes(bitsPerSample));

    // data chunk
    bytes.add('data'.codeUnits);
    bytes.add(_int32ToBytes(dataSize));

    for (final sample in samples) {
      bytes.add(_int16ToBytes(sample));
    }

    final file = File(filePath);
    await file.writeAsBytes(bytes.toBytes());
  }

  Uint8List _int32ToBytes(int value) {
    return Uint8List(4)
      ..[0] = value & 0xFF
      ..[1] = (value >> 8) & 0xFF
      ..[2] = (value >> 16) & 0xFF
      ..[3] = (value >> 24) & 0xFF;
  }

  Uint8List _int16ToBytes(int value) {
    final clamped = value.clamp(-32768, 32767);
    final unsigned = clamped < 0 ? clamped + 65536 : clamped;
    return Uint8List(2)
      ..[0] = unsigned & 0xFF
      ..[1] = (unsigned >> 8) & 0xFF;
  }

  List<int> _bytesToInt16(Uint8List bytes) {
    final samples = <int>[];
    for (var i = 0; i < bytes.length; i += 2) {
      if (i + 1 < bytes.length) {
        final sample = bytes[i] | (bytes[i + 1] << 8);
        final signed = sample > 32767 ? sample - 65536 : sample;
        samples.add(signed);
      }
    }
    return samples;
  }

  /// Stop recording and return audio file path
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      debugPrint('[StreamingVoice] Stopping recording...');

      _stopReTranscriptionLoop();
      _stopRecordingDurationTimer();

      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      await _recorder.stop();
      _isRecording = false;

      // Wait for stream to settle
      await Future.delayed(const Duration(milliseconds: 300));

      // === PARAKEET FINAL FLUSH ===
      // Parakeet's internal buffers need silence to flush the final word(s)
      // Without this, the last 1-2 words are often lost
      debugPrint('[StreamingVoice] Flushing Parakeet with silence...');
      final silenceBuffer = List<int>.filled(16000 * 2, 0); // 2 seconds of silence
      _rollingAudioBuffer.addAll(silenceBuffer);

      // Do one final re-transcription with the silence-padded buffer
      // This captures any final words that Parakeet was holding
      if (_rollingAudioBuffer.length > 16000) {
        await _doFinalTranscription();
      }

      // Flush chunker
      if (_chunker != null) {
        _chunker!.flush();
        await Future.delayed(const Duration(milliseconds: 50));
        _chunker = null;
      }

      if (_noiseFilter != null) {
        _noiseFilter!.reset();
        _noiseFilter = null;
      }

      _emitStreamingState();
      _recordingStartTime = null;

      // Finalize WAV file
      await _finalizeStreamingWavFile();

      // Disable wakelock
      try {
        await WakelockPlus.disable();
      } catch (_) {}

      // Clear buffers
      _rollingAudioBuffer.clear();

      debugPrint('[StreamingVoice] Recording stopped: $_audioFilePath');
      return _audioFilePath;
    } catch (e) {
      debugPrint('[StreamingVoice] Failed to stop: $e');
      return null;
    }
  }

  /// Cancel recording without saving
  Future<void> cancelRecording() async {
    if (!_isRecording) return;

    try {
      _stopReTranscriptionLoop();
      _stopRecordingDurationTimer();

      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      await _recorder.stop();
      _isRecording = false;
      _recordingStartTime = null;

      _chunker = null;

      // Close and delete file
      if (_audioFileSink != null) {
        await _audioFileSink!.close();
        _audioFileSink = null;
      }
      if (_audioFilePath != null) {
        final file = File(_audioFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      // Clear state
      _rollingAudioBuffer.clear();
      _interimText = '';
      _confirmedSegments.clear();
      _processingQueue.clear();

      _emitStreamingState();

      try {
        await WakelockPlus.disable();
      } catch (_) {}

      debugPrint('[StreamingVoice] Recording cancelled');
    } catch (e) {
      debugPrint('[StreamingVoice] Failed to cancel: $e');
    }
  }

  /// Get complete transcript from streaming (confirmed segments)
  String getStreamingTranscript() {
    return _confirmedSegments.join('\n');
  }

  /// Dispose
  void dispose() {
    _stopReTranscriptionLoop();
    _stopRecordingDurationTimer();
    _audioStreamSubscription?.cancel();
    _recorder.dispose();
    _streamingStateController.close();
    _interimTextController.close();
  }
}

/// Internal: Queued segment for processing
class _QueuedSegment {
  final int index;
  final List<int> samples;

  _QueuedSegment({required this.index, required this.samples});
}
