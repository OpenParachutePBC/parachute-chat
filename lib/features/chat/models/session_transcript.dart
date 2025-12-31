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
  List<ChatMessage> toMessages() {
    final messages = <ChatMessage>[];
    String? currentUserContent;
    List<MessageContent> currentAssistantContent = [];
    DateTime? currentTimestamp;
    String? currentMessageId;

    for (final event in events) {
      if (event.type == 'user' && event.message != null) {
        // Save any pending assistant message
        if (currentAssistantContent.isNotEmpty) {
          messages.add(ChatMessage(
            id: currentMessageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
            sessionId: sessionId,
            role: MessageRole.assistant,
            content: currentAssistantContent,
            timestamp: currentTimestamp ?? DateTime.now(),
          ));
          currentAssistantContent = [];
        }

        // Parse user message content
        final content = event.message!['content'];
        String userText = '';
        if (content is String) {
          userText = content;
        } else if (content is List) {
          for (final block in content) {
            if (block is Map && block['type'] == 'text') {
              userText += block['text'] as String? ?? '';
            }
          }
        }

        if (userText.isNotEmpty) {
          messages.add(ChatMessage(
            id: event.uuid ?? DateTime.now().millisecondsSinceEpoch.toString(),
            sessionId: sessionId,
            role: MessageRole.user,
            content: [MessageContent.text(userText)],
            timestamp: event.timestamp ?? DateTime.now(),
          ));
        }

        currentTimestamp = event.timestamp;
        currentMessageId = null;
      } else if (event.type == 'assistant' && event.message != null) {
        currentTimestamp ??= event.timestamp;
        currentMessageId ??= event.uuid;

        // Parse assistant message content blocks
        final content = event.message!['content'];
        if (content is List) {
          for (final block in content) {
            if (block is! Map) continue;

            final blockType = block['type'] as String?;

            if (blockType == 'text') {
              final text = block['text'] as String? ?? '';
              if (text.isNotEmpty) {
                // Check if we should append to existing text or create new
                if (currentAssistantContent.isNotEmpty &&
                    currentAssistantContent.last.type == ContentType.text) {
                  // Replace last text with updated version (streaming accumulates)
                  currentAssistantContent.removeLast();
                }
                currentAssistantContent.add(MessageContent.text(text));
              }
            } else if (blockType == 'tool_use') {
              currentAssistantContent.add(MessageContent.toolUse(ToolCall(
                id: block['id'] as String? ?? '',
                name: block['name'] as String? ?? '',
                input: block['input'] as Map<String, dynamic>? ?? {},
              )));
            } else if (blockType == 'thinking') {
              final thinking = block['thinking'] as String? ?? '';
              if (thinking.isNotEmpty) {
                currentAssistantContent.add(MessageContent.thinking(thinking));
              }
            }
          }
        }
      }
    }

    // Don't forget the last assistant message
    if (currentAssistantContent.isNotEmpty) {
      messages.add(ChatMessage(
        id: currentMessageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        sessionId: sessionId,
        role: MessageRole.assistant,
        content: currentAssistantContent,
        timestamp: currentTimestamp ?? DateTime.now(),
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
