# Chat

AI chat interface. Requires Base server running (`./parachute.sh start` in base/).

**Repository**: https://github.com/OpenParachutePBC/parachute-chat

---

## Architecture

```
UI (Screens) → Providers (Riverpod) → Services → Base Server (SSE)
                                          ↓
                                   ~/Parachute/Chat/
```

**Key pieces:**
- `lib/features/chat/services/chat_service.dart` - HTTP/SSE to Base
- `lib/features/chat/providers/chat_providers.dart` - Main chat state
- `lib/core/services/file_system_service.dart` - Vault paths

**Vault paths:**
- `Chat/sessions/` - Session pointer files (metadata only)
- `Chat/contexts/` - Personal context files
- `CLAUDE.md` - System prompt override

**Pointer architecture:** Session markdown files contain frontmatter only. The SDK JSONL files at `~/.claude/projects/` are the source of truth for message content.

---

## Conventions

### Provider types (when to use which)

| Type | Use for | Example |
|------|---------|---------|
| `Provider<T>` | Singleton services | `chatServiceProvider` |
| `FutureProvider<T>` | Async initialization | `sessionsFutureProvider` |
| `StateNotifierProvider` | Mutable state with methods | `chatSessionProvider` |
| `StreamProvider` | Reactive streams | `backendHealthProvider` |
| `StateProvider` | Simple UI state | `selectedSessionProvider` |

### Provider patterns

```dart
// Service provider with cleanup
final myServiceProvider = Provider<MyService>((ref) {
  final service = MyService();
  ref.onDispose(() => service.dispose());
  return service;
});

// Async service initialization
final myServiceFutureProvider = FutureProvider<MyService>((ref) async {
  final dep = ref.watch(otherServiceProvider);
  return await MyService.create(dep);
});

// State with notifier
final myStateProvider = StateNotifierProvider<MyNotifier, MyState>((ref) {
  return MyNotifier(ref);
});
```

### Service patterns

```dart
// Factory constructor for async init
class MyService {
  MyService._({required this.config});

  static Future<MyService> create() async {
    final config = await loadConfig();
    return MyService._(config: config);
  }
}
```

### Debug logging
```dart
debugPrint('[ClassName] message');
```

### Adding a feature
1. Create directory in `lib/features/<feature>/`
2. Add models, providers, services, screens, widgets subdirectories as needed
3. Simple features: one `<feature>_providers.dart` file
4. Complex features: multiple provider files by concern

---

## Gotchas

- Chat will show "disconnected" if Base server isn't running
- SSE events stream in order: `session` → `init` → `model` → `text`/`tool_use` → `done`
- The `chat_providers.dart` file is large (~2000 lines) - consider splitting if adding major features
- Session deletion requires deleting both SQLite record (via API) and local pointer file
