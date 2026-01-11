import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:parachute_chat/core/services/file_system_service.dart';

/// Service for managing vault context files (CLAUDE.md)
///
/// CLAUDE.md is auto-loaded by the Claude SDK when set as working directory.
/// This service manages the vault's root CLAUDE.md which provides:
/// - Role orientation (thinking companion, not just coding assistant)
/// - Vault structure documentation
/// - User context and preferences
class VaultContextService {
  final FileSystemService _fileSystem;

  VaultContextService(this._fileSystem);

  // ============================================================
  // File Paths
  // ============================================================

  Future<String> get _claudeMdPath async {
    final root = await _fileSystem.getRootPath();
    return '$root/CLAUDE.md';
  }

  // ============================================================
  // Initialization Check
  // ============================================================

  /// Check if vault context files exist
  Future<VaultContextStatus> checkStatus() async {
    final claudePath = await _claudeMdPath;
    final claudeExists = await File(claudePath).exists();

    return VaultContextStatus(
      claudeMdExists: claudeExists,
    );
  }

  /// Create default files if they don't exist
  Future<void> initializeDefaults() async {
    final status = await checkStatus();

    if (!status.claudeMdExists) {
      await _createDefaultClaudeMd();
    }
  }

  // ============================================================
  // CLAUDE.md
  // ============================================================

  /// Load the CLAUDE.md content
  Future<String?> loadClaudeMd() async {
    final path = await _claudeMdPath;
    return _fileSystem.readFileAsString(path);
  }

  /// Save updated CLAUDE.md content
  Future<bool> saveClaudeMd(String content) async {
    final path = await _claudeMdPath;
    return _fileSystem.writeFileAsString(path, content);
  }

  Future<void> _createDefaultClaudeMd() async {
    final path = await _claudeMdPath;
    debugPrint('[VaultContextService] Creating default CLAUDE.md');
    await _fileSystem.writeFileAsString(path, _defaultClaudeMd);
  }

  /// Create CLAUDE.md with context from Claude memories
  ///
  /// User context (Claude memories) goes in Chat/contexts/general-context.md
  /// CLAUDE.md focuses on system orientation
  Future<void> createClaudeMdWithContext(String claudeMemoriesContext) async {
    await _createDefaultClaudeMd();

    // Also ensure general-context.md is created with Claude memories
    if (claudeMemoriesContext.isNotEmpty) {
      final root = await _fileSystem.getRootPath();
      final contextsPath = '$root/Chat/contexts';
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

    if (!status.claudeMdExists) {
      if (memoriesContext != null && memoriesContext.isNotEmpty) {
        await createClaudeMdWithContext(memoriesContext);
      } else {
        await _createDefaultClaudeMd();
      }
    }
  }

  // ============================================================
  // Default File Contents
  // ============================================================

  static const String _defaultClaudeMd = '''# Parachute Vault

> Your extended mind - local-first, voice-first AI tooling for connected thinking

---

## Role

You are a **thinking partner and memory extension**, not just a coding assistant. Help the user:
- Think through ideas and problems
- Remember context from past conversations
- Explore topics and make connections
- Build software when needed

## Communication Style

- **Be conversational** - This is a thinking partnership
- **Ask good questions** - Help think through problems, don't just answer
- **Be direct** - Skip flattery, respond to what's actually being asked
- **Voice-aware** - Input may be voice transcripts (informal, may have errors)

## When to Search the Vault

Search past conversations and journals when:
- User asks for personalized recommendations
- User references past conversations or projects
- User asks about their own thoughts, ideas, or decisions
- You need context about preferences or history

Use web search for external/current information.

---

## Identity

@Chat/contexts/general-context.md

---

## Vault Structure

```
~/Parachute/
├── Daily/          # Voice journal entries
├── Chat/           # AI conversations
├── projects/       # Code projects
├── Coding/         # Other code work
├── Areas/          # Life areas
├── Writings/       # Written content
├── assets/         # Media files
├── .claude/        # Skills and agents
└── .parachute/     # System files
```

---

## Philosophy

This vault is part of **Parachute** - local-first, voice-first AI tooling.

**Core Principles:**
- **Local-First** - Data stays on your devices; you control what goes to the cloud
- **Voice-First** - More natural than typing; meets people where they think
- **Open & Interoperable** - Standard formats (markdown), works with Obsidian
- **Thoughtful AI** - Enhance thinking, don't replace it
''';
}

/// Status of vault context files
class VaultContextStatus {
  final bool claudeMdExists;

  const VaultContextStatus({
    required this.claudeMdExists,
  });

  bool get isFullyInitialized => claudeMdExists;
  bool get needsSetup => !claudeMdExists;
}
