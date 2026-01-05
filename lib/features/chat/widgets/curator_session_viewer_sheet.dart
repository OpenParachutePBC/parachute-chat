import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import '../models/curator_session.dart';
import '../providers/chat_providers.dart';

/// Bottom sheet showing curator session activity
///
/// Displays:
/// - Curator session info (last run, context files tracked)
/// - Recent task history with status and results
/// - Manual trigger button for testing
class CuratorSessionViewerSheet extends ConsumerStatefulWidget {
  final String sessionId;

  const CuratorSessionViewerSheet({
    super.key,
    required this.sessionId,
  });

  /// Shows the curator session viewer sheet
  static Future<void> show(BuildContext context, String sessionId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CuratorSessionViewerSheet(sessionId: sessionId),
    );
  }

  @override
  ConsumerState<CuratorSessionViewerSheet> createState() =>
      _CuratorSessionViewerSheetState();
}

class _CuratorSessionViewerSheetState
    extends ConsumerState<CuratorSessionViewerSheet> {
  bool _isTriggering = false;
  CuratorTask? _selectedTask;

  /// Format a DateTime to a readable string
  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final amPm = local.hour >= 12 ? 'PM' : 'AM';
    final minute = local.minute.toString().padLeft(2, '0');
    return '${months[local.month - 1]} ${local.day}, $hour:$minute $amPm';
  }

  String _formatDateWithSeconds(DateTime dt) {
    final local = dt.toLocal();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final amPm = local.hour >= 12 ? 'PM' : 'AM';
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '${months[local.month - 1]} ${local.day}, $hour:$minute:$second $amPm';
  }

  Future<void> _triggerCurator() async {
    setState(() => _isTriggering = true);
    try {
      final trigger = ref.read(triggerCuratorProvider);
      await trigger(widget.sessionId);
      // Refresh the curator info
      ref.invalidate(curatorInfoProvider(widget.sessionId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error triggering curator: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTriggering = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final curatorInfoAsync = ref.watch(curatorInfoProvider(widget.sessionId));

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
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
                  Icons.auto_fix_high,
                  size: 24,
                  color: isDark ? BrandColors.nightForest : BrandColors.forest,
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  _selectedTask != null ? 'Task Details' : 'Curator Activity',
                  style: TextStyle(
                    fontSize: TypographyTokens.titleLarge,
                    fontWeight: FontWeight.w600,
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
                const Spacer(),
                if (_selectedTask != null)
                  IconButton(
                    onPressed: () => setState(() => _selectedTask = null),
                    icon: Icon(
                      Icons.arrow_back,
                      color: isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood,
                    ),
                    tooltip: 'Back to list',
                  ),
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
            child: curatorInfoAsync.when(
              data: (info) => _selectedTask != null
                  ? _buildTaskDetailView(isDark, _selectedTask!)
                  : _buildMainView(isDark, info),
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(Spacing.xl),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.xl),
                  child: Text(
                    'Error loading curator info:\n$e',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainView(bool isDark, CuratorInfo info) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Curator Status Card
          _buildStatusCard(isDark, info),

          const SizedBox(height: Spacing.lg),

          // Manual Trigger Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isTriggering ? null : _triggerCurator,
              icon: _isTriggering
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_isTriggering ? 'Running...' : 'Trigger Curator'),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    isDark ? BrandColors.nightForest : BrandColors.forest,
                side: BorderSide(
                  color: isDark ? BrandColors.nightForest : BrandColors.forest,
                ),
              ),
            ),
          ),

          const SizedBox(height: Spacing.xl),

          // Task History Section
          Text(
            'Recent Activity',
            style: TextStyle(
              fontSize: TypographyTokens.titleMedium,
              fontWeight: FontWeight.w600,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
          ),
          const SizedBox(height: Spacing.md),

          if (info.recentTasks.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  children: [
                    Icon(
                      Icons.history,
                      size: 48,
                      color: isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood,
                    ),
                    const SizedBox(height: Spacing.md),
                    Text(
                      'No curator activity yet',
                      style: TextStyle(
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...info.recentTasks.map((task) => _buildTaskCard(isDark, task)),
        ],
      ),
    );
  }

  Widget _buildStatusCard(bool isDark, CuratorInfo info) {
    final curator = info.curatorSession;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated
            : BrandColors.softWhite,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: isDark
              ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
              : BrandColors.driftwood.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                curator != null ? Icons.check_circle : Icons.pending,
                size: 20,
                color: curator != null
                    ? (isDark ? BrandColors.nightForest : BrandColors.forest)
                    : (isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood),
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                curator != null ? 'Curator Active' : 'No Curator Yet',
                style: TextStyle(
                  fontSize: TypographyTokens.bodyLarge,
                  fontWeight: FontWeight.w500,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),
            ],
          ),
          if (curator != null) ...[
            const SizedBox(height: Spacing.md),
            _buildInfoRow(
              isDark,
              label: 'Last Run',
              value: curator.lastRunAt != null
                  ? _formatDate(curator.lastRunAt!)
                  : 'Never',
            ),
            const SizedBox(height: Spacing.xs),
            _buildInfoRow(
              isDark,
              label: 'Messages Processed',
              value: curator.lastMessageIndex.toString(),
            ),
            if (curator.contextFiles.isNotEmpty) ...[
              const SizedBox(height: Spacing.xs),
              _buildInfoRow(
                isDark,
                label: 'Context Files',
                value: curator.contextFiles.join(', '),
              ),
            ],
          ],
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              _buildStatBadge(
                isDark,
                label: 'Completed',
                count: info.completedTaskCount,
                color: BrandColors.forest,
              ),
              const SizedBox(width: Spacing.sm),
              _buildStatBadge(
                isDark,
                label: 'With Updates',
                count: info.tasksWithUpdates,
                color: BrandColors.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(bool isDark, {required String label, required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              fontSize: TypographyTokens.bodySmall,
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: TypographyTokens.bodySmall,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatBadge(
    bool isDark, {
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: TypographyTokens.bodySmall,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: Spacing.xs),
          Text(
            label,
            style: TextStyle(
              fontSize: TypographyTokens.bodySmall,
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(bool isDark, CuratorTask task) {
    final statusColor = _getStatusColor(task.status);
    final hasResult = task.result != null;

    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      color: isDark
          ? BrandColors.nightSurfaceElevated
          : BrandColors.softWhite,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(
          color: isDark
              ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
              : BrandColors.driftwood.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        onTap: hasResult ? () => setState(() => _selectedTask = task) : null,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Status indicator
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    task.status.displayName,
                    style: TextStyle(
                      fontSize: TypographyTokens.bodyMedium,
                      fontWeight: FontWeight.w500,
                      color: statusColor,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(task.queuedAt),
                    style: TextStyle(
                      fontSize: TypographyTokens.bodySmall,
                      color: isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  _buildTaskChip(
                    isDark,
                    icon: Icons.flash_on,
                    label: task.triggerTypeDisplay,
                  ),
                  if (task.result != null) ...[
                    const SizedBox(width: Spacing.sm),
                    if (task.result!.titleUpdated)
                      _buildTaskChip(
                        isDark,
                        icon: Icons.title,
                        label: 'Title',
                        color: BrandColors.forest,
                      ),
                    if (task.result!.contextUpdated)
                      _buildTaskChip(
                        isDark,
                        icon: Icons.note_add,
                        label: 'Context',
                        color: BrandColors.warning,
                      ),
                    if (task.result!.noChanges)
                      _buildTaskChip(
                        isDark,
                        icon: Icons.check,
                        label: 'No changes',
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                  ],
                ],
              ),
              if (hasResult) ...[
                const SizedBox(height: Spacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Tap for details',
                      style: TextStyle(
                        fontSize: TypographyTokens.bodySmall,
                        color: isDark
                            ? BrandColors.nightForest
                            : BrandColors.forest,
                      ),
                    ),
                    const SizedBox(width: Spacing.xs),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color:
                          isDark ? BrandColors.nightForest : BrandColors.forest,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskChip(
    bool isDark, {
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final chipColor = color ??
        (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: chipColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: TypographyTokens.bodySmall,
              color: chipColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskDetailView(bool isDark, CuratorTask task) {
    final result = task.result;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status and timing
          _buildDetailSection(
            isDark,
            title: 'Status',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _getStatusColor(task.status),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Text(
                      task.status.displayName,
                      style: TextStyle(
                        fontSize: TypographyTokens.bodyLarge,
                        fontWeight: FontWeight.w500,
                        color: _getStatusColor(task.status),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                _buildInfoRow(isDark,
                    label: 'Queued', value: _formatDateWithSeconds(task.queuedAt)),
                if (task.startedAt != null)
                  _buildInfoRow(isDark,
                      label: 'Started',
                      value: _formatDateWithSeconds(task.startedAt!)),
                if (task.completedAt != null)
                  _buildInfoRow(isDark,
                      label: 'Completed',
                      value: _formatDateWithSeconds(task.completedAt!)),
                if (task.duration != null)
                  _buildInfoRow(isDark,
                      label: 'Duration', value: '${task.duration!.inSeconds}s'),
              ],
            ),
          ),

          const SizedBox(height: Spacing.lg),

          // Result
          if (result != null) ...[
            _buildDetailSection(
              isDark,
              title: 'Actions Taken',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (result.actions.isEmpty)
                    Text(
                      'No actions taken',
                      style: TextStyle(
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                    )
                  else
                    ...result.actions.map(
                      (action) => Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 16,
                              color: isDark
                                  ? BrandColors.nightForest
                                  : BrandColors.forest,
                            ),
                            const SizedBox(width: Spacing.sm),
                            Expanded(
                              child: Text(
                                action,
                                style: TextStyle(
                                  color: isDark
                                      ? BrandColors.nightText
                                      : BrandColors.charcoal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: Spacing.lg),

            // Reasoning
            if (result.reasoning != null) ...[
              _buildDetailSection(
                isDark,
                title: 'Curator Reasoning',
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Spacing.md),
                  decoration: BoxDecoration(
                    color: isDark
                        ? BrandColors.nightSurface
                        : BrandColors.stone,
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: SelectableText(
                    result.reasoning!,
                    style: TextStyle(
                      fontSize: TypographyTokens.bodySmall,
                      fontFamily: 'monospace',
                      color: isDark
                          ? BrandColors.nightText
                          : BrandColors.charcoal,
                    ),
                  ),
                ),
              ),
            ],
          ],

          // Error
          if (task.error != null) ...[
            const SizedBox(height: Spacing.lg),
            _buildDetailSection(
              isDark,
              title: 'Error',
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: BrandColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(color: BrandColors.warning.withValues(alpha: 0.3)),
                ),
                child: SelectableText(
                  task.error!,
                  style: TextStyle(
                    fontSize: TypographyTokens.bodySmall,
                    color: isDark ? BrandColors.warning : BrandColors.error,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailSection(
    bool isDark, {
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: TypographyTokens.titleSmall,
            fontWeight: FontWeight.w600,
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        child,
      ],
    );
  }

  Color _getStatusColor(CuratorTaskStatus status) {
    switch (status) {
      case CuratorTaskStatus.pending:
        return BrandColors.warning;
      case CuratorTaskStatus.running:
        return BrandColors.forest;
      case CuratorTaskStatus.completed:
        return BrandColors.forest;
      case CuratorTaskStatus.failed:
        return BrandColors.error;
    }
  }
}
