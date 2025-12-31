import 'package:flutter/material.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';

/// Welcome step - introduces Parachute with brand styling
///
/// "Think naturally" - A calm, spacious welcome experience
class WelcomeStep extends StatelessWidget {
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const WelcomeStep({super.key, required this.onNext, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: Spacing.xl),

            // Parachute logo
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.xl),
                boxShadow: isDark ? null : Elevation.cardShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.xl),
                child: Image.asset(
                  'assets/icon/parachute_icon.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
            ),

            SizedBox(height: Spacing.xxl),

            // Welcome heading
            Text(
              'Welcome to Parachute',
              style: TextStyle(
                fontSize: TypographyTokens.displaySmall,
                fontWeight: FontWeight.bold,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: Spacing.md),

            // Tagline
            Text(
              'AI conversations with your vault',
              style: TextStyle(
                fontSize: TypographyTokens.titleLarge,
                fontStyle: FontStyle.italic,
                color: isDark
                    ? BrandColors.nightForest.withValues(alpha: 0.9)
                    : BrandColors.forest,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: Spacing.lg),

            // Subtitle
            Text(
              'Chat with Claude about your notes, documents, and ideas',
              style: TextStyle(
                fontSize: TypographyTokens.bodyLarge,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: Spacing.lg),

            // Compatibility badge with brand styling
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: Spacing.lg,
                vertical: Spacing.md,
              ),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: isDark
                        ? BrandColors.nightTurquoise
                        : BrandColors.turquoiseDeep,
                  ),
                  SizedBox(width: Spacing.sm),
                  Flexible(
                    child: Text(
                      'Works with Obsidian, Logseq, and other markdown vaults',
                      style: TextStyle(
                        fontSize: TypographyTokens.bodySmall,
                        color: isDark
                            ? BrandColors.nightTurquoise
                            : BrandColors.turquoiseDeep,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: Spacing.xxxl),

            // Feature highlights
            _buildFeature(
              context,
              icon: Icons.folder_open,
              title: 'Your Vault',
              description:
                  'Sessions and contexts stored as markdown - portable and yours',
              isDark: isDark,
            ),

            SizedBox(height: Spacing.lg),

            _buildFeature(
              context,
              icon: Icons.chat_bubble_outline,
              title: 'AI Conversations',
              description: 'Chat with Claude via Parachute Base server',
              isDark: isDark,
            ),

            SizedBox(height: Spacing.lg),

            _buildFeature(
              context,
              icon: Icons.history,
              title: 'Session History',
              description: 'All conversations saved and searchable',
              isDark: isDark,
            ),

            SizedBox(height: Spacing.lg),

            _buildFeature(
              context,
              icon: Icons.sync,
              title: 'Sync Your Way',
              description:
                  'Use Git, iCloud, Dropbox, or any sync tool you trust',
              isDark: isDark,
            ),

            SizedBox(height: Spacing.xxxl),

            // Continue button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      isDark ? BrandColors.nightForest : BrandColors.forest,
                  foregroundColor: BrandColors.softWhite,
                  padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                ),
                child: Text(
                  'Get Started',
                  style: TextStyle(
                    fontSize: TypographyTokens.bodyLarge,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            SizedBox(height: Spacing.md),

            // Skip button
            TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
              child: const Text('Skip setup'),
            ),

            SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildFeature(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: isDark
                ? BrandColors.nightForest.withValues(alpha: 0.2)
                : BrandColors.forestMist.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Icon(
            icon,
            size: 22,
            color: isDark ? BrandColors.nightForest : BrandColors.forest,
          ),
        ),
        SizedBox(width: Spacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: TypographyTokens.bodyLarge,
                  fontWeight: FontWeight.bold,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),
              SizedBox(height: Spacing.xs),
              Text(
                description,
                style: TextStyle(
                  fontSize: TypographyTokens.bodyMedium,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
