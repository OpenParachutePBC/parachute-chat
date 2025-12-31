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
  /// The SDK transcript structure:
  /// - `user` events with `text` content = human messages (turn boundaries)
  /// - `user` events with `tool_result` content = tool responses (NOT human messages)
  /// - `assistant` events = AI responses (text, tool_use, thinking)
  ///
  /// Each assistant event represents a SEPARATE API call, not streaming updates.
  /// We aggregate ALL assistant content between human messages into one ChatMessage.
  List<ChatMessage> toMessages() {
    final messages = <ChatMessage>[];

    // Track accumulated assistant content between human messages
    List<MessageContent> pendingAssistantContent = [];
    DateTime? assistantTimestamp;
    String? assistantId;

    for (final event in events) {
      if (event.type == 'user' && event.message != null) {
        final content = event.message!['content'];

        // Check if this is a human message (text) or tool result
        bool isHumanMessage = false;
        String humanText = '';

        if (content is String) {
          isHumanMessage = true;
          humanText = content;
        } else if (content is List) {
          for (final block in content) {
            if (block is Map) {
              if (block['type'] == 'text') {
                isHumanMessage = true;
                humanText += block['text'] as String? ?? '';
              }
              // tool_result blocks are NOT human messages
            }
          }
        }

        if (isHumanMessage && humanText.isNotEmpty) {
          // First, flush any pending assistant content
          if (pendingAssistantContent.isNotEmpty) {
            messages.add(ChatMessage(
              id: assistantId ?? DateTime.now().millisecondsSinceEpoch.toString(),
              sessionId: sessionId,
              role: MessageRole.assistant,
              content: pendingAssistantContent,
              timestamp: assistantTimestamp ?? DateTime.now(),
            ));
            pendingAssistantContent = [];
            assistantTimestamp = null;
            assistantId = null;
          }

          // Add the human message
          messages.add(ChatMessage(
            id: event.uuid ?? DateTime.now().millisecondsSinceEpoch.toString(),
            sessionId: sessionId,
            role: MessageRole.user,
            content: [MessageContent.text(humanText)],
            timestamp: event.timestamp ?? DateTime.now(),
          ));
        }
        // If it's a tool_result, we just skip it (don't show in UI)

      } else if (event.type == 'assistant' && event.message != null) {
        final content = event.message!['content'];

        // Set timestamp from first assistant event in this group
        assistantTimestamp ??= event.timestamp;
        assistantId ??= event.uuid;

        if (content is List) {
          for (final block in content) {
            if (block is! Map) continue;
            final blockType = block['type'] as String?;

            if (blockType == 'text') {
              final text = block['text'] as String? ?? '';
              if (text.isNotEmpty) {
                pendingAssistantContent.add(MessageContent.text(text));
              }
            } else if (blockType == 'tool_use') {
              // When we see a tool_use, convert any preceding text to thinking
              // (text before tools is "thinking out loud", not final response)
              for (int i = 0; i < pendingAssistantContent.length; i++) {
                if (pendingAssistantContent[i].type == ContentType.text) {
                  final thinkingText = pendingAssistantContent[i].text ?? '';
                  if (thinkingText.isNotEmpty) {
                    pendingAssistantContent[i] = MessageContent.thinking(thinkingText);
                  }
                }
              }
              pendingAssistantContent.add(MessageContent.toolUse(ToolCall(
                id: block['id'] as String? ?? '',
                name: block['name'] as String? ?? '',
                input: block['input'] as Map<String, dynamic>? ?? {},
              )));
            } else if (blockType == 'thinking') {
              final thinking = block['thinking'] as String? ?? '';
              if (thinking.isNotEmpty) {
                pendingAssistantContent.add(MessageContent.thinking(thinking));
              }
            }
          }
        }
      }
    }

    // Flush any remaining assistant content
    if (pendingAssistantContent.isNotEmpty) {
      messages.add(ChatMessage(
        id: assistantId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        sessionId: sessionId,
        role: MessageRole.assistant,
        content: pendingAssistantContent,
        timestamp: assistantTimestamp ?? DateTime.now(),
      ));
    }

    return messages;
  }
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
