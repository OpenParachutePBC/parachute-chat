import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/chat_session.dart';
import '../models/chat_message.dart';
import '../models/stream_event.dart';
import '../models/system_prompt_info.dart';
import '../models/vault_entry.dart';
import '../models/session_transcript.dart';

/// Service for communicating with the parachute-base backend
///
/// Uses the simplified 8-endpoint API:
///   POST /api/chat           - Run agent (streaming)
///   GET  /api/chat           - List sessions
///   GET  /api/chat/:id       - Get session
///   DELETE /api/chat/:id     - Delete session
///   GET  /api/modules/:mod/prompt   - Get module prompt
///   PUT  /api/modules/:mod/prompt   - Update module prompt
///   GET  /api/modules/:mod/search   - Search module
///   POST /api/modules/:mod/index    - Rebuild index
class ChatService {
  final String baseUrl;
  final http.Client _client;

  /// Timeout for non-streaming HTTP requests
  static const requestTimeout = Duration(seconds: 30);

  ChatService({required this.baseUrl}) : _client = http.Client();

  // ============================================================
  // Sessions
  // ============================================================

  /// Get all chat sessions
  Future<List<ChatSession>> getSessions() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to get sessions: ${response.statusCode}');
      }

      // API returns {"sessions": [...]}
      final decoded = jsonDecode(response.body);
      final List<dynamic> data;
      if (decoded is List) {
        data = decoded;
      } else if (decoded is Map<String, dynamic> && decoded['sessions'] is List) {
        data = decoded['sessions'] as List<dynamic>;
      } else {
        data = [];
      }
      return data
          .map((json) => ChatSession.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[ChatService] Error getting sessions: $e');
      rethrow;
    }
  }

  /// Get a specific session with messages
  Future<ChatSessionWithMessages?> getSession(String sessionId) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/chat/${Uri.encodeComponent(sessionId)}'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(requestTimeout);

      if (response.statusCode == 404) {
        return null;
      }

      if (response.statusCode != 200) {
        throw Exception('Failed to get session: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ChatSessionWithMessages.fromJson(data);
    } catch (e) {
      debugPrint('[ChatService] Error getting session: $e');
      rethrow;
    }
  }

  /// Delete a session
  Future<void> deleteSession(String sessionId) async {
    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/api/chat/${Uri.encodeComponent(sessionId)}'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to delete session: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[ChatService] Error deleting session: $e');
      rethrow;
    }
  }

  /// Get the full SDK transcript for a session
  ///
  /// Returns rich event history including tool calls, thinking blocks, etc.
  /// This is more detailed than the markdown-based messages.
  Future<SessionTranscript?> getSessionTranscript(String sessionId) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/chat/${Uri.encodeComponent(sessionId)}/transcript'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 60)); // Transcripts can be large

      if (response.statusCode == 404) {
        debugPrint('[ChatService] No transcript available for session $sessionId');
        return null;
      }

      if (response.statusCode != 200) {
        throw Exception('Failed to get transcript: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return SessionTranscript.fromJson(data);
    } catch (e) {
      debugPrint('[ChatService] Error getting transcript: $e');
      return null; // Don't rethrow - transcript is optional enhancement
    }
  }

  // ============================================================
  // Module Prompt (System Prompt)
  // ============================================================

  /// Get the module prompt info
  ///
  /// Returns information about the Chat module's system prompt including:
  /// - content: The current prompt text (from AGENTS.md or default)
  /// - exists: Whether AGENTS.md exists for this module
  /// - defaultPrompt: The built-in default prompt
  Future<ModulePromptInfo> getModulePrompt({String module = 'chat'}) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/modules/$module/prompt'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to get module prompt: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ModulePromptInfo.fromJson(data);
    } catch (e) {
      debugPrint('[ChatService] Error getting module prompt: $e');
      rethrow;
    }
  }

  /// Save module prompt (AGENTS.md content)
  ///
  /// Creates or updates the AGENTS.md file in the module's folder.
  /// This will override the built-in default system prompt.
  Future<void> saveModulePrompt(String content, {String module = 'chat'}) async {
    try {
      final response = await _client.put(
        Uri.parse('$baseUrl/api/modules/$module/prompt'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'content': content}),
      ).timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to save module prompt: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[ChatService] Error saving module prompt: $e');
      rethrow;
    }
  }

  // Legacy methods for backward compatibility
  Future<DefaultPromptInfo> getDefaultPrompt() async {
    final info = await getModulePrompt();
    return DefaultPromptInfo(
      content: info.defaultPrompt,
      isActive: !info.exists,
    );
  }

  Future<AgentsMdInfo> getAgentsMd() async {
    final info = await getModulePrompt();
    return AgentsMdInfo(
      exists: info.exists,
      content: info.exists ? info.content : null,
    );
  }

  Future<void> saveAgentsMd(String content) async {
    await saveModulePrompt(content);
  }

  // ============================================================
  // Vault Browsing
  // ============================================================

  /// List directory contents in the vault
  ///
  /// [path] - Relative path within vault (e.g., "", "Projects", "Code/myapp")
  /// Returns entries with metadata including hasClaudeMd for directories
  Future<List<VaultEntry>> listDirectory({String path = ''}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/ls').replace(
        queryParameters: path.isNotEmpty ? {'path': path} : null,
      );

      final response = await _client.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to list directory: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final entries = data['entries'] as List<dynamic>? ?? [];

      return entries
          .map((e) => VaultEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[ChatService] Error listing directory: $e');
      rethrow;
    }
  }

  // ============================================================
  // Streaming Chat
  // ============================================================

  /// Send a message and receive streaming response
  /// Returns a stream of events as they arrive
  ///
  /// [systemPrompt] - Custom system prompt for this session
  /// If not provided, the server will use the module's AGENTS.md or default prompt
  ///
  /// [priorConversation] - For continued conversations, formatted prior messages
  /// that go into the system prompt (not shown in user message)
  ///
  /// [continuedFrom] - ID of the session this continues from (for persistence)
  ///
  /// [workingDirectory] - Working directory for this session (relative to vault)
  /// If provided, the agent operates in this directory and loads its CLAUDE.md
  Stream<StreamEvent> streamChat({
    required String sessionId,
    required String message,
    String? systemPrompt,
    String? initialContext,
    String? priorConversation,
    String? continuedFrom,
    String? workingDirectory,
  }) async* {
    debugPrint('[ChatService] Starting stream chat');
    debugPrint('[ChatService] Session: $sessionId');
    debugPrint('[ChatService] Message: ${message.substring(0, message.length.clamp(0, 50))}...');
    debugPrint('[ChatService] priorConversation provided: ${priorConversation != null}');
    if (priorConversation != null) {
      debugPrint('[ChatService] priorConversation length: ${priorConversation.length}');
    }

    final request = http.Request(
      'POST',
      Uri.parse('$baseUrl/api/chat'),
    );

    request.headers['Content-Type'] = 'application/json';
    final requestBody = {
      'message': message,
      'sessionId': sessionId,
      'module': 'chat',
      if (systemPrompt != null) 'systemPrompt': systemPrompt,
      if (initialContext != null) 'initialContext': initialContext,
      if (priorConversation != null) 'priorConversation': priorConversation,
      if (continuedFrom != null) 'continuedFrom': continuedFrom,
      if (workingDirectory != null) 'workingDirectory': workingDirectory,
    };
    debugPrint('[ChatService] Request body keys: ${requestBody.keys.toList()}');
    request.body = jsonEncode(requestBody);

    // Timeouts for streaming requests
    const connectionTimeout = Duration(seconds: 30);
    const chunkTimeout = Duration(seconds: 60); // Allow time for AI thinking

    try {
      final streamedResponse = await _client.send(request).timeout(
        connectionTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Connection to server timed out after ${connectionTimeout.inSeconds}s',
          );
        },
      );

      if (streamedResponse.statusCode != 200) {
        yield StreamEvent(
          type: StreamEventType.error,
          data: {'error': 'Server returned ${streamedResponse.statusCode}'},
        );
        return;
      }

      String buffer = '';

      // Add per-chunk timeout to detect stalled connections
      await for (final chunk in streamedResponse.stream
          .timeout(chunkTimeout, onTimeout: (sink) {
            sink.addError(TimeoutException(
              'No data received for ${chunkTimeout.inSeconds}s - connection may be stalled',
            ));
            sink.close();
          })
          .transform(utf8.decoder)) {
        buffer += chunk;

        // Process complete lines (SSE format: data: {...}\n\n)
        while (buffer.contains('\n')) {
          final newlineIndex = buffer.indexOf('\n');
          final line = buffer.substring(0, newlineIndex).trim();
          buffer = buffer.substring(newlineIndex + 1);

          if (line.isEmpty) continue;

          final event = StreamEvent.parse(line);
          if (event != null) {
            debugPrint('[ChatService] Event: ${event.type}');
            yield event;

            if (event.type == StreamEventType.done ||
                event.type == StreamEventType.error) {
              return;
            }
          } else if (line.isNotEmpty && !line.startsWith(':')) {
            // Log unexpected parse failures (ignore SSE comments which start with :)
            debugPrint('[ChatService] Failed to parse SSE line: ${line.substring(0, line.length.clamp(0, 100))}');
          }
        }
      }

      // Process any remaining buffer
      if (buffer.trim().isNotEmpty) {
        final event = StreamEvent.parse(buffer.trim());
        if (event != null) {
          yield event;
        }
      }

      debugPrint('[ChatService] Stream completed');
    } catch (e) {
      debugPrint('[ChatService] Stream error: $e');
      yield StreamEvent(
        type: StreamEventType.error,
        data: {'error': e.toString()},
      );
    }
  }

  /// Dispose resources
  void dispose() {
    _client.close();
  }
}

/// A session with its messages
class ChatSessionWithMessages {
  final ChatSession session;
  final List<ChatMessage> messages;

  const ChatSessionWithMessages({
    required this.session,
    required this.messages,
  });

  factory ChatSessionWithMessages.fromJson(Map<String, dynamic> json) {
    final session = ChatSession.fromJson(json);

    final messagesList = json['messages'] as List<dynamic>? ?? [];
    final messages = messagesList.map((m) {
      final msg = m as Map<String, dynamic>;
      return ChatMessage.fromJson({
        ...msg,
        'sessionId': session.id,
      });
    }).toList();

    return ChatSessionWithMessages(
      session: session,
      messages: messages,
    );
  }
}
