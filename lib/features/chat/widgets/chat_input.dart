import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/providers/voice_input_providers.dart';
import 'package:parachute_chat/core/services/voice_input_service.dart';

/// Text input field for chat messages with voice input support
class ChatInput extends ConsumerStatefulWidget {
  final Function(String) onSend;
  final VoidCallback? onStop;
  final bool enabled;
  final bool isStreaming;
  final String? initialText;
  final String hintText;

  const ChatInput({
    super.key,
    required this.onSend,
    this.onStop,
    this.enabled = true,
    this.isStreaming = false,
    this.initialText,
    this.hintText = 'Message your vault...',
  });

  @override
  ConsumerState<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends ConsumerState<ChatInput>
    with SingleTickerProviderStateMixin {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;

  // Animation for recording pulse
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_onTextChanged);

    // Pulse animation for recording state
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;

    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  Future<void> _handleVoiceInput() async {
    final voiceService = ref.read(voiceInputServiceProvider);

    if (voiceService.isRecording) {
      // Stop and transcribe
      _pulseController.stop();
      final text = await voiceService.stopAndTranscribe();
      if (text != null && text.isNotEmpty) {
        // Append to existing text (with space if needed)
        final currentText = _controller.text;
        if (currentText.isNotEmpty && !currentText.endsWith(' ')) {
          _controller.text = '$currentText $text';
        } else {
          _controller.text = currentText + text;
        }
        // Move cursor to end
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      }
    } else {
      // Start recording
      await voiceService.initialize();
      final started = await voiceService.startRecording();
      if (started) {
        _pulseController.repeat(reverse: true);
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Watch voice input state
    final voiceState = ref.watch(voiceInputCurrentStateProvider);
    final isRecording = voiceState == VoiceInputState.recording;
    final isTranscribing = voiceState == VoiceInputState.transcribing;

    // Watch recording duration
    final durationAsync = ref.watch(voiceInputDurationProvider);
    final duration = durationAsync.valueOrNull ?? Duration.zero;

    // Listen for errors
    ref.listen(voiceInputErrorProvider, (previous, next) {
      next.whenData((error) {
        if (error.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: BrandColors.error,
            ),
          );
        }
      });
    });

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
        border: Border(
          top: BorderSide(
            color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Recording indicator (shown when recording)
            if (isRecording)
              _buildRecordingIndicator(isDark, duration),

            // Transcribing indicator
            if (isTranscribing)
              _buildTranscribingIndicator(isDark),

            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Microphone button (left side)
                _buildVoiceButton(isDark, isRecording, isTranscribing),

                const SizedBox(width: Spacing.sm),

                // Text field
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 150),
                    decoration: BoxDecoration(
                      color: isDark
                          ? BrandColors.nightSurfaceElevated
                          : BrandColors.cream,
                      borderRadius: Radii.button,
                      border: Border.all(
                        color: _focusNode.hasFocus
                            ? (isDark ? BrandColors.nightForest : BrandColors.forest)
                            : (isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone),
                        width: _focusNode.hasFocus ? 1.5 : 1,
                      ),
                    ),
                    child: KeyboardListener(
                      focusNode: FocusNode(),
                      onKeyEvent: (event) {
                        // Send on Enter (without Shift)
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter &&
                            !HardwareKeyboard.instance.isShiftPressed) {
                          _handleSend();
                        }
                      },
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        enabled: widget.enabled && !isRecording && !isTranscribing,
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                        style: TextStyle(
                          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                          fontSize: TypographyTokens.bodyMedium,
                        ),
                        decoration: InputDecoration(
                          hintText: isRecording
                              ? 'Recording...'
                              : isTranscribing
                                  ? 'Transcribing...'
                                  : widget.hintText,
                          hintStyle: TextStyle(
                            color: isDark
                                ? BrandColors.nightTextSecondary
                                : BrandColors.driftwood,
                            fontSize: TypographyTokens.bodyMedium,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: Spacing.md,
                            vertical: Spacing.sm,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: Spacing.sm),

                // Send or Stop button
                AnimatedContainer(
                  duration: Motion.quick,
                  curve: Motion.settling,
                  child: widget.isStreaming
                      ? IconButton(
                          onPressed: widget.onStop,
                          style: IconButton.styleFrom(
                            backgroundColor: isDark
                                ? BrandColors.nightForest
                                : BrandColors.forest,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: Radii.button,
                            ),
                          ),
                          icon: const Icon(Icons.stop_rounded, size: 20),
                          tooltip: 'Stop generating',
                        )
                      : IconButton(
                          onPressed: (_hasText && widget.enabled && !isRecording && !isTranscribing)
                              ? _handleSend
                              : null,
                          style: IconButton.styleFrom(
                            backgroundColor: (_hasText && widget.enabled && !isRecording && !isTranscribing)
                                ? (isDark ? BrandColors.nightForest : BrandColors.forest)
                                : (isDark
                                    ? BrandColors.nightSurfaceElevated
                                    : BrandColors.stone),
                            foregroundColor: (_hasText && widget.enabled && !isRecording && !isTranscribing)
                                ? Colors.white
                                : (isDark
                                    ? BrandColors.nightTextSecondary
                                    : BrandColors.driftwood),
                            shape: RoundedRectangleBorder(
                              borderRadius: Radii.button,
                            ),
                          ),
                          icon: const Icon(Icons.send_rounded, size: 20),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceButton(bool isDark, bool isRecording, bool isTranscribing) {
    // Show loading spinner when transcribing
    if (isTranscribing) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone,
          borderRadius: Radii.button,
        ),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
            ),
          ),
        ),
      );
    }

    // Pulsing mic button when recording
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = isRecording ? 1.0 + (_pulseController.value * 0.1) : 1.0;
        return Transform.scale(
          scale: scale,
          child: IconButton(
            onPressed: widget.enabled ? _handleVoiceInput : null,
            style: IconButton.styleFrom(
              backgroundColor: isRecording
                  ? BrandColors.error
                  : (isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone),
              foregroundColor: isRecording
                  ? Colors.white
                  : (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood),
              shape: RoundedRectangleBorder(
                borderRadius: Radii.button,
              ),
            ),
            icon: Icon(
              isRecording ? Icons.stop_rounded : Icons.mic_rounded,
              size: 20,
            ),
            tooltip: isRecording ? 'Stop recording' : 'Voice input',
          ),
        );
      },
    );
  }

  Widget _buildRecordingIndicator(bool isDark, Duration duration) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Pulsing red dot
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final opacity = 0.5 + (_pulseController.value * 0.5);
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: BrandColors.error.withValues(alpha: opacity),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            'Recording ${_formatDuration(duration)}',
            style: TextStyle(
              color: BrandColors.error,
              fontSize: TypographyTokens.labelMedium,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscribingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            'Transcribing...',
            style: TextStyle(
              color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
              fontSize: TypographyTokens.labelMedium,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
