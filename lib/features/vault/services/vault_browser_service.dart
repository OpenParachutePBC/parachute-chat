import 'package:flutter/foundation.dart';
import 'package:parachute_chat/features/chat/services/chat_service.dart';
import 'package:parachute_chat/features/chat/models/vault_entry.dart';

/// Service for browsing the vault using the Base server API
///
/// This provides vault browsing capabilities through the server's
/// /api/ls, /api/read, and /api/write endpoints, rather than
/// direct local file access.
class VaultBrowserService {
  final ChatService _chatService;

  VaultBrowserService(this._chatService);

  /// List contents of a directory in the vault
  ///
  /// [relativePath] - Path relative to vault root (e.g., "", "Chat", "Daily")
  /// Returns entries sorted with directories first, then files alphabetically
  Future<List<VaultEntry>> listDirectory(String relativePath) async {
    try {
      debugPrint('[VaultBrowserService] Listing directory: "$relativePath"');
      final entries = await _chatService.listDirectory(path: relativePath);

      // Sort: directories first, then alphabetically by name
      entries.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      debugPrint('[VaultBrowserService] Found ${entries.length} entries');
      return entries;
    } catch (e) {
      debugPrint('[VaultBrowserService] Error listing directory: $e');
      rethrow;
    }
  }

  /// Read file content from the vault
  ///
  /// [relativePath] - Path relative to vault root
  /// Returns the file content, or null if file doesn't exist
  Future<VaultFileContent?> readFile(String relativePath) async {
    try {
      debugPrint('[VaultBrowserService] Reading file: "$relativePath"');
      final content = await _chatService.readFile(relativePath);
      if (content != null) {
        debugPrint('[VaultBrowserService] Read ${content.content.length} chars');
      }
      return content;
    } catch (e) {
      debugPrint('[VaultBrowserService] Error reading file: $e');
      rethrow;
    }
  }

  /// Write content to a file in the vault
  ///
  /// [relativePath] - Path relative to vault root
  /// [content] - The content to write
  Future<void> writeFile(String relativePath, String content) async {
    try {
      debugPrint('[VaultBrowserService] Writing file: "$relativePath" (${content.length} chars)');
      await _chatService.writeFile(relativePath, content);
      debugPrint('[VaultBrowserService] File written successfully');
    } catch (e) {
      debugPrint('[VaultBrowserService] Error writing file: $e');
      rethrow;
    }
  }

  /// Get the parent path of a given path
  ///
  /// Returns empty string if already at root
  String getParentPath(String path) {
    if (path.isEmpty) return '';

    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';

    parts.removeLast();
    return parts.join('/');
  }

  /// Check if the given path is at the vault root
  bool isAtRoot(String path) {
    return path.isEmpty || path == '/';
  }

  /// Get the folder name from a path
  String getFolderName(String path) {
    if (path.isEmpty) return 'Vault';
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? 'Vault' : parts.last;
  }

  /// Get a display-friendly version of the path
  String getDisplayPath(String path) {
    if (path.isEmpty) return '~/Parachute';
    return '~/Parachute/$path';
  }

  /// Check if a file is a text file that can be edited
  bool isTextFile(String name) {
    final ext = name.toLowerCase().split('.').last;
    const textExtensions = {
      // Markdown and documentation
      'md', 'markdown', 'txt', 'text',
      // Code files
      'dart', 'py', 'js', 'ts', 'jsx', 'tsx', 'json', 'yaml', 'yml',
      'html', 'css', 'scss', 'sass', 'less',
      'sh', 'bash', 'zsh', 'fish',
      'c', 'cpp', 'h', 'hpp', 'java', 'kt', 'swift', 'go', 'rs', 'rb',
      // Config files
      'toml', 'ini', 'cfg', 'conf', 'env', 'properties',
      'gitignore', 'gitattributes', 'editorconfig',
      // Other text formats
      'csv', 'tsv', 'xml', 'svg', 'log',
    };

    // Also check for common dotfiles without extensions
    final lowerName = name.toLowerCase();
    const dotFiles = {
      '.gitignore', '.gitattributes', '.editorconfig',
      '.env', '.env.local', '.env.development', '.env.production',
      'dockerfile', 'makefile', 'cmakelists.txt',
    };

    return textExtensions.contains(ext) || dotFiles.contains(lowerName);
  }

  /// Check if a file is a markdown file
  bool isMarkdownFile(String name) {
    final ext = name.toLowerCase().split('.').last;
    return ext == 'md' || ext == 'markdown';
  }

  /// Get the file type for display purposes
  String getFileType(String name) {
    if (isMarkdownFile(name)) return 'Markdown';

    final ext = name.toLowerCase().split('.').last;
    switch (ext) {
      case 'dart': return 'Dart';
      case 'py': return 'Python';
      case 'js': return 'JavaScript';
      case 'ts': return 'TypeScript';
      case 'json': return 'JSON';
      case 'yaml':
      case 'yml': return 'YAML';
      case 'txt': return 'Text';
      case 'sh':
      case 'bash': return 'Shell';
      case 'html': return 'HTML';
      case 'css': return 'CSS';
      case 'xml': return 'XML';
      case 'csv': return 'CSV';
      case 'log': return 'Log';
      default: return ext.toUpperCase();
    }
  }
}
