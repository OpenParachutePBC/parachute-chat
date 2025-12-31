import 'chat_message.dart';

/// Represents the full SDK transcript for a session
///
/// This contains the raw events from Claude SDK's JSONL storage,
/// which is much richer than the markdown summary.
class SessionTranscript {
  final String sessionId;
  final String? transcriptPath;
  final int eventCount;
  final List<TranscriptEvent> events;

  const SessionTranscript({
    required this.sessionId,
    this.transcriptPath,
    required this.eventCount,
    required this.events,
  });

  factory SessionTranscript.fromJson(Map<String, dynamic> json) {
    final eventsList = json['events'] as List<dynamic>? ?? [];

    return SessionTranscript(
      sessionId: json['sessionId'] as String? ?? '',
      transcriptPath: json['transcriptPath'] as String?,
      eventCount: json['eventCount'] as int? ?? eventsList.length,
      events: eventsList
          .map((e) => TranscriptEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Convert transcript events into ChatMessage objects
  ///
  /// Groups events by conversation turn, combining:
  /// - User messages
  /// - Assistant text, tool calls, and thinking blocks
  ///
  /// The SDK sends multiple `assistant` events during streaming, where each
  /// event contains the FULL accumulated content up to that point (not deltas).
  /// So we only use the LAST assistant event before the next user message.
  List<ChatMessage> toMessages() {
    final messages = <ChatMessage>[];

    // First pass: identify turn boundaries (user messages mark the start of turns)
    // and collect the last assistant event for each turn
    final turns = <_ConversationTurn>[];
    _ConversationTurn? currentTurn;

    for (final event in events) {
      if (event.type == 'user' && event.message != null) {
        // Save previous turn if any
        if (currentTurn != null) {
          turns.add(currentTurn);
        }
        // Start new turn with this user message
        currentTurn = _ConversationTurn(userEvent: event);
      } else if (event.type == 'assistant' && event.message != null) {
        // Update the last assistant event for current turn
        // (each assistant event contains full accumulated content)
        if (currentTurn != null) {
          currentTurn.lastAssistantEvent = event;
        }
      }
    }
    // Don't forget the last turn
    if (currentTurn != null) {
      turns.add(currentTurn);
    }

    // Second pass: convert turns to messages
    for (final turn in turns) {
      // Add user message
      final userContent = turn.userEvent.message!['content'];
      String userText = '';
      if (userContent is String) {
        userText = userContent;
      } else if (userContent is List) {
        for (final block in userContent) {
          if (block is Map && block['type'] == 'text') {
            userText += block['text'] as String? ?? '';
          }
        }
      }

      if (userText.isNotEmpty) {
        messages.add(ChatMessage(
          id: turn.userEvent.uuid ?? DateTime.now().millisecondsSinceEpoch.toString(),
          sessionId: sessionId,
          role: MessageRole.user,
          content: [MessageContent.text(userText)],
          timestamp: turn.userEvent.timestamp ?? DateTime.now(),
        ));
      }

      // Add assistant message (from the last assistant event in this turn)
      if (turn.lastAssistantEvent != null) {
        final assistantContent = <MessageContent>[];
        final content = turn.lastAssistantEvent!.message!['content'];

        if (content is List) {
          for (final block in content) {
            if (block is! Map) continue;
            final blockType = block['type'] as String?;

            if (blockType == 'text') {
              final text = block['text'] as String? ?? '';
              if (text.isNotEmpty) {
                assistantContent.add(MessageContent.text(text));
              }
            } else if (blockType == 'tool_use') {
              assistantContent.add(MessageContent.toolUse(ToolCall(
                id: block['id'] as String? ?? '',
                name: block['name'] as String? ?? '',
                input: block['input'] as Map<String, dynamic>? ?? {},
              )));
            } else if (blockType == 'thinking') {
              final thinking = block['thinking'] as String? ?? '';
              if (thinking.isNotEmpty) {
                assistantContent.add(MessageContent.thinking(thinking));
              }
            }
          }
        }

        if (assistantContent.isNotEmpty) {
          messages.add(ChatMessage(
            id: turn.lastAssistantEvent!.uuid ?? DateTime.now().millisecondsSinceEpoch.toString(),
            sessionId: sessionId,
            role: MessageRole.assistant,
            content: assistantContent,
            timestamp: turn.lastAssistantEvent!.timestamp ?? DateTime.now(),
          ));
        }
      }
    }

    return messages;
  }
}

/// Helper class to track a conversation turn
class _ConversationTurn {
  final TranscriptEvent userEvent;
  TranscriptEvent? lastAssistantEvent;

  _ConversationTurn({required this.userEvent});
}

/// A single event from the SDK transcript
class TranscriptEvent {
  final String type;
  final String? uuid;
  final String? parentUuid;
  final DateTime? timestamp;
  final Map<String, dynamic>? message;
  final Map<String, dynamic> raw;

  const TranscriptEvent({
    required this.type,
    this.uuid,
    this.parentUuid,
    this.timestamp,
    this.message,
    required this.raw,
  });

  factory TranscriptEvent.fromJson(Map<String, dynamic> json) {
    DateTime? timestamp;
    final tsValue = json['timestamp'];
    if (tsValue is String) {
      timestamp = DateTime.tryParse(tsValue);
    } else if (tsValue is int) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(tsValue);
    }

    return TranscriptEvent(
      type: json['type'] as String? ?? 'unknown',
      uuid: json['uuid'] as String?,
      parentUuid: json['parentUuid'] as String?,
      timestamp: timestamp,
      message: json['message'] as Map<String, dynamic>?,
      raw: json,
    );
  }
}
