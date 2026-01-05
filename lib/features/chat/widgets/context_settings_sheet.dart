import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import '../models/context_file.dart';
import '../models/prompt_metadata.dart';
import '../providers/chat_providers.dart';

/// Bottom sheet for managing context settings mid-session
///
/// Allows users to:
/// - Toggle context files on/off
/// - See current project context (CLAUDE.md) and reload it
/// - Preview token counts
/// - Changes take effect on the next message
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
  late List<String> _selectedContexts;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _selectedContexts = List.from(widget.selectedContexts);
  }

  void _toggleContext(String contextPath) {
    setState(() {
      if (_selectedContexts.contains(contextPath)) {
        _selectedContexts.remove(contextPath);
      } else {
        _selectedContexts.add(contextPath);
      }
      _hasChanges = true;
    });
  }

  void _applyChanges() {
    widget.onContextsChanged(_selectedContexts);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final availableContextsAsync = ref.watch(availableContextsProvider);
    final metadata = widget.promptMetadata;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
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
                    Icons.tune,
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
                  // Current prompt metadata summary
                  if (metadata != null) ...[
                    _buildMetadataSummary(metadata, colorScheme),
                    const SizedBox(height: Spacing.md),
                  ],

                  // Project Context (CLAUDE.md) section
                  if (metadata?.workingDirectoryClaudeMd != null ||
                      widget.workingDirectory != null) ...[
                    _buildProjectContextSection(colorScheme),
                    const SizedBox(height: Spacing.md),
                  ],

                  // Context files section
                  _buildContextFilesSection(availableContextsAsync, colorScheme),

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
                            'Changes take effect on your next message',
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

  Widget _buildMetadataSummary(PromptMetadata metadata, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Prompt',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '~${_formatTokens(metadata.totalPromptTokens)} tokens',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Icon(
                Icons.description_outlined,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '${metadata.contextFiles.length} context file${metadata.contextFiles.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (metadata.contextTruncated) ...[
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                Icon(
                  Icons.warning_amber,
                  size: 14,
                  color: colorScheme.error,
                ),
                const SizedBox(width: 4),
                Text(
                  'Context was truncated due to token limit',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ],
            ),
          ],
        ],
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
              Icons.folder_special,
              size: 18,
              color: colorScheme.secondary,
            ),
            const SizedBox(width: Spacing.sm),
            Text(
              'Project Context',
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
                        '${widget.workingDirectory}/CLAUDE.md',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      Text(
                        'No project context',
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
                  tooltip: 'Reload CLAUDE.md',
                  iconSize: 20,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContextFilesSection(
    AsyncValue<List<ContextFile>> availableContextsAsync,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.library_books,
              size: 18,
              color: colorScheme.secondary,
            ),
            const SizedBox(width: Spacing.sm),
            Text(
              'Context Files',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        availableContextsAsync.when(
          data: (contexts) {
            if (contexts.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(Spacing.md),
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
                        'No context files found. Create markdown files in Chat/contexts/ to add personal context.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: contexts.map((ctx) {
                final isSelected = _selectedContexts.contains(ctx.path);
                return _ContextFileTile(
                  contextFile: ctx,
                  isSelected: isSelected,
                  onToggle: () => _toggleContext(ctx.path),
                );
              }).toList(),
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(Spacing.md),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (err, _) => Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: colorScheme.error),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    'Failed to load contexts: $err',
                    style: TextStyle(color: colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}k';
    }
    return tokens.toString();
  }
}

/// Individual context file tile with toggle
class _ContextFileTile extends StatelessWidget {
  final ContextFile contextFile;
  final bool isSelected;
  final VoidCallback onToggle;

  const _ContextFileTile({
    required this.contextFile,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Estimate tokens from file size (roughly 4 chars per token)
    final estimatedTokens = contextFile.size ~/ 4;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Material(
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.4)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.sm),
            child: Row(
              children: [
                Checkbox(
                  value: isSelected,
                  onChanged: (_) => onToggle(),
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contextFile.title.isNotEmpty ? contextFile.title : contextFile.filename,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      if (contextFile.description.isNotEmpty)
                        Text(
                          contextFile.description,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Text(
                  '~${_formatTokens(estimatedTokens)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}k';
    }
    return tokens.toString();
  }
}
