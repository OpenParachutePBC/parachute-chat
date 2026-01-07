import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'context_folder_picker.dart';
import 'directory_picker.dart';

/// Result from the new chat sheet
class NewChatConfig {
  /// Selected context folder paths (e.g., ["", "Projects/parachute"])
  final List<String> contextFolders;

  /// Optional working directory for file operations
  final String? workingDirectory;

  const NewChatConfig({
    required this.contextFolders,
    this.workingDirectory,
  });

  /// Legacy getter for backwards compatibility
  List<String> get contexts => contextFolders;
}

/// Bottom sheet for configuring a new chat session
///
/// Primary flow: Select context folders (AGENTS.md hierarchy)
/// Secondary: Optionally set a working directory for file operations
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
  late List<String> _selectedFolders;
  String? _workingDirectory;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    // Default to root context only
    _selectedFolders = [""];
  }

  Future<void> _selectContextFolders() async {
    final selected = await showContextFolderPicker(
      context,
      initialSelection: _selectedFolders,
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedFolders = selected;
      });
    }
  }

  String _displayPath(String path) {
    if (path.isEmpty) return 'Root';
    // Show just the last folder name for brevity
    return path.split('/').last;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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

          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Context Folders Section
                  _buildSectionHeader(
                    isDark,
                    'Context',
                    'Select folders with AGENTS.md to include in this conversation',
                  ),
                  const SizedBox(height: Spacing.sm),

                  // Context folder chips with edit button
                  _buildContextFolderSelector(isDark),

                  const SizedBox(height: Spacing.lg),

                  // Advanced Options (collapsed by default)
                  _buildAdvancedSection(isDark),
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
                      contextFolders: _selectedFolders,
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

  Widget _buildContextFolderSelector(bool isDark) {
    return InkWell(
      onTap: _selectContextFolders,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: isDark
              ? BrandColors.nightSurfaceElevated
              : BrandColors.stone.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: _selectedFolders.length > 1
                ? (isDark ? BrandColors.nightForest : BrandColors.forest)
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
                          color:
                              isDark ? BrandColors.nightText : BrandColors.charcoal,
                        ),
                        const SizedBox(width: Spacing.xs),
                        Text(_displayPath(path)),
                      ],
                    ),
                    backgroundColor: isDark
                        ? BrandColors.nightForest.withValues(alpha: 0.2)
                        : BrandColors.forest.withValues(alpha: 0.1),
                    labelStyle: TextStyle(
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                      fontSize: TypographyTokens.bodySmall,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  );
                }),
                // Add more button
                ActionChip(
                  label: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 14),
                      SizedBox(width: 4),
                      Text('Edit'),
                    ],
                  ),
                  onPressed: _selectContextFolders,
                  backgroundColor: Colors.transparent,
                  side: BorderSide(
                    color: isDark
                        ? BrandColors.nightTextSecondary.withValues(alpha: 0.5)
                        : BrandColors.driftwood.withValues(alpha: 0.5),
                  ),
                  labelStyle: TextStyle(
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                    fontSize: TypographyTokens.bodySmall,
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

  Widget _buildAdvancedSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle button
        InkWell(
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          borderRadius: BorderRadius.circular(Radii.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: Row(
              children: [
                Icon(
                  _showAdvanced ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                ),
                const SizedBox(width: Spacing.xs),
                Text(
                  'Advanced Options',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelMedium,
                    color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Collapsible content
        if (_showAdvanced) ...[
          const SizedBox(height: Spacing.md),
          _buildSectionHeader(
            isDark,
            'Working Directory',
            'Where the AI can read/write files and run commands',
          ),
          const SizedBox(height: Spacing.sm),
          _buildWorkingDirectorySelector(isDark),
        ],
      ],
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
                hasDirectory ? _workingDirectory! : 'Default (Vault root)',
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
}
