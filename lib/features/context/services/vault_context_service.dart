import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:parachute_chat/core/services/file_system_service.dart';

/// Service for managing vault context files (AGENTS.md)
///
/// These files help orient the AI to understand:
/// - Its role as a thinking companion (not a coding assistant)
/// - The structure and contents of the vault
/// - Who the user is and what they care about
class VaultContextService {
  final FileSystemService _fileSystem;

  VaultContextService(this._fileSystem);

  // ============================================================
  // File Paths
  // ============================================================

  Future<String> get _agentsMdPath async {
    final root = await _fileSystem.getRootPath();
    return '$root/AGENTS.md';
  }

  // ============================================================
  // Initialization Check
  // ============================================================

  /// Check if vault context files exist
  Future<VaultContextStatus> checkStatus() async {
    final agentsPath = await _agentsMdPath;
    final agentsExists = await File(agentsPath).exists();

    return VaultContextStatus(
      agentsMdExists: agentsExists,
    );
  }

  /// Create default files if they don't exist
  Future<void> initializeDefaults() async {
    final status = await checkStatus();

    if (!status.agentsMdExists) {
      await _createDefaultAgentsMd();
    }
  }

  // ============================================================
  // AGENTS.md
  // ============================================================

  /// Load the AGENTS.md content
  Future<String?> loadAgentsMd() async {
    final path = await _agentsMdPath;
    return _fileSystem.readFileAsString(path);
  }

  /// Save updated AGENTS.md content
  Future<bool> saveAgentsMd(String content) async {
    final path = await _agentsMdPath;
    return _fileSystem.writeFileAsString(path, content);
  }

  Future<void> _createDefaultAgentsMd() async {
    final path = await _agentsMdPath;
    debugPrint('[VaultContextService] Creating default AGENTS.md');
    await _fileSystem.writeFileAsString(path, _defaultAgentsMd);
  }

  /// Create AGENTS.md with context from Claude memories
  ///
  /// Note: Claude memories are now stored in contexts/general-context.md
  /// AGENTS.md focuses on system orientation, not user context
  Future<void> createAgentsMdWithClaudeContext(String claudeMemoriesContext) async {
    // AGENTS.md now focuses on system orientation
    // User context (Claude memories) goes in contexts/general-context.md
    await _createDefaultAgentsMd();

    // Also ensure general-context.md is created with Claude memories
    if (claudeMemoriesContext.isNotEmpty) {
      final root = await _fileSystem.getRootPath();
      final contextsPath = '$root/contexts';
      await _fileSystem.ensureDirectoryExists(contextsPath);

      final generalContextPath = '$contextsPath/general-context.md';
      final content = '''# General Context

> Imported from your Claude conversations

$claudeMemoriesContext

---
*This context is automatically loaded for all chats.*
*Edit this file to update what the agent knows about you.*
''';

      await _fileSystem.writeFileAsString(generalContextPath, content);
      debugPrint('[VaultContextService] Created general-context.md with Claude memories');
    }
  }

  /// Initialize defaults with optional Claude memories context
  Future<void> initializeWithClaudeMemories(String? memoriesContext) async {
    final status = await checkStatus();

    if (!status.agentsMdExists) {
      if (memoriesContext != null && memoriesContext.isNotEmpty) {
        await createAgentsMdWithClaudeContext(memoriesContext);
      } else {
        await _createDefaultAgentsMd();
      }
    }
  }

  // ============================================================
  // Default File Contents
  // ============================================================

  static const String _defaultAgentsMd = '''# Parachute Vault Agent

You are the vault agent for Parachute - an open, local-first tool for connected thinking.

## Your Role

You are a **thinking partner and memory extension**, not primarily a coding assistant. Help the user:
- Think through ideas and problems
- Find and connect information across their vault
- Remember context from past conversations
- Surface relevant notes and patterns they might not see

## Vault Structure

This vault contains:

```
Daily/              # Daily journal entries with voice transcripts
  YYYY-MM-DD.md     # One file per day, includes recordings and reflections

assets/             # Audio files organized by month
  YYYY-MM/          # Monthly subfolders for recordings

agent-sessions/     # Chat conversation history
  {session-id}.md   # Searchable record of past conversations

contexts/           # User context (imported from Claude, etc.)
  general-context.md  # Core context about the user (auto-loaded)
  {project}.md        # Project-specific context (loaded on request)

.parachute/         # App data (search index, etc.)
  search.db         # Vector search index
```

## Your Context

Your core context about the user is loaded from `contexts/general-context.md`. This contains memories, preferences, and background imported from their previous AI conversations.

When working on specific topics, check `contexts/` for relevant project context files. Read them when the conversation would benefit from that context.

## Tools Available

- **Search (Glob, Grep)**: Find files and search content. Use these liberally to find relevant context before answering.
- **Read**: Look at specific files. Always prefer reading over guessing.
- **Write/Edit**: Help capture and refine ideas. Ask before major changes.
- **Bash**: Run commands when needed.
- **WebSearch/WebFetch**: Look things up online when helpful.

## How to Help

1. **Search first**: When asked about something, search the vault for relevant context before answering.
2. **Connect dots**: Surface connections between notes, past conversations, and ideas.
3. **Reference sources**: When you find relevant notes, mention them so the user can explore further.
4. **Be conversational**: This is a thinking partnership, not a formal assistant relationship.
5. **Ask good questions**: Help the user think through problems, don't just answer.

## Interaction Style

- Be concise but thoughtful
- Show reasoning when it helps clarify your thinking
- Ask clarifying questions when uncertain
- Suggest connections the user might not see
- Remember: you have access to their vault - use it
''';
}

/// Status of vault context files
class VaultContextStatus {
  final bool agentsMdExists;

  const VaultContextStatus({
    required this.agentsMdExists,
  });

  bool get isFullyInitialized => agentsMdExists;
  bool get needsSetup => !agentsMdExists;
}
