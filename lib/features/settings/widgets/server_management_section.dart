import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/providers/supervisor_provider.dart';
import 'package:parachute_chat/core/services/supervisor_service.dart';
import './settings_section_header.dart';

/// Server Management section with restart button
class ServerManagementSection extends ConsumerWidget {
  const ServerManagementSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final supervisorAvailable = ref.watch(supervisorAvailableProvider);
    final statusAsync = ref.watch(supervisorStatusProvider);
    final actionState = ref.watch(supervisorActionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Server Management',
          subtitle: 'Control the Parachute Base server',
          icon: Icons.dns_outlined,
        ),
        SizedBox(height: Spacing.lg),

        Container(
          padding: EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: isDark
                ? BrandColors.nightSurfaceElevated
                : BrandColors.stone.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: supervisorAvailable.when(
            data: (available) {
              if (!available) {
                return _buildSupervisorUnavailable(context);
              }
              return _buildServerControls(
                context,
                ref,
                statusAsync,
                actionState,
                isDark,
              );
            },
            loading: () => _buildLoading(),
            error: (e, _) => _buildSupervisorUnavailable(context),
          ),
        ),

        SizedBox(height: Spacing.lg),
      ],
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildSupervisorUnavailable(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: BrandColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: BrandColors.warning, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: BrandColors.warning, size: 20),
              SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  'Supervisor Not Running',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: TypographyTokens.bodySmall,
                    color: BrandColors.warning,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: Spacing.sm),
          Text(
            'Start the supervisor service to manage the server from here.\n\n'
            'Run from terminal:\n'
            'cd base && python -m supervisor.main',
            style: TextStyle(
              fontSize: TypographyTokens.labelSmall,
              color: Theme.of(context).brightness == Brightness.dark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerControls(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<SupervisorStatus> statusAsync,
    AsyncValue<SupervisorActionResult?> actionState,
    bool isDark,
  ) {
    return Column(
      children: [
        // Status display
        statusAsync.when(
          data: (status) => _buildStatusDisplay(context, status, isDark),
          loading: () => _buildStatusLoading(),
          error: (e, _) => _buildStatusError(e.toString()),
        ),

        SizedBox(height: Spacing.lg),

        // Action buttons
        _buildActionButtons(context, ref, statusAsync, actionState),

        // Action result message
        if (actionState is AsyncData<SupervisorActionResult?> &&
            actionState.value != null)
          Padding(
            padding: EdgeInsets.only(top: Spacing.md),
            child: _buildActionResult(actionState.value!),
          ),
      ],
    );
  }

  Widget _buildStatusDisplay(
    BuildContext context,
    SupervisorStatus status,
    bool isDark,
  ) {
    final (Color statusColor, IconData statusIcon) = switch (status.serverState) {
      ServerState.running => (BrandColors.success, Icons.check_circle),
      ServerState.stopped => (BrandColors.error, Icons.cancel),
      ServerState.starting ||
      ServerState.restarting => (BrandColors.warning, Icons.hourglass_empty),
      ServerState.stopping => (BrandColors.warning, Icons.stop_circle),
      ServerState.failed => (BrandColors.error, Icons.error),
      ServerState.unknown => (BrandColors.driftwood, Icons.help_outline),
    };

    return Container(
      padding: EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: statusColor, width: 1),
      ),
      child: Column(
        children: [
          // Main status row
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 24),
              SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatState(status.serverState),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: TypographyTokens.bodyMedium,
                        color: statusColor,
                      ),
                    ),
                    if (status.serverState == ServerState.running) ...[
                      SizedBox(height: Spacing.xs),
                      Text(
                        'Uptime: ${status.uptimeFormatted}',
                        style: TextStyle(
                          fontSize: TypographyTokens.labelSmall,
                          color: isDark
                              ? BrandColors.nightTextSecondary
                              : BrandColors.driftwood,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (status.pid != null)
                Text(
                  'PID: ${status.pid}',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                ),
            ],
          ),

          // Additional info
          if (status.restartCount > 0 || status.lastError != null) ...[
            SizedBox(height: Spacing.md),
            Divider(height: 1, color: statusColor.withValues(alpha: 0.3)),
            SizedBox(height: Spacing.sm),
            Row(
              children: [
                if (status.restartCount > 0)
                  Padding(
                    padding: EdgeInsets.only(right: Spacing.md),
                    child: Text(
                      'Restarts: ${status.restartCount}',
                      style: TextStyle(
                        fontSize: TypographyTokens.labelSmall,
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                    ),
                  ),
                if (status.lastError != null)
                  Expanded(
                    child: Text(
                      'Error: ${status.lastError}',
                      style: TextStyle(
                        fontSize: TypographyTokens.labelSmall,
                        color: BrandColors.error,
                      ),
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

  Widget _buildStatusLoading() {
    return Container(
      padding: EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: BrandColors.turquoise.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: BrandColors.turquoise, width: 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(BrandColors.turquoise),
            ),
          ),
          SizedBox(width: Spacing.md),
          Text(
            'Fetching server status...',
            style: TextStyle(
              fontSize: TypographyTokens.bodySmall,
              color: BrandColors.turquoise,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusError(String error) {
    return Container(
      padding: EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: BrandColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: BrandColors.error, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.error, color: BrandColors.error, size: 20),
          SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              'Error: $error',
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: BrandColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<SupervisorStatus> statusAsync,
    AsyncValue<SupervisorActionResult?> actionState,
  ) {
    final isLoading = actionState is AsyncLoading;
    final status = statusAsync.valueOrNull;
    final isRunning = status?.serverState == ServerState.running;
    final isStopped = status?.serverState == ServerState.stopped ||
        status?.serverState == ServerState.failed;

    return Row(
      children: [
        // Start button
        Expanded(
          child: FilledButton.icon(
            onPressed: (isLoading || isRunning)
                ? null
                : () => ref.read(supervisorActionsProvider.notifier).startServer(),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start'),
            style: FilledButton.styleFrom(
              backgroundColor: BrandColors.success,
              disabledBackgroundColor: BrandColors.success.withValues(alpha: 0.3),
              padding: EdgeInsets.symmetric(vertical: Spacing.md),
            ),
          ),
        ),

        SizedBox(width: Spacing.sm),

        // Stop button
        Expanded(
          child: FilledButton.icon(
            onPressed: (isLoading || isStopped)
                ? null
                : () => ref.read(supervisorActionsProvider.notifier).stopServer(),
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
            style: FilledButton.styleFrom(
              backgroundColor: BrandColors.error,
              disabledBackgroundColor: BrandColors.error.withValues(alpha: 0.3),
              padding: EdgeInsets.symmetric(vertical: Spacing.md),
            ),
          ),
        ),

        SizedBox(width: Spacing.sm),

        // Restart button
        Expanded(
          child: FilledButton.icon(
            onPressed: isLoading
                ? null
                : () => ref.read(supervisorActionsProvider.notifier).restartServer(),
            icon: const Icon(Icons.refresh),
            label: const Text('Restart'),
            style: FilledButton.styleFrom(
              backgroundColor: BrandColors.turquoise,
              disabledBackgroundColor: BrandColors.turquoise.withValues(alpha: 0.3),
              padding: EdgeInsets.symmetric(vertical: Spacing.md),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionResult(SupervisorActionResult result) {
    final color = result.success ? BrandColors.success : BrandColors.error;
    final icon = result.success ? Icons.check_circle : Icons.error;
    final message = result.success
        ? 'Action completed successfully'
        : 'Action failed: ${result.error ?? "Unknown error"}';

    return Container(
      padding: EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatState(ServerState state) {
    return switch (state) {
      ServerState.running => 'Server Running',
      ServerState.stopped => 'Server Stopped',
      ServerState.starting => 'Server Starting...',
      ServerState.stopping => 'Server Stopping...',
      ServerState.restarting => 'Server Restarting...',
      ServerState.failed => 'Server Failed',
      ServerState.unknown => 'Status Unknown',
    };
  }
}
