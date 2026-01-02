import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/features/skills/models/skill.dart';
import 'package:parachute_chat/features/skills/providers/skills_providers.dart';
import './settings_section_header.dart';

/// Agent Skills settings section
///
/// Displays available agent skills and allows creating/deleting them.
/// Skills are stored in {vault}/.claude/skills/ and are available to all chats.
///
/// Skills can include:
/// - SKILL.md: Instructions (required)
/// - scripts/: Executable Python/Bash scripts
/// - references/: Documentation loaded on-demand
/// - assets/: Files for output (templates, images)
class SkillsSection extends ConsumerStatefulWidget {
  const SkillsSection({super.key});

  @override
  ConsumerState<SkillsSection> createState() => _SkillsSectionState();
}

class _SkillsSectionState extends ConsumerState<SkillsSection> {
  bool _isCreatingSkill = false;
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _resetForm() {
    _nameController.clear();
    _descriptionController.clear();
    _contentController.clear();
    setState(() => _isCreatingSkill = false);
  }

  Future<void> _createSkill() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    final content = _contentController.text.trim();

    try {
      await createSkill(
        ref,
        name: name,
        description: description.isEmpty ? null : description,
        content: content.isEmpty ? null : content,
      );

      _resetForm();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Skill "$name" created'),
            backgroundColor: BrandColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating skill: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
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
    if (filename == 'scripts' || filename == 'references' || filename == 'assets') {
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

  Widget _buildCreateSkillForm(bool isDark) {
    final cardColor = isDark ? BrandColors.nightSurfaceElevated : Colors.white;
    final borderColor = BrandColors.turquoise.withValues(alpha: 0.5);

    return Form(
      key: _formKey,
      child: Container(
        padding: EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: BrandColors.turquoise.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.add_circle_outline,
                  color: BrandColors.turquoise,
                  size: 20,
                ),
                SizedBox(width: Spacing.sm),
                Text(
                  'Create Skill',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: TypographyTokens.bodyLarge,
                    color:
                        isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
              ],
            ),
            SizedBox(height: Spacing.md),

            // Info box
            Container(
              padding: EdgeInsets.all(Spacing.sm),
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightForest.withValues(alpha: 0.2)
                    : BrandColors.turquoise.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: BrandColors.turquoise,
                  ),
                  SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'For complex skills with scripts/files, ask Claude in chat: "Create a skill that..."',
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
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Skill Name',
                hintText: 'e.g., code-reviewer',
                prefixIcon: const Icon(Icons.label_outline),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: isDark
                    ? BrandColors.nightSurface
                    : BrandColors.cream.withValues(alpha: 0.5),
                helperText: 'Lowercase with hyphens (e.g., pdf-processor)',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Name is required';
                }
                return null;
              },
            ),
            SizedBox(height: Spacing.md),
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: 'When should Claude use this skill?',
                prefixIcon: const Icon(Icons.description_outlined),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: isDark
                    ? BrandColors.nightSurface
                    : BrandColors.cream.withValues(alpha: 0.5),
                helperText: 'Include trigger words (e.g., "review code", "analyze PR")',
              ),
            ),
            SizedBox(height: Spacing.md),
            TextFormField(
              controller: _contentController,
              decoration: InputDecoration(
                labelText: 'Instructions (SKILL.md body)',
                hintText: '## How to use this skill\n\n1. First step...',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: isDark
                    ? BrandColors.nightSurface
                    : BrandColors.cream.withValues(alpha: 0.5),
                alignLabelWithHint: true,
              ),
              maxLines: 6,
            ),
            SizedBox(height: Spacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _resetForm,
                  child: const Text('Cancel'),
                ),
                SizedBox(width: Spacing.md),
                FilledButton.icon(
                  onPressed: _createSkill,
                  icon: const Icon(Icons.add),
                  label: const Text('Create Skill'),
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
          ],
        ),
      ),
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
                  'Skills can include scripts, reference docs, and assets. Claude triggers them automatically based on your request.',
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
        SizedBox(height: Spacing.md),

        // Skills list or form
        if (_isCreatingSkill)
          _buildCreateSkillForm(isDark)
        else
          skillsAsync.when(
            data: (skills) {
              if (skills.isEmpty) {
                return _buildEmptyState(isDark);
              }

              return Column(
                children: [
                  ...skills.map((skill) => _buildSkillCard(skill, isDark)),
                  SizedBox(height: Spacing.md),
                  _buildAddButton(isDark),
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
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      padding: EdgeInsets.all(Spacing.xl),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: isDark
              ? BrandColors.turquoise.withValues(alpha: 0.2)
              : BrandColors.stone,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 48,
            color: BrandColors.driftwood.withValues(alpha: 0.5),
          ),
          SizedBox(height: Spacing.md),
          Text(
            'No skills configured',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
            ),
          ),
          SizedBox(height: Spacing.sm),
          Text(
            'Create skills here or ask Claude:\n"Create a skill for reviewing code"',
            style: TextStyle(
              fontSize: TypographyTokens.labelSmall,
              color: isDark
                  ? BrandColors.nightTextSecondary.withValues(alpha: 0.7)
                  : BrandColors.driftwood.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: Spacing.lg),
          FilledButton.icon(
            onPressed: () => setState(() => _isCreatingSkill = true),
            icon: const Icon(Icons.add),
            label: const Text('Create Skill'),
            style: FilledButton.styleFrom(
              backgroundColor: BrandColors.turquoise,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton(bool isDark) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => setState(() => _isCreatingSkill = true),
        icon: const Icon(Icons.add),
        label: const Text('Create Skill'),
        style: OutlinedButton.styleFrom(
          foregroundColor: BrandColors.turquoise,
          side: BorderSide(color: BrandColors.turquoise),
          padding: EdgeInsets.symmetric(vertical: Spacing.md),
        ),
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
