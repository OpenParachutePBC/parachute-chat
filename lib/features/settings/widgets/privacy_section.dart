import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/services/logging_service.dart';
import './settings_section_header.dart';

/// Privacy & Debugging settings section
class PrivacySection extends ConsumerStatefulWidget {
  const PrivacySection({super.key});

  @override
  ConsumerState<PrivacySection> createState() => _PrivacySectionState();
}

class _PrivacySectionState extends ConsumerState<PrivacySection> {
  Future<void> _viewLogFiles() async {
    final logPaths = await logger.getLogFilePaths();
    if (logPaths.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No log files found')),
        );
      }
      return;
    }

    final latestLog = logPaths.first;
    final logDir = latestLog.substring(0, latestLog.lastIndexOf('/'));
    final uri = Uri.file(logDir);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop =
        Platform.isMacOS || Platform.isLinux || Platform.isWindows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Privacy & Debugging',
          subtitle: 'All data stays local on your device',
          icon: Icons.shield_outlined,
        ),
        SizedBox(height: Spacing.lg),

        // Privacy Info
        Container(
          padding: EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: BrandColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: BrandColors.success,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lock_outlined,
                    color: BrandColors.success,
                    size: 32,
                  ),
                  SizedBox(width: Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Local-First',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: TypographyTokens.bodyLarge,
                            color: isDark
                                ? BrandColors.nightText
                                : BrandColors.charcoal,
                          ),
                        ),
                        SizedBox(height: Spacing.xs),
                        Text(
                          'Your data stays on your device. No telemetry or crash reporting.',
                          style: TextStyle(
                            fontSize: TypographyTokens.bodySmall,
                            color: isDark
                                ? BrandColors.nightTextSecondary
                                : BrandColors.driftwood,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: Spacing.lg),

        // View Logs Button (desktop only)
        if (isDesktop) ...[
          OutlinedButton.icon(
            onPressed: _viewLogFiles,
            icon: const Icon(Icons.folder_open),
            label: const Text('View Local Log Files'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          SizedBox(height: Spacing.sm),
          Center(
            child: Text(
              'Log files are stored locally and rotated automatically',
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
            ),
          ),
        ],
        SizedBox(height: Spacing.lg),
      ],
    );
  }
}
