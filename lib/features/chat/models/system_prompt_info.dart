/// Information about a module's system prompt (from /api/modules/:mod/prompt)
class ModulePromptInfo {
  /// The current prompt content (from AGENTS.md or default)
  final String content;

  /// Whether AGENTS.md exists for this module
  final bool exists;

  /// The built-in default prompt
  final String defaultPrompt;

  const ModulePromptInfo({
    required this.content,
    required this.exists,
    required this.defaultPrompt,
  });

  factory ModulePromptInfo.fromJson(Map<String, dynamic> json) {
    return ModulePromptInfo(
      content: json['content'] as String? ?? '',
      exists: json['exists'] as bool? ?? false,
      defaultPrompt: json['defaultPrompt'] as String? ?? '',
    );
  }
}

/// Information about the built-in default system prompt
/// @deprecated Use ModulePromptInfo instead
class DefaultPromptInfo {
  /// The actual prompt content
  final String content;

  /// Whether this default is currently active (no AGENTS.md override)
  final bool isActive;

  /// Name of the override file if present (e.g., "AGENTS.md")
  final String? overrideFile;

  /// Description of what this prompt is
  final String description;

  const DefaultPromptInfo({
    required this.content,
    required this.isActive,
    this.overrideFile,
    this.description = '',
  });

  factory DefaultPromptInfo.fromJson(Map<String, dynamic> json) {
    return DefaultPromptInfo(
      content: json['content'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? true,
      overrideFile: json['overrideFile'] as String?,
      description: json['description'] as String? ?? '',
    );
  }
}

/// Information about the user's AGENTS.md file
/// @deprecated Use ModulePromptInfo instead
class AgentsMdInfo {
  /// The content of AGENTS.md (null if doesn't exist)
  final String? content;

  /// Path to the file
  final String? path;

  /// Whether the file exists
  final bool exists;

  const AgentsMdInfo({
    this.content,
    this.path,
    required this.exists,
  });

  factory AgentsMdInfo.fromJson(Map<String, dynamic> json) {
    return AgentsMdInfo(
      content: json['content'] as String?,
      path: json['path'] as String?,
      exists: json['content'] != null,
    );
  }
}
