import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_session.dart';
import '../models/chat_message.dart';
import '../models/context_file.dart';
import '../models/stream_event.dart';
import '../models/session_resume_info.dart';
import '../models/vault_entry.dart';
import '../services/chat_service.dart';
import '../services/local_session_reader.dart';
import '../services/chat_import_service.dart';
import '../services/background_stream_manager.dart';
import 'package:parachute_chat/core/providers/feature_flags_provider.dart';
import 'package:parachute_chat/core/services/file_system_service.dart';
import 'package:parachute_chat/core/providers/file_system_provider.dart';
import 'package:parachute_chat/core/services/logger_service.dart';
import 'package:parachute_chat/core/services/performance_service.dart';

// ============================================================
// Service Provider
// ============================================================

// Note: aiServerUrlProvider is imported from feature_flags_provider.dart
// Do NOT redefine it here - that was causing the URL not to update bug!

/// Provider for ChatService
///
/// Creates a new ChatService instance with the configured server URL.
/// The service handles all communication with the parachute-agent backend.
final chatServiceProvider = Provider<ChatService>((ref) {
  // Watch the server URL - this will rebuild ChatService when URL changes
  final urlAsync = ref.watch(aiServerUrlProvider);
  final baseUrl = urlAsync.valueOrNull ?? 'http://localhost:3333';

  final service = ChatService(baseUrl: baseUrl);

  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

/// Provider for the local session reader (reads from vault markdown files)
final localSessionReaderProvider = Provider<LocalSessionReader>((ref) {
  return LocalSessionReader(FileSystemService());
});

/// Provider for the chat import service
///
/// Used to import chat history from ChatGPT, Claude, and other sources.
final chatImportServiceProvider = Provider<ChatImportService>((ref) {
  final fileSystemService = ref.watch(fileSystemServiceProvider);
  return ChatImportService(fileSystemService);
});

// ============================================================
// Session Providers
// ============================================================

/// Provider for fetching all chat sessions
///
/// Tries to fetch from the server first. If server is unavailable,
/// falls back to reading local session files from the vault.
final chatSessionsProvider = FutureProvider<List<ChatSession>>((ref) async {
  final service = ref.watch(chatServiceProvider);
  final localReader = ref.watch(localSessionReaderProvider);

  try {
    // Try server first
    final serverSessions = await service.getSessions();
    debugPrint('[ChatProviders] Loaded ${serverSessions.length} sessions from server');
    return serverSessions;
  } catch (e) {
    debugPrint('[ChatProviders] Server unavailable, falling back to local sessions: $e');

    // Fall back to local sessions
    try {
      final localSessions = await localReader.getLocalSessions();
      debugPrint('[ChatProviders] Loaded ${localSessions.length} local sessions');
      return localSessions;
    } catch (localError) {
      debugPrint('[ChatProviders] Error loading local sessions: $localError');
      return [];
    }
  }
});

/// Provider for the current session ID
///
/// When null, indicates a new chat should be started.
/// When set, the chat screen shows that session's messages.
final currentSessionIdProvider = StateProvider<String?>((ref) => null);

/// Provider for fetching a specific session with messages
final sessionWithMessagesProvider =
    FutureProvider.family<ChatSessionWithMessages?, String>((ref, sessionId) async {
  final service = ref.watch(chatServiceProvider);
  try {
    return await service.getSession(sessionId);
  } catch (e) {
    debugPrint('[ChatProviders] Error fetching session $sessionId: $e');
    return null;
  }
});


// ============================================================
// Chat State Management
// ============================================================

/// State for the chat messages list with streaming support
class ChatMessagesState {
  final List<ChatMessage> messages;
  final bool isStreaming;
  final String? error;
  final String? sessionId;
  final String? sessionTitle;

  /// Working directory for this session (relative to vault)
  /// If set, the agent operates in this directory and loads its CLAUDE.md
  /// Default is 'Chat' for the standard thinking-oriented experience
  final String? workingDirectory;

  /// If this is a continuation, the original session being continued
  final ChatSession? continuedFromSession;

  /// Messages from the original session (for display in resume marker)
  final List<ChatMessage> priorMessages;

  /// The session being viewed (for imported sessions that can be continued)
  final ChatSession? viewingSession;

  /// Information about how the session was resumed
  /// Set when receiving a session or done event from the backend
  final SessionResumeInfo? sessionResumeInfo;

  /// Session unavailability info - set when SDK session cannot be resumed
  /// Contains info for showing recovery dialog to user
  final SessionUnavailableInfo? sessionUnavailable;

  /// Whether the session is currently loading (e.g., during session switch)
  final bool isLoading;

  /// The model being used for this session (e.g., 'claude-opus-4-5-20250514')
  /// Set when receiving model event from backend
  final String? model;

  const ChatMessagesState({
    this.messages = const [],
    this.isStreaming = false,
    this.isLoading = false,
    this.error,
    this.sessionId,
    this.sessionTitle,
    this.workingDirectory,
    this.continuedFromSession,
    this.priorMessages = const [],
    this.viewingSession,
    this.sessionResumeInfo,
    this.sessionUnavailable,
    this.model,
  });

  /// Whether this session is continuing from another
  bool get isContinuation => continuedFromSession != null;

  /// Whether we're viewing an imported session that can be continued
  bool get isViewingImported => viewingSession?.isImported ?? false;

  ChatMessagesState copyWith({
    List<ChatMessage>? messages,
    bool? isStreaming,
    bool? isLoading,
    String? error,
    String? sessionId,
    String? sessionTitle,
    String? workingDirectory,
    ChatSession? continuedFromSession,
    List<ChatMessage>? priorMessages,
    ChatSession? viewingSession,
    SessionResumeInfo? sessionResumeInfo,
    SessionUnavailableInfo? sessionUnavailable,
    String? model,
    bool clearSessionUnavailable = false,
    bool clearWorkingDirectory = false,
  }) {
    return ChatMessagesState(
      messages: messages ?? this.messages,
      isStreaming: isStreaming ?? this.isStreaming,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      sessionId: sessionId ?? this.sessionId,
      sessionTitle: sessionTitle ?? this.sessionTitle,
      workingDirectory: clearWorkingDirectory ? null : (workingDirectory ?? this.workingDirectory),
      continuedFromSession: continuedFromSession ?? this.continuedFromSession,
      priorMessages: priorMessages ?? this.priorMessages,
      viewingSession: viewingSession ?? this.viewingSession,
      model: model ?? this.model,
      sessionResumeInfo: sessionResumeInfo ?? this.sessionResumeInfo,
      sessionUnavailable: clearSessionUnavailable ? null : (sessionUnavailable ?? this.sessionUnavailable),
    );
  }
}

/// Information about a session that couldn't be resumed
class SessionUnavailableInfo {
  final String sessionId;
  final String reason;
  final bool hasMarkdownHistory;
  final int messageCount;
  final String message;

  /// The original message that was being sent when the error occurred
  final String pendingMessage;

  const SessionUnavailableInfo({
    required this.sessionId,
    required this.reason,
    required this.hasMarkdownHistory,
    required this.messageCount,
    required this.message,
    required this.pendingMessage,
  });
}

/// Notifier for managing chat messages and streaming
class ChatMessagesNotifier extends StateNotifier<ChatMessagesState> {
  final ChatService _service;
  final Ref _ref;
  static const _uuid = Uuid();
  final _log = logger.createLogger('ChatMessagesNotifier');

  /// Track the session ID of the currently active stream
  /// Used to prevent old streams from updating state after session switch
  String? _activeStreamSessionId;

  /// Throttle for UI updates during streaming (50ms = ~20 updates/sec max)
  final _streamingThrottle = Throttle(const Duration(milliseconds: 50));

  /// Track pending content updates for batching
  List<MessageContent>? _pendingContent;

  /// Background stream manager for handling streams that survive navigation
  final BackgroundStreamManager _streamManager = BackgroundStreamManager.instance;

  /// Current stream subscription (for cleanup when navigating away)
  StreamSubscription<StreamEvent>? _currentStreamSubscription;

  ChatMessagesNotifier(this._service, this._ref) : super(const ChatMessagesState());

  /// Prepare state for switching to a new session
  ///
  /// Clears old messages immediately and shows loading state to prevent
  /// stale content from being displayed during async session load.
  void prepareForSessionSwitch(String newSessionId) {
    // Cancel subscription to current stream
    _currentStreamSubscription?.cancel();
    _currentStreamSubscription = null;
    _activeStreamSessionId = null;

    // Check if the new session has an active background stream
    final hasActiveStream = _streamManager.hasActiveStream(newSessionId);

    // Clear messages immediately and show loading state
    state = ChatMessagesState(
      sessionId: newSessionId,
      isLoading: true,
      isStreaming: hasActiveStream,
      // Clear all other fields to prevent showing stale content
    );
  }

  /// Load messages for a session
  ///
  /// First tries to load the rich SDK transcript (with tool calls, thinking, etc.),
  /// then falls back to markdown messages, then local files.
  /// Also cancels any active stream by invalidating the stream session ID.
  /// If the session was continued from another session, loads prior messages too.
  /// If there's an active background stream for this session, reattaches to it.
  Future<void> loadSession(String sessionId, {bool isLocal = false}) async {
    final trace = perf.trace('LoadSession', metadata: {'sessionId': sessionId, 'isLocal': isLocal});

    // Cancel subscription to current stream (but let it continue in background)
    _currentStreamSubscription?.cancel();
    _currentStreamSubscription = null;
    _activeStreamSessionId = null;

    // Check if there's an active background stream for this session
    if (_streamManager.hasActiveStream(sessionId)) {
      debugPrint('[ChatMessagesNotifier] Reattaching to active background stream for: $sessionId');
      _activeStreamSessionId = sessionId;
      // We'll reattach after loading the current state
    }

    try {
      ChatSession? loadedSession;
      List<ChatMessage> loadedMessages = [];
      bool usedTranscript = false;

      // Try server first unless we know it's local
      if (!isLocal) {
        try {
          // First try to get the rich transcript (has tool calls, thinking, etc.)
          final transcript = await _service.getSessionTranscript(sessionId);
          if (transcript != null && transcript.events.isNotEmpty) {
            loadedMessages = transcript.toMessages();
            usedTranscript = true;
            debugPrint('[ChatMessagesNotifier] Loaded ${loadedMessages.length} messages from SDK transcript (${transcript.eventCount} events)');
          }

          // Get session metadata (we still need this for title, workingDirectory, etc.)
          final sessionData = await _service.getSession(sessionId);
          if (sessionData != null) {
            loadedSession = sessionData.session;
            // Only use markdown messages if transcript didn't provide any
            if (!usedTranscript || loadedMessages.isEmpty) {
              loadedMessages = sessionData.messages;
              debugPrint('[ChatMessagesNotifier] Using ${loadedMessages.length} messages from markdown');
            }
          }
        } catch (e) {
          debugPrint('[ChatMessagesNotifier] Server unavailable, trying local: $e');
        }
      }

      // Fall back to local session reader if not found on server
      if (loadedSession == null) {
        final localReader = _ref.read(localSessionReaderProvider);
        final localSession = await localReader.getSession(sessionId);
        if (localSession != null) {
          loadedSession = localSession.session;
          loadedMessages = localSession.messages;
        }
      }

      if (loadedSession == null) {
        state = state.copyWith(error: 'Session not found');
        return;
      }

      // Check if this session continues another - load prior messages
      List<ChatMessage> priorMessages = [];
      ChatSession? continuedFromSession;

      if (loadedSession.continuedFrom != null) {
        debugPrint('[ChatMessagesNotifier] Session continues from: ${loadedSession.continuedFrom}');
        final localReader = _ref.read(localSessionReaderProvider);
        final originalSession = await localReader.getSession(loadedSession.continuedFrom!);
        if (originalSession != null) {
          priorMessages = originalSession.messages;
          continuedFromSession = originalSession.session;
          debugPrint('[ChatMessagesNotifier] Loaded ${priorMessages.length} prior messages');
        } else {
          debugPrint('[ChatMessagesNotifier] Could not find original session to load prior messages');
        }
      }

      // SIMPLIFIED: The session id IS the SDK session ID now
      // Just use it directly for all API calls
      debugPrint('[ChatMessagesNotifier] Loading session with ID: $sessionId (usedTranscript: $usedTranscript)');

      // Check if there's an active background stream - set isStreaming if so
      final hasActiveStream = _streamManager.hasActiveStream(sessionId);

      // Preserve the model from current state if we have one (set during streaming)
      final currentModel = state.model;

      state = ChatMessagesState(
        messages: loadedMessages,
        sessionId: sessionId,
        sessionTitle: loadedSession.title,
        workingDirectory: loadedSession.workingDirectory,
        viewingSession: loadedSession.isImported ? loadedSession : null,
        priorMessages: priorMessages,
        continuedFromSession: continuedFromSession,
        isStreaming: hasActiveStream,
        isLoading: false, // Loading complete
        model: currentModel, // Preserve model from streaming
      );

      // If there's an active background stream, reattach to receive updates
      if (hasActiveStream) {
        debugPrint('[ChatMessagesNotifier] Session has active stream - reattaching');
        _reattachToBackgroundStream(sessionId);
      }

      trace.end(additionalData: {'messageCount': loadedMessages.length, 'usedTranscript': usedTranscript, 'hasActiveStream': hasActiveStream});
    } catch (e) {
      trace.end(additionalData: {'error': e.toString()});
      _log.error('Error loading session', error: e);
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// Reattach to a background stream to continue receiving updates
  void _reattachToBackgroundStream(String sessionId) {
    _currentStreamSubscription = _streamManager.reattachCallback(
      sessionId: sessionId,
      onEvent: (event) => _handleStreamEvent(event, sessionId),
      onDone: () {
        debugPrint('[ChatMessagesNotifier] Background stream done for: $sessionId');
        if (state.sessionId == sessionId) {
          state = state.copyWith(isStreaming: false);
          _ref.invalidate(chatSessionsProvider);
        }
      },
      onError: (error) {
        debugPrint('[ChatMessagesNotifier] Background stream error for $sessionId: $error');
        if (state.sessionId == sessionId) {
          state = state.copyWith(isStreaming: false, error: error.toString());
        }
      },
    );
  }

  /// Handle a stream event (used by both direct and background streams)
  void _handleStreamEvent(StreamEvent event, String sessionId) {
    // Only process if we're still on this session
    if (state.sessionId != sessionId) return;

    switch (event.type) {
      case StreamEventType.done:
        state = state.copyWith(isStreaming: false);
        // Reload to get final state
        loadSession(sessionId);
        break;
      case StreamEventType.aborted:
        // Stream was stopped by user - session is still valid
        state = state.copyWith(isStreaming: false);
        debugPrint('[ChatMessagesNotifier] Stream aborted: ${event.abortedMessage}');
        // Reload to get current state (conversation continues)
        loadSession(sessionId);
        break;
      case StreamEventType.error:
        state = state.copyWith(
          isStreaming: false,
          error: event.errorMessage ?? 'Unknown error',
        );
        break;
      default:
        // Other events are handled by the main sendMessage loop
        break;
    }
  }

  /// Abort the current streaming session
  ///
  /// Sends abort signal to the server to stop the agent mid-processing.
  /// Returns true if abort was successful.
  Future<bool> abortStream() async {
    final sessionId = state.sessionId;
    if (sessionId == null || !state.isStreaming) {
      debugPrint('[ChatMessagesNotifier] No active stream to abort');
      return false;
    }

    debugPrint('[ChatMessagesNotifier] Aborting stream for: $sessionId');
    final success = await _service.abortStream(sessionId);

    if (success) {
      // Update state to reflect abort
      state = state.copyWith(isStreaming: false);
      // Cancel local subscription
      _currentStreamSubscription?.cancel();
      _currentStreamSubscription = null;
      _activeStreamSessionId = null;
    }

    return success;
  }

  /// Clear current session (for new chat)
  ///
  /// Also cancels any active stream by invalidating the stream session ID.
  /// Preserves workingDirectory if [preserveWorkingDirectory] is true.
  /// Note: Background streams continue even when session is cleared.
  void clearSession({bool preserveWorkingDirectory = false}) {
    // Cancel subscription but let background stream continue
    _currentStreamSubscription?.cancel();
    _currentStreamSubscription = null;
    _activeStreamSessionId = null;

    if (preserveWorkingDirectory && state.workingDirectory != null) {
      state = ChatMessagesState(workingDirectory: state.workingDirectory);
    } else {
      state = const ChatMessagesState();
    }
  }

  /// Set the working directory for new sessions
  ///
  /// [path] should be relative to the vault (e.g., "Chat", "Projects/myapp")
  /// Set to null or 'Chat' for the default thinking-oriented experience.
  void setWorkingDirectory(String? path) {
    state = state.copyWith(
      workingDirectory: path,
      clearWorkingDirectory: path == null,
    );
  }

  /// Set up a continuation from an existing session
  ///
  /// This prepares the chat state to continue from an imported or prior session.
  /// The prior messages are stored for display in the resume marker,
  /// and will be passed as context with the first message.
  void setupContinuation({
    required ChatSession originalSession,
    required List<ChatMessage> priorMessages,
  }) {
    debugPrint('[ChatMessagesNotifier] setupContinuation called');
    debugPrint('[ChatMessagesNotifier] Original session: ${originalSession.id}');
    debugPrint('[ChatMessagesNotifier] Prior messages: ${priorMessages.length}');
    if (priorMessages.isNotEmpty) {
      debugPrint('[ChatMessagesNotifier] First prior message: ${priorMessages.first.textContent.substring(0, (priorMessages.first.textContent.length).clamp(0, 100))}...');
    }
    state = ChatMessagesState(
      continuedFromSession: originalSession,
      priorMessages: priorMessages,
    );
    debugPrint('[ChatMessagesNotifier] State set - isContinuation: ${state.isContinuation}');
  }

  /// Format prior messages as context for the AI
  /// The server wraps this in its own header, so we just provide the messages
  /// Limited to ~50k chars to avoid 413 errors
  String _formatPriorMessagesAsContext() {
    if (state.priorMessages.isEmpty) return '';

    final buffer = StringBuffer();
    const maxChars = 50000;

    // Take most recent messages that fit within limit
    final messages = state.priorMessages.reversed.toList();
    final selectedMessages = <ChatMessage>[];
    int totalChars = 0;

    for (final msg in messages) {
      final content = msg.textContent;
      if (content.isEmpty) continue;

      final msgText = '${msg.role == MessageRole.user ? "Human" : "Assistant"}: $content\n\n';
      if (totalChars + msgText.length > maxChars) break;

      totalChars += msgText.length;
      selectedMessages.insert(0, msg);
    }

    for (final msg in selectedMessages) {
      final role = msg.role == MessageRole.user ? 'Human' : 'Assistant';
      final content = msg.textContent;
      buffer.writeln('$role: $content\n');
    }

    debugPrint('[ChatMessagesNotifier] Formatted ${selectedMessages.length}/${state.priorMessages.length} prior messages ($totalChars chars)');
    return buffer.toString().trim();
  }

  /// Send a message and handle streaming response
  ///
  /// [systemPrompt] - Custom system prompt for this session
  /// If not provided, the server will use the module's AGENTS.md or default prompt.
  ///
  /// [priorConversation] - For continued conversations, prior messages
  /// formatted as text. Goes into system prompt, not shown in chat.
  ///
  /// [contexts] - List of context file paths to load (e.g., ['Chat/contexts/general-context.md'])
  /// Only used on first message of a new chat.
  Future<void> sendMessage({
    required String message,
    String? systemPrompt,
    String? initialContext,
    String? priorConversation,
    List<String>? contexts,
  }) async {
    if (state.isStreaming) return;

    // Generate or use existing session ID
    final sessionId = state.sessionId ?? _uuid.v4();

    // Add user message immediately
    final userMessage = ChatMessage.user(
      sessionId: sessionId,
      text: message,
    );

    // Create placeholder for assistant response
    final assistantMessage = ChatMessage.assistantPlaceholder(
      sessionId: sessionId,
    );

    // Mark this session as the active stream
    _activeStreamSessionId = sessionId;

    state = state.copyWith(
      messages: [...state.messages, userMessage, assistantMessage],
      isStreaming: true,
      sessionId: sessionId,
      error: null,
    );

    // Track accumulated content for streaming
    List<MessageContent> accumulatedContent = [];
    String? actualSessionId;

    // Include prior conversation context if this is a continuation
    // This goes into the system prompt, not shown in the user message
    String? effectivePriorConversation = priorConversation;
    debugPrint('[ChatMessagesNotifier] sendMessage - isContinuation: ${state.isContinuation}');
    debugPrint('[ChatMessagesNotifier] sendMessage - messages.length: ${state.messages.length}');
    debugPrint('[ChatMessagesNotifier] sendMessage - priorMessages.length: ${state.priorMessages.length}');
    if (state.isContinuation && state.messages.length <= 2) {
      // Only inject prior context on first message of continuation
      debugPrint('[ChatMessagesNotifier] Injecting prior conversation context');
      final formatted = _formatPriorMessagesAsContext();
      if (formatted.isNotEmpty) {
        effectivePriorConversation = formatted;
        debugPrint('[ChatMessagesNotifier] Formatted context length: ${effectivePriorConversation.length}');
      } else {
        debugPrint('[ChatMessagesNotifier] WARNING: Prior messages formatted to empty string!');
      }
    } else {
      debugPrint('[ChatMessagesNotifier] NOT injecting prior context (isContinuation: ${state.isContinuation}, messages: ${state.messages.length})');
    }

    try {
      // Get continuedFrom ID for first message of continuation (for persistence)
      final continuedFromId = (state.isContinuation && state.messages.length <= 2)
          ? state.continuedFromSession?.id
          : null;
      debugPrint('[ChatMessagesNotifier] continuedFromId: $continuedFromId');
      if (state.isContinuation) {
        debugPrint('[ChatMessagesNotifier] continuedFromSession.id: ${state.continuedFromSession?.id}');
      }

      await for (final event in _service.streamChat(
        sessionId: sessionId,
        message: message,
        systemPrompt: systemPrompt,
        initialContext: initialContext,
        priorConversation: effectivePriorConversation,
        continuedFrom: continuedFromId,
        workingDirectory: state.workingDirectory,
        contexts: contexts,
      )) {
        // Check if session has changed (user switched chats during stream)
        if (_activeStreamSessionId != sessionId) {
          debugPrint('[ChatMessagesNotifier] Stream cancelled - session changed from $sessionId');
          break; // Exit the stream loop
        }

        switch (event.type) {
          case StreamEventType.session:
            // Server may return a different session ID (for resumed sessions)
            actualSessionId = event.sessionId;
            if (actualSessionId != null && actualSessionId.isNotEmpty && actualSessionId != sessionId) {
              // Update session ID if server assigned a different one
              debugPrint('[ChatMessagesNotifier] Session event has server ID: $actualSessionId (was: $sessionId)');
              _ref.read(currentSessionIdProvider.notifier).state = actualSessionId;
              // ALSO update state.sessionId so future sendMessage calls use the correct ID
              state = state.copyWith(sessionId: actualSessionId);
            }
            // Capture session title if present
            final sessionTitle = event.sessionTitle;
            if (sessionTitle != null && sessionTitle.isNotEmpty) {
              state = state.copyWith(sessionTitle: sessionTitle);
            }
            // Capture session resume info
            final resumeInfo = event.sessionResumeInfo;
            if (resumeInfo != null) {
              debugPrint('[ChatMessagesNotifier] Session resume info: ${resumeInfo.method} '
                  '(sdkResumeFailed: ${resumeInfo.sdkResumeFailed}, '
                  'contextInjected: ${resumeInfo.contextInjected}, '
                  'messagesInjected: ${resumeInfo.messagesInjected})');
              state = state.copyWith(sessionResumeInfo: resumeInfo);
            }
            break;

          case StreamEventType.model:
            // Model info from SDK - capture for display
            final model = event.model;
            if (model != null) {
              debugPrint('[ChatMessagesNotifier] Using model: $model');
              state = state.copyWith(model: model);
            }
            break;

          case StreamEventType.text:
            // Accumulating text content from server
            final content = event.textContent;
            if (content != null) {
              // Track the current text for potential conversion to "thinking"
              // The server sends accumulated text, so we replace the last text block
              final hasTextContent = accumulatedContent.any((c) => c.type == ContentType.text);
              if (hasTextContent) {
                // Replace the last text content
                final lastTextIndex = accumulatedContent.lastIndexWhere(
                    (c) => c.type == ContentType.text);
                accumulatedContent[lastTextIndex] = MessageContent.text(content);
              } else {
                accumulatedContent.add(MessageContent.text(content));
              }
              _updateAssistantMessage(accumulatedContent, isStreaming: true);
            }
            break;

          case StreamEventType.toolUse:
            // Flush any pending UI updates before showing tool call
            _flushPendingUpdates();

            // Tool call event - convert any pending text to "thinking"
            final toolCall = event.toolCall;
            if (toolCall != null) {
              // Check if there's text content before this tool call
              final lastTextIndex = accumulatedContent.lastIndexWhere(
                  (c) => c.type == ContentType.text);
              if (lastTextIndex >= 0) {
                // Convert the last text block to thinking
                final thinkingText = accumulatedContent[lastTextIndex].text ?? '';
                if (thinkingText.isNotEmpty) {
                  accumulatedContent[lastTextIndex] = MessageContent.thinking(thinkingText);
                }
              }
              accumulatedContent.add(MessageContent.toolUse(toolCall));
              // Force immediate update for tool events (not throttled)
              _performMessageUpdate(accumulatedContent, isStreaming: true);
            }
            break;

          case StreamEventType.toolResult:
            // Tool result - attach to the corresponding tool call
            final toolUseId = event.toolUseId;
            final resultContent = event.toolResultContent;
            if (toolUseId != null && resultContent != null) {
              // Find the tool call with this ID and update it with the result
              for (int i = 0; i < accumulatedContent.length; i++) {
                final content = accumulatedContent[i];
                if (content.type == ContentType.toolUse &&
                    content.toolCall?.id == toolUseId) {
                  // Replace with updated tool call that has the result
                  final updatedToolCall = content.toolCall!.withResult(
                    resultContent,
                    isError: event.toolResultIsError,
                  );
                  accumulatedContent[i] = MessageContent.toolUse(updatedToolCall);
                  _updateAssistantMessage(accumulatedContent, isStreaming: true);
                  break;
                }
              }
            }
            break;

          case StreamEventType.done:
            // Stream complete
            _updateAssistantMessage(accumulatedContent, isStreaming: false);

            // CRITICAL: Capture session ID from done event (for new sessions, this is the first time we get the real ID)
            final doneSessionId = event.sessionId;
            if (doneSessionId != null && doneSessionId.isNotEmpty && doneSessionId != actualSessionId) {
              debugPrint('[ChatMessagesNotifier] Done event has new session ID: $doneSessionId (was: $actualSessionId)');
              actualSessionId = doneSessionId;
              _ref.read(currentSessionIdProvider.notifier).state = doneSessionId;
              // ALSO update state.sessionId so future sendMessage calls use the correct ID
              state = state.copyWith(sessionId: doneSessionId);
            }

            // Capture session title if present in done event
            final doneTitle = event.sessionTitle;
            // Also capture resume info from done event (may have more complete info)
            final doneResumeInfo = event.sessionResumeInfo;
            if (doneResumeInfo != null) {
              debugPrint('[ChatMessagesNotifier] Done event resume info: ${doneResumeInfo.method}');
              state = state.copyWith(
                isStreaming: false,
                sessionTitle: (doneTitle != null && doneTitle.isNotEmpty) ? doneTitle : null,
                sessionResumeInfo: doneResumeInfo,
              );
            } else if (doneTitle != null && doneTitle.isNotEmpty) {
              state = state.copyWith(isStreaming: false, sessionTitle: doneTitle);
            } else {
              state = state.copyWith(isStreaming: false);
            }
            // Refresh sessions list to get updated title
            _ref.invalidate(chatSessionsProvider);
            // Search indexing is handled by the agent server via MCP
            break;

          case StreamEventType.error:
            final errorMsg = event.errorMessage ?? 'Unknown error';
            state = state.copyWith(
              isStreaming: false,
              error: errorMsg,
            );
            _updateAssistantMessage(
              [MessageContent.text('Error: $errorMsg')],
              isStreaming: false,
            );
            break;

          case StreamEventType.thinking:
            // Extended thinking content from Claude
            final thinkingText = event.thinkingContent;
            if (thinkingText != null && thinkingText.isNotEmpty) {
              accumulatedContent.add(MessageContent.thinking(thinkingText));
              _updateAssistantMessage(accumulatedContent, isStreaming: true);
            }
            break;

          case StreamEventType.sessionUnavailable:
            // SDK session couldn't be resumed - ask user how to proceed
            final unavailableInfo = SessionUnavailableInfo(
              sessionId: event.sessionId ?? actualSessionId ?? '',
              reason: event.unavailableReason ?? 'unknown',
              hasMarkdownHistory: event.hasMarkdownHistory,
              messageCount: event.markdownMessageCount,
              message: event.unavailableMessage ?? 'Session could not be resumed.',
              pendingMessage: message,
            );
            state = state.copyWith(
              isStreaming: false,
              sessionUnavailable: unavailableInfo,
            );
            debugPrint('[ChatMessagesNotifier] Session unavailable: ${unavailableInfo.reason}');
            return; // Stop processing, wait for user decision

          case StreamEventType.aborted:
            // Stream was stopped by user - session is still valid for future messages
            debugPrint('[ChatMessagesNotifier] Stream aborted by user');
            _updateAssistantMessage(accumulatedContent, isStreaming: false);
            state = state.copyWith(isStreaming: false);
            // Reload session to get the final state
            loadSession(actualSessionId ?? sessionId);
            return; // Exit the stream loop

          case StreamEventType.init:
          case StreamEventType.unknown:
            // Ignore init and unknown events
            break;
        }
      }

      // If we exited the loop without a done/error event (e.g., session switch or unexpected stream end),
      // make sure to stop streaming state so the user can send another message
      if (state.isStreaming) {
        debugPrint('[ChatMessagesNotifier] Stream ended without done event - cleaning up');
        state = state.copyWith(isStreaming: false);
      }
    } catch (e) {
      debugPrint('[ChatMessagesNotifier] Stream error: $e');
      state = state.copyWith(
        isStreaming: false,
        error: e.toString(),
      );
      _updateAssistantMessage(
        [MessageContent.text('Error: $e')],
        isStreaming: false,
      );
    } finally {
      // Final safety net: ensure streaming is always stopped when sendMessage exits
      if (state.isStreaming && _activeStreamSessionId == sessionId) {
        debugPrint('[ChatMessagesNotifier] Finally block cleanup - forcing streaming off');
        state = state.copyWith(isStreaming: false);
      }
    }
  }

  /// Update the assistant message being streamed
  /// Uses throttling during streaming to reduce UI updates
  void _updateAssistantMessage(List<MessageContent> content, {required bool isStreaming}) {
    // Always update immediately when streaming ends
    if (!isStreaming) {
      _pendingContent = null;
      _performMessageUpdate(content, isStreaming: false);
      _streamingThrottle.reset();
      return;
    }

    // Store pending content
    _pendingContent = content;

    // Throttle UI updates during streaming
    if (_streamingThrottle.shouldProceed()) {
      _performMessageUpdate(content, isStreaming: true);
    }
  }

  /// Actually perform the message update (called from throttled path)
  void _performMessageUpdate(List<MessageContent> content, {required bool isStreaming}) {
    final trace = perf.trace('MessageUpdate', metadata: {
      'messageCount': state.messages.length,
      'contentBlocks': content.length,
    });

    final messages = List<ChatMessage>.from(state.messages);
    if (messages.isEmpty) {
      trace.end();
      return;
    }

    // Find the last assistant message (should be the streaming one)
    final lastIndex = messages.length - 1;
    if (messages[lastIndex].role != MessageRole.assistant) {
      trace.end();
      return;
    }

    messages[lastIndex] = messages[lastIndex].copyWith(
      content: List.from(content),
      isStreaming: isStreaming,
    );

    state = state.copyWith(messages: messages);
    trace.end();
  }

  /// Flush any pending content updates (call when important events happen)
  void _flushPendingUpdates() {
    if (_pendingContent != null) {
      _performMessageUpdate(_pendingContent!, isStreaming: true);
    }
  }

  /// Handle user's choice for session recovery
  /// Called when user selects how to proceed after session_unavailable
  ///
  /// [recoveryMode] - Either 'inject_context' or 'fresh_start'
  Future<void> recoverSession(String recoveryMode) async {
    final unavailableInfo = state.sessionUnavailable;
    if (unavailableInfo == null) {
      debugPrint('[ChatMessagesNotifier] recoverSession called but no unavailable info');
      return;
    }

    debugPrint('[ChatMessagesNotifier] Recovering session with mode: $recoveryMode');

    // Clear the unavailable state
    state = state.copyWith(clearSessionUnavailable: true);

    // If fresh start, also clear the session ID to get a new one
    if (recoveryMode == 'fresh_start') {
      state = state.copyWith(
        sessionId: null,
        messages: [],
        clearSessionUnavailable: true,
      );
    }

    // Retry the original message
    await sendMessage(message: unavailableInfo.pendingMessage);
  }

  /// Dismiss the session unavailable dialog without retrying
  void dismissSessionUnavailable() {
    state = state.copyWith(clearSessionUnavailable: true);
  }
}

/// Provider for chat messages state
final chatMessagesProvider =
    StateNotifierProvider<ChatMessagesNotifier, ChatMessagesState>((ref) {
  final service = ref.watch(chatServiceProvider);
  return ChatMessagesNotifier(service, ref);
});

// ============================================================
// Session Management Actions
// ============================================================

/// Provider for deleting a session
final deleteSessionProvider = Provider<Future<void> Function(String)>((ref) {
  final service = ref.watch(chatServiceProvider);
  return (String sessionId) async {
    await service.deleteSession(sessionId);
    // Clear current session if it was deleted
    if (ref.read(currentSessionIdProvider) == sessionId) {
      ref.read(currentSessionIdProvider.notifier).state = null;
      ref.read(chatMessagesProvider.notifier).clearSession();
    }
    // Refresh sessions list
    ref.invalidate(chatSessionsProvider);
  };
});

/// Provider for creating a new chat
final newChatProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(currentSessionIdProvider.notifier).state = null;
    ref.read(chatMessagesProvider.notifier).clearSession();
  };
});

/// Provider for switching to a session
///
/// Set [isLocal] to true for imported or local-only sessions that don't
/// need to check the server.
final switchSessionProvider = Provider<Future<void> Function(String, {bool isLocal})>((ref) {
  return (String sessionId, {bool isLocal = false}) async {
    // Immediately clear old messages and show loading state to prevent
    // showing stale content from previous session during async load
    ref.read(chatMessagesProvider.notifier).prepareForSessionSwitch(sessionId);
    ref.read(currentSessionIdProvider.notifier).state = sessionId;
    await ref.read(chatMessagesProvider.notifier).loadSession(sessionId, isLocal: isLocal);
  };
});

/// Provider for continuing an imported session
///
/// Creates a new chat that continues from the given session,
/// passing all prior messages as context for the AI.
final continueSessionProvider = Provider<Future<void> Function(ChatSession)>((ref) {
  final service = ref.watch(chatServiceProvider);
  final localReader = ref.watch(localSessionReaderProvider);

  return (ChatSession originalSession) async {
    debugPrint('[ChatProviders] continueSessionProvider called');
    debugPrint('[ChatProviders] Original session ID: ${originalSession.id}');
    debugPrint('[ChatProviders] isLocal: ${originalSession.isLocal}, isImported: ${originalSession.isImported}');

    try {
      List<ChatMessage> priorMessages = [];

      // For local/imported sessions, use local reader
      // For server sessions, try the server API
      if (originalSession.isLocal || originalSession.isImported) {
        debugPrint('[ChatProviders] Loading from local reader...');
        final localSession = await localReader.getSession(originalSession.id);
        if (localSession == null) {
          debugPrint('[ChatProviders] WARNING: localReader.getSession returned null!');
        } else {
          priorMessages = localSession.messages;
          debugPrint('[ChatProviders] Loaded ${priorMessages.length} messages from local session');
          if (priorMessages.isNotEmpty) {
            debugPrint('[ChatProviders] First message preview: ${priorMessages.first.textContent.substring(0, priorMessages.first.textContent.length.clamp(0, 100))}...');
          }
        }
      } else {
        debugPrint('[ChatProviders] Loading from server...');
        final sessionData = await service.getSession(originalSession.id);
        priorMessages = sessionData?.messages ?? [];
        debugPrint('[ChatProviders] Loaded ${priorMessages.length} messages from server');
      }

      // Clear current session and set up continuation
      ref.read(currentSessionIdProvider.notifier).state = null;
      ref.read(chatMessagesProvider.notifier).setupContinuation(
        originalSession: originalSession,
        priorMessages: priorMessages,
      );
    } catch (e, st) {
      debugPrint('[ChatProviders] Error setting up continuation: $e');
      debugPrint('[ChatProviders] Stack trace: $st');
      // Fall back to just clearing the session
      ref.read(currentSessionIdProvider.notifier).state = null;
      ref.read(chatMessagesProvider.notifier).clearSession();
    }
  };
});

// ============================================================
// Vault Browsing
// ============================================================

/// Provider for browsing vault directories
///
/// Use with .family to specify the path:
/// - ref.watch(vaultDirectoryProvider('')) - vault root
/// - ref.watch(vaultDirectoryProvider('Projects')) - Projects folder
/// - ref.watch(vaultDirectoryProvider('Projects/myapp')) - specific project
final vaultDirectoryProvider = FutureProvider.family<List<VaultEntry>, String>((ref, path) async {
  final service = ref.watch(chatServiceProvider);
  return service.listDirectory(path: path);
});

/// Provider for the current working directory path being browsed
final currentBrowsePathProvider = StateProvider<String>((ref) => '');

/// Provider for the selected working directory for new chats
///
/// This is the working directory that will be used when starting a new chat.
/// null means use the default (Chat/).
final selectedWorkingDirectoryProvider = StateProvider<String?>((ref) => null);

// ============================================================
// Context Selection
// ============================================================

/// Provider for available context files
///
/// Fetches context files from Chat/contexts/ directory.
/// Returns empty list if server is unavailable (graceful degradation).
final availableContextsProvider = FutureProvider<List<ContextFile>>((ref) async {
  final service = ref.watch(chatServiceProvider);
  try {
    return await service.getContexts();
  } catch (e) {
    debugPrint('[ChatProviders] Error loading contexts: $e');
    return []; // Graceful degradation - show no contexts if server unavailable
  }
});

/// Provider for selected context file paths for new chats
///
/// Default: ['Chat/contexts/general-context.md']
/// Paths are relative to vault (e.g., "Chat/contexts/work-context.md")
final selectedContextsProvider = StateProvider<List<String>>((ref) {
  return ['Chat/contexts/general-context.md'];
});
