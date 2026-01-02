import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/widgets/error_boundary.dart';
import 'package:parachute_chat/core/services/logger_service.dart';
import '../models/chat_session.dart';
import '../providers/chat_providers.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input.dart';
import '../widgets/session_selector.dart';
import '../widgets/connection_status_banner.dart';
import '../widgets/resume_marker.dart';
import '../widgets/session_resume_banner.dart';
import '../widgets/directory_picker.dart';
import '../../settings/screens/settings_screen.dart';

/// Main chat screen for AI conversations
///
/// Supports:
/// - Streaming responses with real-time text and tool call display
/// - Session switching via bottom sheet
/// - Agent selection
/// - Initial context (e.g., from recording transcript)
/// - Auto-run mode for standalone agents
class ChatScreen extends ConsumerStatefulWidget {
  /// Optional initial message to pre-fill
  final String? initialMessage;

  /// Optional context to include with first message (e.g., recording transcript)
  final String? initialContext;

  /// If true, automatically sends [autoRunMessage] on screen load
  final bool autoRun;

  /// Message to auto-send when [autoRun] is true
  final String? autoRunMessage;

  const ChatScreen({
    super.key,
    this.initialMessage,
    this.initialContext,
    this.autoRun = false,
    this.autoRunMessage,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  String? _pendingInitialContext;
  bool _hasAutoRun = false;
  bool _resumeBannerDismissed = false;

  /// Track if user is scrolled away from bottom (to show scroll-to-bottom FAB)
  bool _showScrollToBottomFab = false;

  @override
  void initState() {
    super.initState();
    _pendingInitialContext = widget.initialContext;

    // Listen to scroll position to show/hide scroll-to-bottom FAB
    _scrollController.addListener(_onScroll);

    // Schedule auto-run after first frame
    if (widget.autoRun && widget.autoRunMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performAutoRun();
      });
    }

    // Scroll to bottom after first frame if messages are loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomInstant();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    // Show FAB if scrolled more than 200 pixels from bottom
    final isNearBottom = position.maxScrollExtent - position.pixels < 200;

    if (_showScrollToBottomFab == isNearBottom) {
      setState(() {
        _showScrollToBottomFab = !isNearBottom;
      });
    }
  }

  void _performAutoRun() {
    if (_hasAutoRun) return;
    _hasAutoRun = true;
    _handleSend(widget.autoRunMessage!);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Motion.standard,
          curve: Motion.settling,
        );
      });
    }
  }

  /// Scroll to bottom instantly (no animation) - for initial load
  void _scrollToBottomInstant() {
    // Use multiple post-frame callbacks to ensure layout is complete
    // This handles cases where ListView hasn't attached yet or content is still rendering
    int attempts = 0;
    const maxAttempts = 5;

    void tryScroll() {
      if (!mounted) return;
      attempts++;

      if (_scrollController.hasClients) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(maxExtent);

        // Schedule another check in case content is still loading
        if (attempts < maxAttempts) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scrollController.hasClients) {
              final newMaxExtent = _scrollController.position.maxScrollExtent;
              // If max extent changed, scroll again
              if (newMaxExtent > maxExtent) {
                _scrollController.jumpTo(newMaxExtent);
              }
            }
          });
        }
      } else if (attempts < maxAttempts) {
        // Retry on next frame if not ready yet
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) tryScroll();
        });
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) tryScroll();
    });
  }

  void _handleSend(String message) {
    // Get selected contexts for first message only
    final chatState = ref.read(chatMessagesProvider);
    List<String>? contexts;

    // Only include contexts on the first message of a new chat
    if (chatState.messages.isEmpty && chatState.sessionId == null) {
      contexts = ref.read(selectedContextsProvider);
      // Reset contexts after using them
      ref.read(selectedContextsProvider.notifier).state = [
        'Chat/contexts/general-context.md'
      ];
    }

    ref.read(chatMessagesProvider.notifier).sendMessage(
          message: message,
          initialContext: _pendingInitialContext,
          contexts: contexts,
        );

    // Clear pending context after first message
    _pendingInitialContext = null;

    _scrollToBottom();
  }

  Future<void> _showDirectoryPicker() async {
    final chatState = ref.read(chatMessagesProvider);
    final currentPath = chatState.workingDirectory;

    final selectedPath = await showDirectoryPicker(
      context,
      initialPath: currentPath,
    );

    // null means canceled, any other value (including empty string) is a selection
    if (selectedPath != null && mounted) {
      ref.read(chatMessagesProvider.notifier).setWorkingDirectory(
            selectedPath.isEmpty ? null : selectedPath,
          );
    }
  }

  void _showSessionRecoveryDialog(SessionUnavailableInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('Session Recovery'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(info.message),
              if (info.hasMarkdownHistory) ...[
                const SizedBox(height: 12),
                Text(
                  '${info.messageCount} messages available from history.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                ref.read(chatMessagesProvider.notifier).dismissSessionUnavailable();
              },
              child: const Text('Cancel'),
            ),
            if (info.hasMarkdownHistory)
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  ref.read(chatMessagesProvider.notifier).recoverSession('inject_context');
                },
                child: const Text('Continue with History'),
              ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                ref.read(chatMessagesProvider.notifier).recoverSession('fresh_start');
              },
              child: const Text('Start Fresh'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chatState = ref.watch(chatMessagesProvider);
    final currentSessionId = ref.watch(currentSessionIdProvider);

    // Auto-scroll when new messages arrive
    ref.listen(chatMessagesProvider, (previous, next) {
      final prevCount = previous?.messages.length ?? 0;
      final nextCount = next.messages.length;

      if (nextCount != prevCount) {
        // If loading a session (0 -> many messages), scroll instantly
        // Otherwise animate for streaming/new messages
        if (prevCount == 0 && nextCount > 1) {
          _scrollToBottomInstant();
        } else {
          _scrollToBottom();
        }
      }

      // Reset resume banner when session changes
      if (previous?.sessionId != next.sessionId) {
        _resumeBannerDismissed = false;
      }

      // Show session recovery dialog when session is unavailable
      if (next.sessionUnavailable != null && previous?.sessionUnavailable == null) {
        _showSessionRecoveryDialog(next.sessionUnavailable!);
      }
    });

    // Wrap in error boundary to catch rendering errors
    return ScreenErrorBoundary(
      onError: (error, stack) {
        logger.createLogger('ChatScreen').error(
          'Chat screen error',
          error: error,
          stackTrace: stack,
        );
      },
      child: Scaffold(
        backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
        floatingActionButton: _showScrollToBottomFab
            ? Padding(
                padding: const EdgeInsets.only(bottom: 80), // Above the input field
                child: FloatingActionButton.small(
                  onPressed: _scrollToBottom,
                  backgroundColor: isDark
                      ? BrandColors.nightSurfaceElevated
                      : BrandColors.softWhite,
                  foregroundColor: isDark
                      ? BrandColors.nightForest
                      : BrandColors.forest,
                  elevation: 4,
                  child: const Icon(Icons.keyboard_arrow_down),
                ),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        appBar: AppBar(
          backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
          surfaceTintColor: Colors.transparent,
          title: _buildTitle(context, isDark, currentSessionId),
          actions: [
            // Working directory indicator/picker
            if (chatState.workingDirectory != null)
              Tooltip(
                message: chatState.workingDirectory!,
                child: TextButton.icon(
                  // Only allow changing before first message
                  onPressed: chatState.messages.isEmpty ? _showDirectoryPicker : null,
                  icon: Icon(
                    Icons.folder_outlined,
                    size: 18,
                    color: isDark ? BrandColors.nightForest : BrandColors.forest,
                  ),
                  label: Text(
                    chatState.workingDirectory!.split('/').last,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? BrandColors.nightForest : BrandColors.forest,
                    ),
                  ),
                ),
              )
            else if (chatState.messages.isEmpty)
              // Only show picker button for new chats without a directory set
              IconButton(
                onPressed: _showDirectoryPicker,
                icon: const Icon(Icons.folder_outlined),
                tooltip: 'Set working directory',
              ),
            const SizedBox(width: Spacing.xs),
          ],
      ),
      body: Column(
        children: [
          // Connection status banner (shows when server unreachable)
          ConnectionStatusBanner(
            onSettings: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),

          // Session resume banner (shows when context was rebuilt)
          if (chatState.sessionResumeInfo != null && !_resumeBannerDismissed)
            SessionResumeBanner(
              resumeInfo: chatState.sessionResumeInfo!,
              onDismiss: () {
                setState(() {
                  _resumeBannerDismissed = true;
                });
              },
            ),

          // Context banner (if initial context provided)
          if (_pendingInitialContext != null)
            _buildContextBanner(context, isDark),

          // Messages list
          Expanded(
            child: chatState.messages.isEmpty
                ? _buildEmptyStateOrContinuation(context, isDark, chatState)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(Spacing.md),
                    itemCount: chatState.messages.length + (chatState.isContinuation ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Show resume marker at the top if this is a continuation
                      if (chatState.isContinuation && index == 0) {
                        return ResumeMarker(
                          key: const ValueKey('resume_marker'),
                          originalSession: chatState.continuedFromSession!,
                          priorMessages: chatState.priorMessages,
                        );
                      }
                      final msgIndex = chatState.isContinuation ? index - 1 : index;
                      return MessageBubble(
                        message: chatState.messages[msgIndex],
                      );
                    },
                  ),
          ),

          // Error banner
          if (chatState.error != null)
            _buildErrorBanner(context, isDark, chatState.error!),

          // Continue button for imported sessions
          if (chatState.isViewingImported)
            _buildContinueButton(context, isDark, chatState),

          // Input field - disabled when viewing imported sessions (use Continue button)
          ChatInput(
            onSend: _handleSend,
            enabled: !chatState.isStreaming && !chatState.isViewingImported,
            initialText: widget.initialMessage,
            hintText: _pendingInitialContext != null
                ? 'Ask about this recording...'
                : chatState.isViewingImported
                    ? 'Click Continue to resume this conversation'
                    : 'Message your vault...',
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildTitle(BuildContext context, bool isDark, String? sessionId) {
    final chatState = ref.watch(chatMessagesProvider);
    final sessionTitle = chatState.sessionTitle;

    // Determine title text
    String titleText;
    if (sessionId == null) {
      titleText = 'Parachute Chat';
    } else if (sessionTitle != null && sessionTitle.isNotEmpty) {
      titleText = sessionTitle;
    } else {
      titleText = 'Parachute Chat';
    }

    return GestureDetector(
      onTap: () => SessionSelector.show(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 20,
            color: isDark ? BrandColors.nightForest : BrandColors.forest,
          ),
          const SizedBox(width: Spacing.sm),
          Flexible(
            child: Text(
              titleText,
              style: TextStyle(
                fontSize: TypographyTokens.titleMedium,
                fontWeight: FontWeight.w600,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            Icons.arrow_drop_down,
            size: 20,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStateOrContinuation(
    BuildContext context,
    bool isDark,
    ChatMessagesState chatState,
  ) {
    // If this is a continuation, show the resume marker with a prompt to continue
    if (chatState.isContinuation) {
      return ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          ResumeMarker(
            originalSession: chatState.continuedFromSession!,
            priorMessages: chatState.priorMessages,
          ),
          const SizedBox(height: Spacing.xl),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.chat_outlined,
                  size: 32,
                  color: isDark ? BrandColors.nightForest : BrandColors.forest,
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  'Continue the conversation',
                  style: TextStyle(
                    fontSize: TypographyTokens.titleMedium,
                    fontWeight: FontWeight.w600,
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  'Send a message to pick up where you left off',
                  style: TextStyle(
                    fontSize: TypographyTokens.bodyMedium,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return _buildEmptyState(context, isDark);
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
              padding: const EdgeInsets.all(Spacing.xl),
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightSurfaceElevated
                    : BrandColors.forestMist.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_outlined,
                size: 48,
                color: isDark ? BrandColors.nightForest : BrandColors.forest,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text(
              'Start a conversation',
              style: TextStyle(
                fontSize: TypographyTokens.headlineSmall,
                fontWeight: FontWeight.w600,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Ask questions about your vault, get help with ideas,\nor explore your thoughts.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TypographyTokens.bodyMedium,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
                height: TypographyTokens.lineHeightRelaxed,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            // Quick suggestion chips
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              alignment: WrapAlignment.center,
              children: [
                _SuggestionChip(
                  label: 'Summarize my recent notes',
                  onTap: () => _handleSend('Summarize my recent notes'),
                ),
                _SuggestionChip(
                  label: 'What did I capture today?',
                  onTap: () => _handleSend('What did I capture today?'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildContextBanner(BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.all(Spacing.md),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightTurquoise.withValues(alpha: 0.1)
            : BrandColors.turquoiseMist,
        borderRadius: Radii.card,
        border: Border.all(
          color: isDark
              ? BrandColors.nightTurquoise.withValues(alpha: 0.3)
              : BrandColors.turquoiseLight,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            size: 20,
            color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoiseDeep,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'Recording context attached',
              style: TextStyle(
                fontSize: TypographyTokens.bodySmall,
                color:
                    isDark ? BrandColors.nightTurquoise : BrandColors.turquoiseDeep,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _pendingInitialContext = null;
              });
            },
            icon: Icon(
              Icons.close,
              size: 18,
              color:
                  isDark ? BrandColors.nightTurquoise : BrandColors.turquoiseDeep,
            ),
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton(
    BuildContext context,
    bool isDark,
    ChatMessagesState chatState,
  ) {
    final session = chatState.viewingSession!;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightForest.withValues(alpha: 0.1)
            : BrandColors.forestMist,
        border: Border(
          top: BorderSide(
            color: isDark
                ? BrandColors.nightForest.withValues(alpha: 0.2)
                : BrandColors.forest.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.history,
            size: 16,
            color: isDark ? BrandColors.nightForest : BrandColors.forest,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'Imported from ${session.source.displayName}',
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: () => _showContinueConfirmation(context, session, isDark),
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Continue'),
            style: FilledButton.styleFrom(
              backgroundColor:
                  isDark ? BrandColors.nightForest : BrandColors.forest,
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, bool isDark, String error) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Spacing.md),
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: BrandColors.errorLight,
        borderRadius: Radii.badge,
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: BrandColors.error,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              error,
              style: TextStyle(
                fontSize: TypographyTokens.bodySmall,
                color: BrandColors.error,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showContinueConfirmation(
    BuildContext context,
    ChatSession session,
    bool isDark,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
        title: Text(
          'Continue conversation?',
          style: TextStyle(
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will start a new conversation with the prior messages as context.',
              style: TextStyle(
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                height: TypographyTokens.lineHeightRelaxed,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Container(
              padding: const EdgeInsets.all(Spacing.sm),
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightSurface
                    : BrandColors.stone.withValues(alpha: 0.3),
                borderRadius: Radii.badge,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'Attachments, images, and some context may not carry over perfectly.',
                      style: TextStyle(
                        fontSize: TypographyTokens.labelSmall,
                        color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? BrandColors.nightForest : BrandColors.forest,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(continueSessionProvider)(session);
    }
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: isDark
          ? BrandColors.nightSurfaceElevated
          : BrandColors.stone.withValues(alpha: 0.5),
      labelStyle: TextStyle(
        fontSize: TypographyTokens.labelMedium,
        color: isDark ? BrandColors.nightText : BrandColors.charcoal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: Radii.badge,
        side: BorderSide(
          color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone,
        ),
      ),
    );
  }
}

