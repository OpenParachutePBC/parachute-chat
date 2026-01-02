import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/features/skills/models/skill.dart';
import 'package:parachute_chat/features/skills/providers/skills_providers.dart';
import './settings_section_header.dart';

/// Agent Skills settings section
///
/// Skills extend Claude's capabilities with custom instructions, scripts,
/// reference docs, and assets. They're stored in {vault}/.claude/skills/
/// and Claude triggers them automatically based on the task.
///
/// Skill structure:
/// - SKILL.md: Instructions (required)
/// - scripts/: Executable Python/Bash scripts
/// - references/: Documentation loaded on-demand
/// - assets/: Files for output (templates, images)
///
/// This UI focuses on:
/// 1. Uploading .skill files (ZIP format) from external sources
/// 2. Viewing and managing existing skills
/// 3. Guiding users to ask Claude for creating complex skills
class SkillsSection extends ConsumerStatefulWidget {
  const SkillsSection({super.key});

  @override
  ConsumerState<SkillsSection> createState() => _SkillsSectionState();
}

class _SkillsSectionState extends ConsumerState<SkillsSection> {
  bool _isUploading = false;

  Future<void> _uploadSkillFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['skill', 'zip'],
        dialogTitle: 'Select a .skill or .zip file',
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) {
        throw Exception('Could not access selected file');
      }

      setState(() => _isUploading = true);

      await uploadSkillFile(ref, file.path!, file.name);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Skill "${file.name}" uploaded successfully'),
            backgroundColor: BrandColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading skill: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _deleteSkill(Skill skill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Skill'),
        content: Text(
            'Are you sure you want to delete "${skill.name}"?\n\nThis will remove the entire skill directory including any scripts and files.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: BrandColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await deleteSkill(ref, skill.directory);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Skill "${skill.name}" deleted'),
            backgroundColor: BrandColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting skill: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
  }

  void _showSkillDetail(Skill skill) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Fetch full skill content
    final fullSkill =
        await ref.read(skillDetailProvider(skill.directory).future);

    if (!mounted || fullSkill == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? BrandColors.nightSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: EdgeInsets.only(bottom: Spacing.md),
                  decoration: BoxDecoration(
                    color: BrandColors.driftwood.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: BrandColors.turquoise.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      color: BrandColors.turquoise,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullSkill.name,
                          style: TextStyle(
                            fontSize: TypographyTokens.titleMedium,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? BrandColors.nightText
                                : BrandColors.charcoal,
                          ),
                        ),
                        if (fullSkill.description.isNotEmpty)
                          Text(
                            fullSkill.description,
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
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              SizedBox(height: Spacing.md),

              // Metadata chips
              if (fullSkill.hasAllowedTools ||
                  (fullSkill.additionalFiles?.isNotEmpty ?? false))
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    if (fullSkill.hasAllowedTools)
                      _buildInfoChip(
                        Icons.security,
                        'Restricted tools',
                        BrandColors.warning,
                        isDark,
                      ),
                    if (fullSkill.additionalFiles?.isNotEmpty ?? false)
                      _buildInfoChip(
                        Icons.folder,
                        '${fullSkill.additionalFiles!.length} files',
                        BrandColors.forest,
                        isDark,
                      ),
                  ],
                ),

              // Additional files list
              if (fullSkill.additionalFiles?.isNotEmpty ?? false) ...[
                SizedBox(height: Spacing.md),
                Text(
                  'Bundled Files',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: TypographyTokens.labelMedium,
                    color:
                        isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
                SizedBox(height: Spacing.sm),
                ...fullSkill.additionalFiles!.map((file) => Padding(
                      padding: EdgeInsets.only(bottom: Spacing.xs),
                      child: Row(
                        children: [
                          Icon(
                            _getFileIcon(file),
                            size: 16,
                            color: BrandColors.driftwood,
                          ),
                          SizedBox(width: Spacing.sm),
                          Text(
                            file,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: TypographyTokens.labelSmall,
                              color: isDark
                                  ? BrandColors.nightTextSecondary
                                  : BrandColors.driftwood,
                            ),
                          ),
                        ],
                      ),
                    )),
              ],

              SizedBox(height: Spacing.md),
              Text(
                'SKILL.md Content',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: TypographyTokens.labelMedium,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),
              SizedBox(height: Spacing.sm),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(Spacing.md),
                    decoration: BoxDecoration(
                      color: isDark
                          ? BrandColors.nightSurfaceElevated
                          : BrandColors.cream,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(
                        color: isDark
                            ? BrandColors.nightForest.withValues(alpha: 0.3)
                            : BrandColors.stone,
                      ),
                    ),
                    child: SelectableText(
                      fullSkill.body ?? fullSkill.fullContent ?? 'No content',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: TypographyTokens.bodySmall,
                        color: isDark
                            ? BrandColors.nightText
                            : BrandColors.charcoal,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color, bool isDark) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: TypographyTokens.labelSmall,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String filename) {
    if (filename.endsWith('.py')) return Icons.code;
    if (filename.endsWith('.sh')) return Icons.terminal;
    if (filename.endsWith('.md')) return Icons.description;
    if (filename.endsWith('.json')) return Icons.data_object;
    if (filename.endsWith('.png') ||
        filename.endsWith('.jpg') ||
        filename.endsWith('.svg')) {
      return Icons.image;
    }
    if (filename == 'scripts' ||
        filename == 'references' ||
        filename == 'assets') {
      return Icons.folder;
    }
    return Icons.insert_drive_file;
  }

  Widget _buildSkillCard(Skill skill, bool isDark) {
    final cardColor = isDark ? BrandColors.nightSurfaceElevated : Colors.white;
    final borderColor = isDark
        ? BrandColors.turquoise.withValues(alpha: 0.2)
        : BrandColors.turquoise.withValues(alpha: 0.15);
    final textColor = isDark ? BrandColors.nightText : BrandColors.charcoal;
    final subtitleColor =
        isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood;

    return Container(
      margin: EdgeInsets.only(bottom: Spacing.sm),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showSkillDetail(skill),
          borderRadius: BorderRadius.circular(Radii.md),
          child: Padding(
            padding: EdgeInsets.all(Spacing.md),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: BrandColors.turquoise.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    color: BrandColors.turquoise,
                    size: 20,
                  ),
                ),
                SizedBox(width: Spacing.md),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        skill.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: TypographyTokens.bodyMedium,
                          color: textColor,
                        ),
                      ),
                      if (skill.description.isNotEmpty) ...[
                        SizedBox(height: Spacing.xs),
                        Text(
                          skill.description,
                          style: TextStyle(
                            fontSize: TypographyTokens.labelSmall,
                            color: subtitleColor,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (skill.hasAllowedTools) ...[
                        SizedBox(height: Spacing.xs),
                        Row(
                          children: [
                            Icon(
                              Icons.security,
                              size: 12,
                              color: BrandColors.warning,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Tool restrictions',
                              style: TextStyle(
                                fontSize: TypographyTokens.labelSmall,
                                color: BrandColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Actions
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: BrandColors.error, size: 20),
                  onPressed: () => _deleteSkill(skill),
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHowToCreateSkills(bool isDark) {
    return Container(
      padding: EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightForest.withValues(alpha: 0.2)
            : BrandColors.forest.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: isDark
              ? BrandColors.nightForest.withValues(alpha: 0.4)
              : BrandColors.forest.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 20,
                color: BrandColors.forest,
              ),
              SizedBox(width: Spacing.sm),
              Text(
                'Creating Skills',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: TypographyTokens.bodyMedium,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),
            ],
          ),
          SizedBox(height: Spacing.md),
          Text(
            'Skills are directories with instructions, scripts, and reference files. '
            'The best way to create them is to ask Claude in a chat:',
            style: TextStyle(
              fontSize: TypographyTokens.bodySmall,
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
              height: 1.4,
            ),
          ),
          SizedBox(height: Spacing.md),
          Container(
            padding: EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: isDark ? BrandColors.nightSurface : Colors.white,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(
                color: isDark
                    ? BrandColors.nightForest.withValues(alpha: 0.3)
                    : BrandColors.stone,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Example prompts:',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    fontWeight: FontWeight.w600,
                    color:
                        isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
                SizedBox(height: Spacing.sm),
                _buildExamplePrompt(
                  '"Create a skill for reviewing pull requests"',
                  isDark,
                ),
                SizedBox(height: Spacing.xs),
                _buildExamplePrompt(
                  '"Make a skill that generates commit messages"',
                  isDark,
                ),
                SizedBox(height: Spacing.xs),
                _buildExamplePrompt(
                  '"Build a skill for writing documentation"',
                  isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExamplePrompt(String text, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.format_quote,
          size: 14,
          color: BrandColors.turquoise,
        ),
        SizedBox(width: Spacing.xs),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: TypographyTokens.labelSmall,
              fontStyle: FontStyle.italic,
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final skillsAsync = ref.watch(skillsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Agent Skills',
          subtitle: 'Specialized capabilities Claude can invoke automatically',
          icon: Icons.auto_awesome,
        ),
        SizedBox(height: Spacing.md),

        // Info box about skills
        Container(
          padding: EdgeInsets.all(Spacing.sm),
          decoration: BoxDecoration(
            color: isDark
                ? BrandColors.turquoise.withValues(alpha: 0.15)
                : BrandColors.turquoise.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: BrandColors.turquoise,
              ),
              SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'Skills can include scripts, reference docs, and assets. '
                  'Claude triggers them automatically based on your request.',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: Spacing.lg),

        // Upload skill button
        _buildUploadSection(isDark),
        SizedBox(height: Spacing.lg),

        // Skills list
        skillsAsync.when(
          data: (skills) {
            if (skills.isEmpty) {
              return _buildEmptyState(isDark);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Installed Skills',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: TypographyTokens.bodyMedium,
                    color:
                        isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
                SizedBox(height: Spacing.md),
                ...skills.map((skill) => _buildSkillCard(skill, isDark)),
              ],
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, stack) => _buildErrorState(error, isDark),
        ),

        SizedBox(height: Spacing.lg),

        // How to create skills section
        _buildHowToCreateSkills(isDark),

        SizedBox(height: Spacing.lg),
      ],
    );
  }

  Widget _buildUploadSection(bool isDark) {
    return Container(
      padding: EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: isDark
              ? BrandColors.turquoise.withValues(alpha: 0.3)
              : BrandColors.turquoise.withValues(alpha: 0.2),
          width: 2,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.upload_file,
            size: 40,
            color: BrandColors.turquoise,
          ),
          SizedBox(height: Spacing.md),
          Text(
            'Upload a Skill',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: TypographyTokens.bodyLarge,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
          ),
          SizedBox(height: Spacing.xs),
          Text(
            'Import .skill or .zip files from external sources',
            style: TextStyle(
              fontSize: TypographyTokens.bodySmall,
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: Spacing.lg),
          _isUploading
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation(BrandColors.turquoise),
                      ),
                    ),
                    SizedBox(width: Spacing.md),
                    Text(
                      'Uploading...',
                      style: TextStyle(
                        color: BrandColors.turquoise,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                )
              : FilledButton.icon(
                  onPressed: _uploadSkillFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose File'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BrandColors.turquoise,
                    padding: EdgeInsets.symmetric(
                      horizontal: Spacing.xl,
                      vertical: Spacing.md,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      padding: EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated.withValues(alpha: 0.5)
            : BrandColors.stone.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 24,
            color: BrandColors.driftwood.withValues(alpha: 0.5),
          ),
          SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              'No skills installed yet. Upload a skill file or ask Claude to create one.',
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

  Widget _buildErrorState(Object error, bool isDark) {
    return Container(
      padding: EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: BrandColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: BrandColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: BrandColors.error, size: 32),
          SizedBox(height: Spacing.md),
          Text(
            'Failed to load skills',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: BrandColors.error,
            ),
          ),
          SizedBox(height: Spacing.sm),
          Text(
            error.toString(),
            style: TextStyle(
              fontSize: TypographyTokens.labelSmall,
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: Spacing.md),
          OutlinedButton.icon(
            onPressed: () => refreshSkills(ref),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: BrandColors.error,
              side: BorderSide(color: BrandColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
