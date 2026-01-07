# Parachute Chat - Development Guide

**AI chat assistant that connects to Parachute Base server for Claude SDK integration.**

---

## Overview

Parachute Chat is a Flutter app that provides AI-powered chat with your knowledge vault. Unlike Parachute Daily (which runs standalone), Chat requires the Base server for AI features.

**Key Characteristics:**
- Requires Base server connection (`http://localhost:3333` by default)
- Sessions stored as markdown in `Chat/sessions/`
- Riverpod for state management
- SSE streaming for real-time AI responses

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        PARACHUTE CHAT                            │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    UI Layer (Screens)                     │   │
│  │  ChatScreen, SettingsScreen, VaultScreen                 │   │
│  └────────────────────────┬─────────────────────────────────┘   │
│                           │                                      │
│  ┌────────────────────────▼─────────────────────────────────┐   │
│  │                 State Layer (Riverpod)                    │   │
│  │  chatSessionProvider, messagesProvider, settingsProvider │   │
│  └────────────────────────┬─────────────────────────────────┘   │
│                           │                                      │
│  ┌────────────────────────▼─────────────────────────────────┐   │
│  │                  Service Layer                            │   │
│  │  ChatService (HTTP/SSE), FileSystemService (paths)       │   │
│  └────────────────────────┬─────────────────────────────────┘   │
│                           │                                      │
└───────────────────────────┼──────────────────────────────────────┘
                            │
                            ▼ HTTP/SSE (port 3333)
                   ┌─────────────────┐
                   │  BASE SERVER    │
                   └─────────────────┘
```

---

## Directory Structure

```
chat/lib/
├── main.dart                    # App entry point
├── core/                        # Shared infrastructure
│   ├── config/                  # App configuration
│   ├── constants/               # App-wide constants
│   ├── errors/                  # Error types
│   ├── models/                  # Shared models
│   ├── providers/               # Core Riverpod providers
│   ├── services/                # Core services
│   ├── theme/                   # Design tokens, themes
│   └── widgets/                 # Reusable widgets
│
└── features/                    # Feature modules
    ├── chat/                    # Main chat feature
    │   ├── models/              # ChatSession, ChatMessage
    │   ├── providers/           # Chat state providers
    │   ├── screens/             # ChatScreen
    │   ├── services/            # ChatService, LocalSessionReader
    │   └── widgets/             # MessageBubble, etc.
    │
    ├── settings/                # App settings
    │   ├── models/              # Settings models
    │   ├── screens/             # SettingsScreen
    │   ├── services/            # Settings persistence
    │   └── widgets/             # Settings sections
    │
    ├── context/                 # Personal context management
    │   ├── models/              # Context models
    │   ├── providers/           # Context state
    │   ├── services/            # Context loading
    │   └── widgets/             # Context UI
    │
    ├── vault/                   # Vault browsing
    │   ├── providers/           # Vault state
    │   ├── screens/             # VaultScreen
    │   └── widgets/             # File browser
    │
    ├── files/                   # File operations
    │   └── providers/           # File state
    │
    ├── recorder/                # Voice input (shared with Daily)
    │   ├── models/              # Recording models
    │   ├── providers/           # Recording state
    │   ├── services/            # Audio, transcription
    │   └── widgets/             # Recording UI
    │
    └── onboarding/              # First-run setup
        └── screens/             # Onboarding flow
```

---

## Key Files

| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry point, provider scope setup |
| `lib/features/chat/services/chat_service.dart` | HTTP/SSE communication with Base server |
| `lib/features/chat/providers/chat_providers.dart` | Main chat state management |
| `lib/features/chat/models/chat_session.dart` | Session model with messages |
| `lib/core/services/file_system_service.dart` | Vault paths, file operations |
| `lib/core/providers/backend_health_provider.dart` | Server connection status |

---

## State Management (Riverpod)

### Core Providers

```dart
// Server connection state
final backendHealthProvider = StreamProvider<BackendHealth>((ref) {
  return BackendHealthService.healthStream;
});

// Current chat session
final chatSessionProvider = StateNotifierProvider<ChatSessionNotifier, ChatSession?>((ref) {
  return ChatSessionNotifier(ref);
});

// Messages for current session
final messagesProvider = Provider<List<ChatMessage>>((ref) {
  return ref.watch(chatSessionProvider)?.messages ?? [];
});

// Session list from server
final sessionsProvider = FutureProvider<List<SessionSummary>>((ref) async {
  return ref.read(chatServiceProvider).listSessions();
});
```

### Provider Pattern

1. **Services** are created via `Provider` (singleton)
2. **UI State** uses `StateNotifierProvider` for mutations
3. **Async data** uses `FutureProvider` or `StreamProvider`
4. **Derived state** uses plain `Provider` with `ref.watch`

---

## Chat Flow

### Sending a Message

```
User types message
       │
       ▼
ChatScreen calls sendMessage()
       │
       ▼
ChatService.sendMessageStreaming()
       │
       ▼
POST /api/chat/stream (SSE)
       │
       ▼
Stream events: session → init → text → tool_use → done
       │
       ▼
ChatSessionNotifier updates state
       │
       ▼
UI rebuilds via Riverpod watch
```

### SSE Event Types

| Event | Purpose |
|-------|---------|
| `session` | Session ID and resume info |
| `init` | Available tools list |
| `model` | Model being used (e.g., `claude-opus-4-5-20250514`) |
| `text` | AI response text (streaming) |
| `thinking` | Extended thinking content (chain of thought) |
| `tool_use` | Tool being executed |
| `tool_result` | Tool execution result |
| `done` | Final response, session metadata |
| `aborted` | Stream stopped by user (graceful) |
| `session_unavailable` | SDK session couldn't be resumed |
| `error` | Error message |

---

## Data Paths

The Chat app uses these vault paths:

| Path | Contents |
|------|----------|
| `Chat/sessions/` | Chat session markdown files (flat structure) |
| `Chat/contexts/` | Personal context files |
| `Chat/assets/` | Generated images, audio |
| `CLAUDE.md` | System prompt override |

**Note:** Sessions use lightweight pointer architecture—markdown files contain only frontmatter metadata, with SDK JSONL files at `~/.claude/projects/` as the source of truth for message content.

Configured in `FileSystemService`:
```dart
// Default root: ~/Parachute/Chat/
static const String _defaultSessionsFolderName = 'sessions';
static const String _defaultAssetsFolderName = 'assets';
static const String _contextsFolderName = 'contexts';
```

---

## Getting Started

**Prerequisite:** The Base server must be running for Chat to work.

```bash
# Start Base server (from sibling directory)
cd ../base && ./parachute.sh start

# Then run Chat
cd ../chat
flutter pub get                 # Install dependencies
flutter run -d macos            # Run on macOS
flutter run -d android          # Run on Android
flutter analyze                 # Check for issues
flutter test                    # Run tests
```

Verify server is running: `curl http://localhost:3333/api/health`

---

## Server Communication

Uses the Base server's simplified 8-endpoint API.

### ChatService API Methods

```dart
// Send message with streaming response (POST /api/chat)
Stream<StreamEvent> streamChat({
  required String sessionId,
  required String message,
  String? systemPrompt,
  String? initialContext,
  String? priorConversation,
  String? continuedFrom,
});

// List sessions (GET /api/chat)
Future<List<ChatSession>> getSessions();

// Get session by ID with full messages (GET /api/chat/:id)
Future<ChatSessionWithMessages?> getSession(String sessionId);

// Delete session (DELETE /api/chat/:id)
Future<void> deleteSession(String sessionId);

// Module prompt (GET/PUT /api/modules/:mod/prompt)
Future<ModulePromptInfo> getModulePrompt({String module = 'chat'});
Future<void> saveModulePrompt(String content, {String module = 'chat'});
```

### Server URL Configuration

Default: `http://localhost:3333`

Change via Settings → AI Chat → Server URL

Stored in: `SharedPreferences` key `backendUrl`

---

## Adding Features

### New Chat Widget

1. Create widget in `lib/features/chat/widgets/`
2. Use `ref.watch` for reactive state
3. Access services via `ref.read(chatServiceProvider)`

### New Settings Section

1. Create widget in `lib/features/settings/widgets/`
2. Add to `SettingsScreen` build method
3. Use `SharedPreferences` for persistence

### New Provider

1. Define in appropriate `providers/` directory
2. Follow naming: `thingProvider` for state, `thingServiceProvider` for services
3. Document in this file

---

## Debugging

### Server Connection Issues

```dart
// Check backend health
ref.watch(backendHealthProvider).when(
  data: (health) => print('Server: ${health.isHealthy}'),
  loading: () => print('Checking...'),
  error: (e, _) => print('Error: $e'),
);
```

### Session State Issues

```dart
// Inspect current session
final session = ref.read(chatSessionProvider);
print('Session ID: ${session?.id}');
print('Messages: ${session?.messages.length}');
```

### Enable Debug Logging

```dart
// In ChatService
debugPrint('[ChatService] Sending: $message');
debugPrint('[ChatService] Response: $event');
```

---

## GitHub Repository

This is a standalone repository: [parachute-chat](https://github.com/OpenParachutePBC/parachute-chat)

**Related repos:**
- [parachute-base](https://github.com/OpenParachutePBC/parachute-base) - Backend server (required)
- [parachute-daily](https://github.com/OpenParachutePBC/parachute-daily) - Voice journaling (standalone)

---

**Last Updated:** January 7, 2026
