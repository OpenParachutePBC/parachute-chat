import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import '../models/context_file.dart';
import '../providers/chat_providers.dart';
import '../screens/context_file_viewer_screen.dart';
import 'directory_picker.dart';

/// Result from the new chat sheet
class NewChatConfig {
  final List<String> contexts;
  final String? workingDirectory;

  const NewChatConfig({
    required this.contexts,
    this.workingDirectory,
  });
}

/// Bottom sheet for configuring a new chat session
///
/// Shows available context files as selectable chips and
/// allows selecting a working directory.
class NewChatSheet extends ConsumerStatefulWidget {
  const NewChatSheet({super.key});

  /// Shows the new chat sheet and returns the configuration.
  /// Returns null if cancelled.
  static Future<NewChatConfig?> show(BuildContext context) {
    return showModalBottomSheet<NewChatConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NewChatSheet(),
    );
  }

  @override
  ConsumerState<NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends ConsumerState<NewChatSheet> {
  String? _workingDirectory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final contextsAsync = ref.watch(availableContextsProvider);
    final selectedContexts = ref.watch(selectedContextsProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.xl),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: Spacing.sm),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
              borderRadius: Radii.pill,
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Row(
              children: [
                Icon(
                  Icons.chat_outlined,
                  size: 24,
                  color: isDark ? BrandColors.nightForest : BrandColors.forest,
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  'New Chat',
                  style: TextStyle(
                    fontSize: TypographyTokens.titleLarge,
                    fontWeight: FontWeight.w600,
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Working Directory Section
                  _buildSectionHeader(
                    isDark,
                    'Working Directory',
                    'Where the AI agent will operate',
                  ),
                  const SizedBox(height: Spacing.sm),
                  _buildWorkingDirectorySelector(isDark),

                  const SizedBox(height: Spacing.xl),

                  // Context Files Section
                  _buildSectionHeader(
                    isDark,
                    'Context Files',
                    'Personal context to include in this chat',
                  ),
                  const SizedBox(height: Spacing.sm),

                  // Context chips
                  contextsAsync.when(
                    data: (contexts) {
                      if (contexts.isEmpty) {
                        return _buildEmptyContexts(isDark);
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: Spacing.sm,
                            runSpacing: Spacing.sm,
                            children: contexts.map((ctx) {
                              final isSelected =
                                  selectedContexts.contains(ctx.path);
                              return _ContextChip(
                                contextFile: ctx,
                                isSelected: isSelected,
                                onTap: () =>
                                    _toggleContext(ref, ctx.path, isSelected),
                                onEdit: () => _editContext(ctx),
                                isDark: isDark,
                              );
                            }).toList(),
                          ),
                        ],
                      );
                    },
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(Spacing.md),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (e, _) => _buildContextError(isDark),
                  ),
                ],
              ),
            ),
          ),

          const Divider(height: 1),

          // Start Chat button
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    NewChatConfig(
                      contexts: selectedContexts,
                      workingDirectory: _workingDirectory,
                    ),
                  ),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Start Chat'),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        isDark ? BrandColors.nightForest : BrandColors.forest,
                    padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(bool isDark, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: TypographyTokens.labelMedium,
            fontWeight: FontWeight.w600,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: TypographyTokens.bodySmall,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
        ),
      ],
    );
  }

  Widget _buildWorkingDirectorySelector(bool isDark) {
    final hasDirectory = _workingDirectory != null && _workingDirectory!.isNotEmpty;

    return InkWell(
      onTap: () => _selectWorkingDirectory(),
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: isDark
              ? BrandColors.nightSurfaceElevated
              : BrandColors.stone.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: hasDirectory
                ? (isDark ? BrandColors.nightForest : BrandColors.forest)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasDirectory ? Icons.folder_open : Icons.folder_outlined,
              size: 20,
              color: hasDirectory
                  ? (isDark ? BrandColors.nightForest : BrandColors.forest)
                  : (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                hasDirectory ? _workingDirectory! : 'Default (Chat folder)',
                style: TextStyle(
                  fontSize: TypographyTokens.bodyMedium,
                  color: hasDirectory
                      ? (isDark ? BrandColors.nightText : BrandColors.charcoal)
                      : (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood),
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectWorkingDirectory() async {
    final selected = await showDirectoryPicker(
      context,
      initialPath: _workingDirectory,
    );

    if (selected != null && mounted) {
      setState(() {
        // Empty string means vault root, which we treat as "no custom directory"
        _workingDirectory = selected.isEmpty ? null : selected;
      });
    }
  }

  void _toggleContext(WidgetRef ref, String path, bool isCurrentlySelected) {
    final current = ref.read(selectedContextsProvider);
    if (isCurrentlySelected) {
      ref.read(selectedContextsProvider.notifier).state =
          current.where((p) => p != path).toList();
    } else {
      ref.read(selectedContextsProvider.notifier).state = [...current, path];
    }
  }

  void _editContext(ContextFile ctx) {
    // Use the new ContextFileViewerScreen which reads/writes via API
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ContextFileViewerScreen(contextFile: ctx),
      ),
    );
  }

  Widget _buildEmptyContexts(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated
            : BrandColors.stone.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'No context files found. Add .md files to Chat/contexts/ to include personal context.',
              style: TextStyle(
                fontSize: TypographyTokens.bodySmall,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextError(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: BrandColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: BrandColors.error),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'Could not load context files',
              style: TextStyle(
                fontSize: TypographyTokens.bodySmall,
                color: BrandColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextChip extends StatelessWidget {
  final ContextFile contextFile;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final bool isDark;

  const _ContextChip({
    required this.contextFile,
    required this.isSelected,
    required this.onTap,
    this.onEdit,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onEdit,
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(contextFile.title),
            if (contextFile.isDefault) ...[
              const SizedBox(width: Spacing.xs),
              Icon(
                Icons.star,
                size: 14,
                color: isSelected ? Colors.white : BrandColors.warning,
              ),
            ],
            // Edit indicator
            if (onEdit != null) ...[
              const SizedBox(width: Spacing.xs),
              Icon(
                Icons.edit_outlined,
                size: 12,
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.7)
                    : (isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood),
              ),
            ],
          ],
        ),
        selected: isSelected,
        onSelected: (_) => onTap(),
        selectedColor: isDark ? BrandColors.nightForest : BrandColors.forest,
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          color: isSelected
              ? Colors.white
              : (isDark ? BrandColors.nightText : BrandColors.charcoal),
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
        backgroundColor: isDark
            ? BrandColors.nightSurfaceElevated
            : BrandColors.stone.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(
            color: isSelected
                ? (isDark ? BrandColors.nightForest : BrandColors.forest)
                : Colors.transparent,
          ),
        ),
      ),
    );
  }
}
