import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/providers/feature_flags_provider.dart';
import 'package:parachute_chat/core/providers/backend_health_provider.dart';
import './settings_section_header.dart';

/// AI Chat Server settings section
class AiChatSection extends ConsumerStatefulWidget {
  const AiChatSection({super.key});

  @override
  ConsumerState<AiChatSection> createState() => _AiChatSectionState();
}

class _AiChatSectionState extends ConsumerState<AiChatSection> {
  String _aiServerUrl = 'http://localhost:3333';
  final TextEditingController _aiServerUrlController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _aiServerUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final featureFlagsService = ref.read(featureFlagsServiceProvider);
    _aiServerUrl = await featureFlagsService.getAiServerUrl();
    _aiServerUrlController.text = _aiServerUrl;
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _setAiServerUrl(String url) async {
    final featureFlagsService = ref.read(featureFlagsServiceProvider);
    await featureFlagsService.setAiServerUrl(url);
    setState(() => _aiServerUrl = url);

    // Clear the cached URL and invalidate the provider so ChatService rebuilds
    featureFlagsService.clearCache();
    ref.invalidate(aiServerUrlProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('AI server URL updated - takes effect immediately'),
          backgroundColor: BrandColors.success,
        ),
      );
    }
  }

  Widget _buildServerStatusIndicator() {
    final healthAsync = ref.watch(serverHealthProvider(_aiServerUrl));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return healthAsync.when(
      data: (health) {
        final statusColor = health.isHealthy
            ? BrandColors.success
            : BrandColors.error;

        return Container(
          padding: EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: statusColor, width: 1),
          ),
          child: Row(
            children: [
              Icon(
                health.isHealthy ? Icons.check_circle : Icons.error,
                color: statusColor,
                size: 20,
              ),
              SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      health.isHealthy
                          ? 'Server Connected'
                          : 'Server Unavailable',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: TypographyTokens.bodySmall,
                        color: statusColor,
                      ),
                    ),
                    SizedBox(height: Spacing.xs),
                    Text(
                      health.displayMessage,
                      style: TextStyle(
                        fontSize: TypographyTokens.labelSmall,
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
        );
      },
      loading: () => Container(
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
              'Checking server status...',
              style: TextStyle(
                fontSize: TypographyTokens.bodySmall,
                color: BrandColors.turquoise,
              ),
            ),
          ],
        ),
      ),
      error: (error, stack) => Container(
        padding: EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: BrandColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: BrandColors.warning, width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.warning, color: BrandColors.warning, size: 20),
            SizedBox(width: Spacing.md),
            Expanded(
              child: Text(
                'Error checking server: $error',
                style: TextStyle(
                  fontSize: TypographyTokens.labelSmall,
                  color: BrandColors.warning,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'AI Chat Server',
          subtitle: 'Configure connection to Parachute Base server',
          icon: Icons.chat_bubble_outline,
        ),
        SizedBox(height: Spacing.lg),

        // AI Chat Server Configuration
        Container(
          padding: EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: isDark
                ? BrandColors.nightSurfaceElevated
                : BrandColors.stone.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Column(
            children: [
                TextField(
                  controller: _aiServerUrlController,
                  decoration: InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'http://localhost:3333',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.link),
                  ),
                  keyboardType: TextInputType.url,
                ),
                SizedBox(height: Spacing.md),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          _setAiServerUrl(_aiServerUrlController.text.trim());
                        },
                        icon: const Icon(Icons.save),
                        label: const Text('Save Server URL'),
                        style: FilledButton.styleFrom(
                          backgroundColor: BrandColors.forest,
                          padding: EdgeInsets.symmetric(vertical: Spacing.md),
                        ),
                      ),
                    ),
                    SizedBox(width: Spacing.md),
                    FilledButton.icon(
                      onPressed: () {
                        ref.invalidate(serverHealthProvider(_aiServerUrl));
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Test'),
                      style: FilledButton.styleFrom(
                        backgroundColor: BrandColors.turquoise,
                        padding: EdgeInsets.symmetric(
                          horizontal: Spacing.lg,
                          vertical: Spacing.md,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: Spacing.lg),
                _buildServerStatusIndicator(),
            ],
          ),
        ),

        SizedBox(height: Spacing.lg),
      ],
    );
  }
}
