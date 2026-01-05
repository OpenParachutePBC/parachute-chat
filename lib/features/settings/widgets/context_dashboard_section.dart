import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/features/chat/models/context_file.dart';
import 'package:parachute_chat/features/chat/providers/chat_providers.dart';
import 'package:parachute_chat/features/chat/screens/context_file_viewer_screen.dart';
import 'package:parachute_chat/features/chat/services/chat_service.dart';
import './settings_section_header.dart';

/// Context Dashboard section showing context files health and curator activity
///
/// Displays:
/// - Summary stats (total facts, history entries, context files)
/// - List of context files with metadata
/// - Recent curator activity/updates
class ContextDashboardSection extends ConsumerWidget {
  const ContextDashboardSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final contextFilesAsync = ref.watch(contextFilesInfoProvider);
    final curatorActivityAsync = ref.watch(curatorActivityProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Context Dashboard',
          icon: Icons.psychology,
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          'Your personal context helps the AI understand you better. '
          'The curator automatically updates these files as you chat.',
          style: TextStyle(
            fontSize: TypographyTokens.bodyMedium,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
        ),
        const SizedBox(height: Spacing.lg),

        // Summary stats
        contextFilesAsync.when(
          data: (info) => _buildSummaryStats(context, isDark, info),
          loading: () => _buildLoadingCard(isDark),
          error: (e, _) => _buildErrorCard(isDark, 'Failed to load context files'),
        ),

        const SizedBox(height: Spacing.lg),

        // Context files list
        const SettingsSubsectionHeader(
          title: 'Context Files',
          subtitle: 'Tap to view, long-press to edit',
        ),
        const SizedBox(height: Spacing.md),

        contextFilesAsync.when(
          data: (info) => _buildContextFilesList(context, ref, isDark, info),
          loading: () => _buildLoadingCard(isDark),
          error: (e, _) => _buildErrorCard(isDark, 'Could not load context files'),
        ),

        const SizedBox(height: Spacing.xl),

        // Recent curator activity
        const SettingsSubsectionHeader(
          title: 'Recent Curator Activity',
          subtitle: 'What the AI has learned about you',
        ),
        const SizedBox(height: Spacing.md),

        curatorActivityAsync.when(
          data: (activity) => _buildCuratorActivity(context, isDark, activity),
          loading: () => _buildLoadingCard(isDark),
          error: (e, _) => _buildEmptyActivity(isDark),
        ),

        const SizedBox(height: Spacing.lg),
      ],
    );
  }

  Widget _buildSummaryStats(BuildContext context, bool isDark, ContextFilesInfo info) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [BrandColors.nightForest.withValues(alpha: 0.2), BrandColors.nightTurquoise.withValues(alpha: 0.1)]
              : [BrandColors.forest.withValues(alpha: 0.1), BrandColors.turquoise.withValues(alpha: 0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
          color: isDark ? BrandColors.nightForest : BrandColors.forest,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.description_outlined,
                  value: info.files.length.toString(),
                  label: 'Context Files',
                  color: isDark ? BrandColors.nightForest : BrandColors.forest,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: _StatCard(
                  icon: Icons.check_circle_outline,
                  value: info.totalFacts.toString(),
                  label: 'Facts',
                  color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: _StatCard(
                  icon: Icons.history,
                  value: info.totalHistoryEntries.toString(),
                  label: 'History',
                  color: BrandColors.warning,
                  isDark: isDark,
                ),
              ),
            ],
          ),
          if (info.files.isEmpty) ...[
            const SizedBox(height: Spacing.md),
            Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightSurfaceElevated
                    : BrandColors.softWhite,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 20,
                    color: BrandColors.warning,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'Import your Claude history to get started with context files!',
                      style: TextStyle(
                        fontSize: TypographyTokens.bodySmall,
                        color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContextFilesList(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    ContextFilesInfo info,
  ) {
    if (info.files.isEmpty) {
      return _buildEmptyContextFiles(isDark);
    }

    return Column(
      children: info.files.map((file) {
        return _ContextFileCard(
          file: file,
          isDark: isDark,
          onTap: () => _openContextFile(context, ref, file),
        );
      }).toList(),
    );
  }

  void _openContextFile(BuildContext context, WidgetRef ref, ContextFileMetadata file) {
    // Create a ContextFile from metadata to use with existing viewer
    final contextFile = ContextFile(
      path: file.path,
      filename: file.path.split('/').last,
      title: file.name,
      description: file.description,
      isDefault: file.name.toLowerCase().contains('general'),
      size: 0, // Not available from metadata
      modified: file.lastModified ?? DateTime.now(),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ContextFileViewerScreen(contextFile: contextFile),
      ),
    );
  }

  Widget _buildEmptyContextFiles(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated
            : BrandColors.stone.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: isDark
              ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
              : BrandColors.driftwood.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 48,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'No context files yet',
            style: TextStyle(
              fontSize: TypographyTokens.titleMedium,
              fontWeight: FontWeight.w600,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Context files help the AI remember important information about you. '
            'Import your Claude chat history or start chatting to build context.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: TypographyTokens.bodySmall,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCuratorActivity(
    BuildContext context,
    bool isDark,
    CuratorActivityInfo activity,
  ) {
    if (activity.recentUpdates.isEmpty) {
      return _buildEmptyActivity(isDark);
    }

    return Column(
      children: [
        // Last activity timestamp
        if (activity.lastActivityAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 14,
                  color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                ),
                const SizedBox(width: Spacing.xs),
                Text(
                  'Last update: ${_formatTimestamp(activity.lastActivityAt!)}',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  ),
                ),
              ],
            ),
          ),

        // Recent updates
        ...activity.recentUpdates.take(5).map((update) {
          return _CuratorUpdateCard(update: update, isDark: isDark);
        }),

        // Modified files summary
        if (activity.contextFilesModified.isNotEmpty) ...[
          const SizedBox(height: Spacing.md),
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: isDark
                  ? BrandColors.nightSurfaceElevated
                  : BrandColors.stone.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.edit_note,
                  size: 18,
                  color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    'Files updated: ${activity.contextFilesModified.join(", ")}',
                    style: TextStyle(
                      fontSize: TypographyTokens.bodySmall,
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyActivity(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated
            : BrandColors.stone.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome,
            size: 24,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No curator activity yet',
                  style: TextStyle(
                    fontSize: TypographyTokens.bodyMedium,
                    fontWeight: FontWeight.w600,
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'As you chat, the curator learns and updates your context files automatically.',
                  style: TextStyle(
                    fontSize: TypographyTokens.bodySmall,
                    color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated
            : BrandColors.stone.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildErrorCard(bool isDark, String message) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: BrandColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: BrandColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: BrandColors.error),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: BrandColors.error,
                fontSize: TypographyTokens.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) {
      return 'just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${dt.month}/${dt.day}/${dt.year}';
    }
  }
}

/// Small stat card for the summary section
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final bool isDark;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated
            : BrandColors.softWhite,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: Spacing.xs),
          Text(
            value,
            style: TextStyle(
              fontSize: TypographyTokens.headlineMedium,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: TypographyTokens.labelSmall,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
          ),
        ],
      ),
    );
  }
}

/// Card for displaying a single context file
class _ContextFileCard extends StatelessWidget {
  final ContextFileMetadata file;
  final bool isDark;
  final VoidCallback onTap;

  const _ContextFileCard({
    required this.file,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: isDark
                ? BrandColors.nightSurfaceElevated
                : BrandColors.softWhite,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: file.isNativeFormat
                  ? (isDark ? BrandColors.nightForest : BrandColors.forest).withValues(alpha: 0.3)
                  : (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood).withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(Spacing.sm),
                decoration: BoxDecoration(
                  color: file.isNativeFormat
                      ? (isDark ? BrandColors.nightForest : BrandColors.forest).withValues(alpha: 0.1)
                      : (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Icon(
                  file.isNativeFormat ? Icons.psychology : Icons.description,
                  size: 20,
                  color: file.isNativeFormat
                      ? (isDark ? BrandColors.nightForest : BrandColors.forest)
                      : (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood),
                ),
              ),
              const SizedBox(width: Spacing.md),

              // File info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: TextStyle(
                        fontSize: TypographyTokens.bodyMedium,
                        fontWeight: FontWeight.w600,
                        color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Row(
                      children: [
                        _MetaBadge(
                          icon: Icons.check_circle_outline,
                          value: '${file.factsCount} facts',
                          isDark: isDark,
                        ),
                        const SizedBox(width: Spacing.sm),
                        _MetaBadge(
                          icon: Icons.history,
                          value: '${file.historyCount} history',
                          isDark: isDark,
                        ),
                        if (file.focusCount > 0) ...[
                          const SizedBox(width: Spacing.sm),
                          _MetaBadge(
                            icon: Icons.flag_outlined,
                            value: '${file.focusCount} focus',
                            isDark: isDark,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Native format badge
              if (file.isNativeFormat)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: Spacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: (isDark ? BrandColors.nightForest : BrandColors.forest).withValues(alpha: 0.1),
                    borderRadius: Radii.pill,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified,
                        size: 12,
                        color: isDark ? BrandColors.nightForest : BrandColors.forest,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Native',
                        style: TextStyle(
                          fontSize: TypographyTokens.labelSmall,
                          color: isDark ? BrandColors.nightForest : BrandColors.forest,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(width: Spacing.sm),
              Icon(
                Icons.chevron_right,
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small metadata badge
class _MetaBadge extends StatelessWidget {
  final IconData icon;
  final String value;
  final bool isDark;

  const _MetaBadge({
    required this.icon,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
        ),
        const SizedBox(width: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: TypographyTokens.labelSmall,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
        ),
      ],
    );
  }
}

/// Card for displaying a curator update
class _CuratorUpdateCard extends StatelessWidget {
  final CuratorUpdate update;
  final bool isDark;

  const _CuratorUpdateCard({
    required this.update,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated
            : BrandColors.softWhite,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: isDark
              ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
              : BrandColors.stone,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Actions taken
          Wrap(
            spacing: Spacing.xs,
            runSpacing: Spacing.xs,
            children: update.actions.map((action) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: (isDark ? BrandColors.nightTurquoise : BrandColors.turquoise).withValues(alpha: 0.1),
                  borderRadius: Radii.pill,
                ),
                child: Text(
                  action,
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoiseDeep,
                  ),
                ),
              );
            }).toList(),
          ),

          // Reasoning (if available)
          if (update.reasoning != null && update.reasoning!.isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              update.reasoning!,
              style: TextStyle(
                fontSize: TypographyTokens.bodySmall,
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // New title (if title was updated)
          if (update.newTitle != null) ...[
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Icon(
                  Icons.title,
                  size: 14,
                  color: isDark ? BrandColors.nightForest : BrandColors.forest,
                ),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: Text(
                    'New title: ${update.newTitle}',
                    style: TextStyle(
                      fontSize: TypographyTokens.bodySmall,
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
