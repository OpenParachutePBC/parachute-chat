import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/providers/feature_flags_provider.dart';
import 'package:parachute_chat/core/providers/backend_health_provider.dart';

/// Server setup step - configure Base server connection
class ServerSetupStep extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  const ServerSetupStep({
    super.key,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  @override
  ConsumerState<ServerSetupStep> createState() => _ServerSetupStepState();
}

class _ServerSetupStepState extends ConsumerState<ServerSetupStep> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false;
  bool _isTested = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCurrentUrl();
  }

  Future<void> _loadCurrentUrl() async {
    final url = await ref.read(aiServerUrlProvider.future);
    if (mounted) {
      setState(() {
        _urlController.text = url;
      });
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isTested = false;
    });

    try {
      // Invalidate to trigger fresh health check
      ref.invalidate(serverHealthProvider(_urlController.text.trim()));

      // Wait for health check
      final health = await ref.read(
        serverHealthProvider(_urlController.text.trim()).future,
      );

      if (mounted) {
        if (health.isHealthy) {
          setState(() {
            _isTested = true;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = health.displayMessage;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Connection failed: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveAndContinue() async {
    setState(() => _isLoading = true);

    try {
      final featureFlags = ref.read(featureFlagsServiceProvider);
      await featureFlags.setAiServerUrl(_urlController.text.trim());

      // Invalidate providers to reload with new URL
      ref.invalidate(aiServerUrlProvider);

      if (mounted) {
        widget.onNext();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error saving URL: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: Spacing.xl),

            // Heading
            Text(
              'Connect to Parachute Base',
              style: TextStyle(
                fontSize: TypographyTokens.displaySmall,
                fontWeight: FontWeight.bold,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),

            SizedBox(height: Spacing.md),

            Text(
              'Chat needs to connect to the Parachute Base server for AI features',
              style: TextStyle(
                fontSize: TypographyTokens.bodyLarge,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
                height: 1.5,
              ),
            ),

            SizedBox(height: Spacing.xxl),

            // Server URL input
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://localhost:3333',
                helperText: 'Use hostname (e.g., mbp.local:3333) or IP address',
                prefixIcon: const Icon(Icons.link),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              onChanged: (_) {
                // Reset test status when URL changes
                setState(() {
                  _isTested = false;
                  _errorMessage = null;
                });
              },
            ),

            SizedBox(height: Spacing.lg),

            // Test button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _testConnection,
                icon: _isLoading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDark ? BrandColors.nightForest : BrandColors.forest,
                          ),
                        ),
                      )
                    : const Icon(Icons.refresh),
                label: Text(_isLoading ? 'Testing...' : 'Test Connection'),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                  side: BorderSide(
                    color: isDark ? BrandColors.nightForest : BrandColors.forest,
                  ),
                  foregroundColor:
                      isDark ? BrandColors.nightForest : BrandColors.forest,
                ),
              ),
            ),

            // Status indicator
            if (_isTested || _errorMessage != null) ...[
              SizedBox(height: Spacing.lg),
              Container(
                padding: EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: (_isTested ? BrandColors.success : BrandColors.error)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(
                    color: _isTested ? BrandColors.success : BrandColors.error,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isTested ? Icons.check_circle : Icons.error,
                      color: _isTested ? BrandColors.success : BrandColors.error,
                      size: 20,
                    ),
                    SizedBox(width: Spacing.md),
                    Expanded(
                      child: Text(
                        _isTested
                            ? 'Connected successfully!'
                            : _errorMessage ?? 'Connection failed',
                        style: TextStyle(
                          fontSize: TypographyTokens.bodyMedium,
                          fontWeight: FontWeight.w600,
                          color:
                              _isTested ? BrandColors.success : BrandColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            SizedBox(height: Spacing.xxl),

            // Info box
            Container(
              padding: EdgeInsets.all(Spacing.lg),
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightTurquoise.withValues(alpha: 0.1)
                    : BrandColors.turquoiseMist,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(
                  color: isDark
                      ? BrandColors.nightTurquoise.withValues(alpha: 0.3)
                      : BrandColors.turquoise.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: isDark
                            ? BrandColors.nightTurquoise
                            : BrandColors.turquoiseDeep,
                      ),
                      SizedBox(width: Spacing.sm),
                      Text(
                        'Quick Setup',
                        style: TextStyle(
                          fontSize: TypographyTokens.bodyLarge,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? BrandColors.nightTurquoise
                              : BrandColors.turquoiseDeep,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: Spacing.md),
                  Text(
                    '1. Make sure Parachute Base is running:\n   cd base && npm start\n\n2. If connecting from another device, use your machine\'s hostname or IP address\n\n3. Test the connection before continuing',
                    style: TextStyle(
                      fontSize: TypographyTokens.bodyMedium,
                      color: isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: Spacing.xxxl),

            // Navigation buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onBack,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                    ),
                    child: const Text('Back'),
                  ),
                ),
                SizedBox(width: Spacing.md),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _saveAndContinue,
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          isDark ? BrandColors.nightForest : BrandColors.forest,
                      foregroundColor: BrandColors.softWhite,
                      padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                    ),
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),

            SizedBox(height: Spacing.md),

            // Skip button
            Center(
              child: TextButton(
                onPressed: widget.onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
                child: const Text('Skip for now'),
              ),
            ),

            SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }
}
