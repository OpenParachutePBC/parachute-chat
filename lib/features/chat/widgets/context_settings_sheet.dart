import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import '../models/prompt_metadata.dart';
import 'context_folder_picker.dart';

/// Bottom sheet for managing context settings mid-session
///
/// Shows folder-based context selection with AGENTS.md hierarchy.
/// Users can select folders and the parent chain is automatically included.
class ContextSettingsSheet extends ConsumerStatefulWidget {
  final String? workingDirectory;
  final PromptMetadata? promptMetadata;
  final List<String> selectedContexts;
  final Function(List<String>) onContextsChanged;
  final VoidCallback? onReloadClaudeMd;

  const ContextSettingsSheet({
    super.key,
    this.workingDirectory,
    this.promptMetadata,
    required this.selectedContexts,
    required this.onContextsChanged,
    this.onReloadClaudeMd,
  });

  /// Shows the context settings sheet
  static Future<void> show(
    BuildContext context, {
    String? workingDirectory,
    PromptMetadata? promptMetadata,
    required List<String> selectedContexts,
    required Function(List<String>) onContextsChanged,
    VoidCallback? onReloadClaudeMd,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ContextSettingsSheet(
        workingDirectory: workingDirectory,
        promptMetadata: promptMetadata,
        selectedContexts: selectedContexts,
        onContextsChanged: onContextsChanged,
        onReloadClaudeMd: onReloadClaudeMd,
      ),
    );
  }

  @override
  ConsumerState<ContextSettingsSheet> createState() => _ContextSettingsSheetState();
}

class _ContextSettingsSheetState extends ConsumerState<ContextSettingsSheet> {
  late List<String> _selectedFolders;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    // Convert legacy context paths to folder paths if needed
    _selectedFolders = _extractFolderPaths(widget.selectedContexts);
    // If empty, default to root
    if (_selectedFolders.isEmpty) {
      _selectedFolders = [""];
    }
  }

  /// Extract folder paths from mixed context paths
  List<String> _extractFolderPaths(List<String> contexts) {
    final folders = <String>[];
    for (final ctx in contexts) {
      if (ctx.endsWith('.md')) {
        // Legacy: "Chat/contexts/file.md" -> skip (legacy file)
        // Or: "Projects/parachute/AGENTS.md" -> extract folder
        if (ctx.contains('AGENTS.md') || ctx.contains('CLAUDE.md')) {
          final folder = ctx
              .replaceAll('/AGENTS.md', '')
              .replaceAll('/CLAUDE.md', '')
              .replaceAll('AGENTS.md', '')
              .replaceAll('CLAUDE.md', '');
          folders.add(folder);
        }
      } else {
        // Already a folder path
        folders.add(ctx);
      }
    }
    return folders;
  }

  Future<void> _selectFolders() async {
    final selected = await showContextFolderPicker(
      context,
      initialSelection: _selectedFolders,
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedFolders = selected;
        _hasChanges = true;
      });
    }
  }

  void _applyChanges() {
    // Return folder paths directly (orchestrator now handles folders)
    widget.onContextsChanged(_selectedFolders);
    Navigator.of(context).pop();
  }

  String _displayPath(String path) {
    if (path.isEmpty) return 'Root';
    return path.split('/').last;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final metadata = widget.promptMetadata;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_special,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    'Context Settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  if (_hasChanges)
                    TextButton(
                      onPressed: _applyChanges,
                      child: const Text('Apply'),
                    ),
                ],
              ),
            ),

            const Divider(),

            // Content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  // Selected folders section
                  Row(
                    children: [
                      Icon(
                        Icons.folder_open,
                        size: 18,
                        color: colorScheme.secondary,
                      ),
                      const SizedBox(width: Spacing.sm),
                      Text(
                        'Context Folders',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    'Folders with AGENTS.md that provide context',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.md),

                  // Folder selection UI
                  _buildFolderSelector(colorScheme),

                  // Project Context (CLAUDE.md) section
                  if (metadata?.workingDirectoryClaudeMd != null ||
                      widget.workingDirectory != null) ...[
                    const SizedBox(height: Spacing.lg),
                    _buildProjectContextSection(colorScheme),
                  ],

                  const SizedBox(height: Spacing.lg),

                  // Info text
                  Container(
                    padding: const EdgeInsets.all(Spacing.sm),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            'Parent folders are automatically included. Changes take effect on your next message.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderSelector(ColorScheme colorScheme) {
    return InkWell(
      onTap: _selectFolders,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _selectedFolders.length > 1
                ? colorScheme.primary.withValues(alpha: 0.5)
                : Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Selected folders as chips
            Wrap(
              spacing: Spacing.xs,
              runSpacing: Spacing.xs,
              children: [
                ..._selectedFolders.map((path) {
                  final isRoot = path.isEmpty;
                  return Chip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isRoot ? Icons.home : Icons.folder,
                          size: 14,
                          color: colorScheme.onSurface,
                        ),
                        const SizedBox(width: 4),
                        Text(_displayPath(path)),
                      ],
                    ),
                    backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    labelStyle: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 12,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  );
                }),
                // Edit button
                ActionChip(
                  label: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 14),
                      SizedBox(width: 4),
                      Text('Edit'),
                    ],
                  ),
                  onPressed: _selectFolders,
                  backgroundColor: Colors.transparent,
                  side: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.5),
                  ),
                  labelStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectContextSection(ColorScheme colorScheme) {
    final metadata = widget.promptMetadata;
    final claudeMdPath = metadata?.workingDirectoryClaudeMd;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.code,
              size: 18,
              color: colorScheme.secondary,
            ),
            const SizedBox(width: Spacing.sm),
            Text(
              'Working Directory Context',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        Container(
          padding: const EdgeInsets.all(Spacing.sm),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (claudeMdPath != null)
                      Text(
                        claudeMdPath,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      )
                    else if (widget.workingDirectory != null)
                      Text(
                        '${widget.workingDirectory}/(AGENTS.md or CLAUDE.md)',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      Text(
                        'No working directory context',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    if (claudeMdPath != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Loaded automatically from working directory',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.onReloadClaudeMd != null && claudeMdPath != null)
                IconButton(
                  onPressed: () {
                    widget.onReloadClaudeMd!();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Project context will refresh on next message'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Reload working directory context',
                  iconSize: 20,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
