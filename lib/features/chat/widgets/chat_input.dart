import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/providers/voice_input_providers.dart';
import 'package:parachute_chat/core/services/voice_input_service.dart';
import '../models/attachment.dart';

/// Text input field for chat messages with voice input and attachment support
class ChatInput extends ConsumerStatefulWidget {
  final Function(String, List<ChatAttachment>) onSend;
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

  // Pending attachments
  final List<ChatAttachment> _attachments = [];
  bool _isLoadingAttachment = false;

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
    // Can send if there's text OR attachments
    if ((text.isEmpty && _attachments.isEmpty) || !widget.enabled) return;

    widget.onSend(text, List.from(_attachments));
    _controller.clear();
    setState(() {
      _attachments.clear();
    });
    _focusNode.requestFocus();
  }

  Future<void> _handleAttachment() async {
    if (_isLoadingAttachment) return;

    setState(() {
      _isLoadingAttachment = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          // Images
          'jpg', 'jpeg', 'png', 'gif', 'webp',
          // Documents
          'pdf', 'txt', 'md',
          // Code files
          'dart', 'py', 'js', 'ts', 'java', 'kt', 'swift', 'go', 'rs',
          'c', 'cpp', 'h', 'hpp', 'json', 'yaml', 'yml', 'xml', 'html',
          'css', 'sql', 'sh',
        ],
        allowMultiple: true,
        withData: true, // Get bytes directly on mobile
      );

      if (result != null) {
        for (final file in result.files) {
          ChatAttachment? attachment;

          if (file.bytes != null) {
            // Mobile: use bytes directly
            attachment = ChatAttachment.fromBytes(
              bytes: file.bytes!,
              fileName: file.name,
              mimeType: getMimeType(file.name),
            );
          } else if (file.path != null) {
            // Desktop: read from file path
            attachment = await ChatAttachment.fromFile(File(file.path!));
          }

          if (attachment != null) {
            setState(() {
              _attachments.add(attachment!);
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to attach file: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAttachment = false;
        });
      }
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
    });
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
            // Attachment previews (shown when files are attached)
            if (_attachments.isNotEmpty)
              _buildAttachmentPreviews(isDark),

            // Recording indicator (shown when recording)
            if (isRecording)
              _buildRecordingIndicator(isDark, duration),

            // Transcribing indicator
            if (isTranscribing)
              _buildTranscribingIndicator(isDark),

            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Attachment button (left side)
                _buildAttachmentButton(isDark, isRecording, isTranscribing),

                const SizedBox(width: Spacing.xs),

                // Microphone button
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
                          onPressed: ((_hasText || _attachments.isNotEmpty) && widget.enabled && !isRecording && !isTranscribing)
                              ? _handleSend
                              : null,
                          style: IconButton.styleFrom(
                            backgroundColor: ((_hasText || _attachments.isNotEmpty) && widget.enabled && !isRecording && !isTranscribing)
                                ? (isDark ? BrandColors.nightForest : BrandColors.forest)
                                : (isDark
                                    ? BrandColors.nightSurfaceElevated
                                    : BrandColors.stone),
                            foregroundColor: ((_hasText || _attachments.isNotEmpty) && widget.enabled && !isRecording && !isTranscribing)
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

  Widget _buildAttachmentButton(bool isDark, bool isRecording, bool isTranscribing) {
    if (_isLoadingAttachment) {
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

    return IconButton(
      onPressed: (widget.enabled && !isRecording && !isTranscribing)
          ? _handleAttachment
          : null,
      style: IconButton.styleFrom(
        backgroundColor: _attachments.isNotEmpty
            ? (isDark ? BrandColors.nightTurquoise : BrandColors.turquoise)
            : (isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone),
        foregroundColor: _attachments.isNotEmpty
            ? Colors.white
            : (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood),
        shape: RoundedRectangleBorder(
          borderRadius: Radii.button,
        ),
      ),
      icon: Badge(
        isLabelVisible: _attachments.isNotEmpty,
        label: Text('${_attachments.length}'),
        child: const Icon(Icons.attach_file_rounded, size: 20),
      ),
      tooltip: 'Attach files',
    );
  }

  Widget _buildAttachmentPreviews(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _attachments.asMap().entries.map((entry) {
            final index = entry.key;
            final attachment = entry.value;
            return _buildAttachmentChip(isDark, attachment, index);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildAttachmentChip(bool isDark, ChatAttachment attachment, int index) {
    final isImage = attachment.type == AttachmentType.image;

    return Container(
      margin: const EdgeInsets.only(right: Spacing.sm),
      child: Material(
        color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.cream,
        borderRadius: Radii.badge,
        child: InkWell(
          borderRadius: Radii.badge,
          onTap: () {
            // Could show preview dialog in the future
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm,
              vertical: Spacing.xs,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone,
              ),
              borderRadius: Radii.badge,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Thumbnail or icon
                if (isImage && attachment.base64Data != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(
                      attachment.bytes!,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildFileIcon(attachment, isDark),
                    ),
                  )
                else
                  _buildFileIcon(attachment, isDark),

                const SizedBox(width: Spacing.xs),

                // File name and size
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        attachment.fileName,
                        style: TextStyle(
                          fontSize: TypographyTokens.labelSmall,
                          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        attachment.formattedSize,
                        style: TextStyle(
                          fontSize: TypographyTokens.labelSmall - 2,
                          color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: Spacing.xs),

                // Remove button
                InkWell(
                  onTap: () => _removeAttachment(index),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileIcon(ChatAttachment attachment, bool isDark) {
    IconData icon;
    Color color;

    switch (attachment.type) {
      case AttachmentType.image:
        icon = Icons.image_rounded;
        color = BrandColors.turquoise;
        break;
      case AttachmentType.pdf:
        icon = Icons.picture_as_pdf_rounded;
        color = BrandColors.error;
        break;
      case AttachmentType.text:
        icon = Icons.article_rounded;
        color = BrandColors.forest;
        break;
      case AttachmentType.code:
        icon = Icons.code_rounded;
        color = BrandColors.warning;
        break;
      case AttachmentType.unknown:
        icon = Icons.insert_drive_file_rounded;
        color = isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood;
        break;
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}
