/// Represents an Agent Skill that can be invoked by Claude.
/// Skills are stored in {vault}/.claude/skills/{name}/SKILL.md
class Skill {
  final String name;
  final String description;
  final String directory;
  final String path;
  final String? preview;
  final bool hasAllowedTools;
  final List<String>? allowedTools;

  // Full content (only populated when loading individual skill)
  final String? body;
  final String? fullContent;
  final Map<String, dynamic>? frontmatter;
  final List<String>? additionalFiles;

  Skill({
    required this.name,
    this.description = '',
    required this.directory,
    required this.path,
    this.preview,
    this.hasAllowedTools = false,
    this.allowedTools,
    this.body,
    this.fullContent,
    this.frontmatter,
    this.additionalFiles,
  });

  factory Skill.fromJson(Map<String, dynamic> json) {
    return Skill(
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      directory: json['directory'] as String,
      path: json['path'] as String,
      preview: json['preview'] as String?,
      hasAllowedTools: json['hasAllowedTools'] as bool? ?? false,
      allowedTools: (json['allowedTools'] as List<dynamic>?)?.cast<String>(),
      body: json['body'] as String?,
      fullContent: json['fullContent'] as String?,
      frontmatter: json['frontmatter'] as Map<String, dynamic>?,
      additionalFiles:
          (json['additionalFiles'] as List<dynamic>?)?.cast<String>(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'directory': directory,
      'path': path,
      if (preview != null) 'preview': preview,
      'hasAllowedTools': hasAllowedTools,
      if (allowedTools != null) 'allowedTools': allowedTools,
      if (body != null) 'body': body,
      if (fullContent != null) 'fullContent': fullContent,
      if (frontmatter != null) 'frontmatter': frontmatter,
      if (additionalFiles != null) 'additionalFiles': additionalFiles,
    };
  }

  /// Whether this skill has full content loaded
  bool get hasFullContent => body != null || fullContent != null;

  @override
  String toString() => 'Skill($name)';
}

/// Input for creating a new skill
class CreateSkillInput {
  final String name;
  final String? description;
  final String? content;
  final List<String>? allowedTools;

  CreateSkillInput({
    required this.name,
    this.description,
    this.content,
    this.allowedTools,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      if (content != null) 'content': content,
      if (allowedTools != null) 'allowedTools': allowedTools,
    };
  }
}
