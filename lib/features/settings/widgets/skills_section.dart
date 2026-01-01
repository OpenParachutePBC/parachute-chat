import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/features/skills/models/skill.dart';
import 'package:parachute_chat/features/skills/providers/skills_providers.dart';
import './settings_section_header.dart';

/// Agent Skills settings section
///
/// Displays available agent skills and allows creating/deleting them.
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
        content: Text('Are you sure you want to delete "${skill.name}"?'),
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
    // Fetch full skill content
    final fullSkill = await ref.read(skillDetailProvider(skill.directory).future);

    if (!mounted || fullSkill == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? BrandColors.nightSurface
          : Colors.white,
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      fullSkill.name,
                      style: TextStyle(
                        fontSize: TypographyTokens.titleLarge,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              if (fullSkill.description.isNotEmpty) ...[
                SizedBox(height: Spacing.sm),
                Text(
                  fullSkill.description,
                  style: TextStyle(
                    color: BrandColors.driftwood,
                  ),
                ),
              ],
              SizedBox(height: Spacing.lg),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(Spacing.md),
                    decoration: BoxDecoration(
                      color: BrandColors.stone.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: SelectableText(
                      fullSkill.body ?? fullSkill.fullContent ?? 'No content',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: TypographyTokens.bodySmall,
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

  Widget _buildSkillCard(Skill skill, bool isDark) {
    return Card(
      margin: EdgeInsets.only(bottom: Spacing.sm),
      color: isDark
          ? BrandColors.nightSurfaceElevated
          : BrandColors.stone.withValues(alpha: 0.3),
      child: ListTile(
        onTap: () => _showSkillDetail(skill),
        leading: Icon(
          Icons.auto_awesome,
          color: BrandColors.turquoise,
        ),
        title: Text(
          skill.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (skill.description.isNotEmpty)
              Text(
                skill.description,
                style: TextStyle(
                  fontSize: TypographyTokens.labelSmall,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (skill.hasAllowedTools && skill.allowedTools != null) ...[
              SizedBox(height: Spacing.xs),
              Wrap(
                spacing: Spacing.xs,
                children: skill.allowedTools!.take(3).map((tool) {
                  return Chip(
                    label: Text(
                      tool,
                      style: TextStyle(fontSize: TypographyTokens.labelSmall),
                    ),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: BrandColors.error),
          onPressed: () => _deleteSkill(skill),
          tooltip: 'Delete skill',
        ),
      ),
    );
  }

  Widget _buildCreateSkillForm(bool isDark) {
    return Form(
      key: _formKey,
      child: Container(
        padding: EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: isDark
              ? BrandColors.nightSurfaceElevated
              : BrandColors.stone.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: BrandColors.turquoise.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Create Skill',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            SizedBox(height: Spacing.md),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Skill Name',
                hintText: 'e.g., Code Reviewer',
                border: OutlineInputBorder(),
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
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'What does this skill do?',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: Spacing.md),
            TextFormField(
              controller: _contentController,
              decoration: const InputDecoration(
                labelText: 'Instructions (optional)',
                hintText: 'Add detailed instructions for the skill...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 5,
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
          subtitle: 'Custom skills that Claude can invoke',
          icon: Icons.auto_awesome,
        ),
        SizedBox(height: Spacing.lg),

        // Skills list
        skillsAsync.when(
          data: (skills) {
            if (skills.isEmpty && !_isCreatingSkill) {
              return Container(
                padding: EdgeInsets.all(Spacing.lg),
                decoration: BoxDecoration(
                  color: isDark
                      ? BrandColors.nightSurfaceElevated
                      : BrandColors.stone.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 48,
                      color: BrandColors.driftwood,
                    ),
                    SizedBox(height: Spacing.md),
                    Text(
                      'No skills configured',
                      style: TextStyle(
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                    ),
                    SizedBox(height: Spacing.sm),
                    Text(
                      'You can also ask Claude to create skills in chat',
                      style: TextStyle(
                        fontSize: TypographyTokens.labelSmall,
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                    ),
                    SizedBox(height: Spacing.md),
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

            return Column(
              children: [
                ...skills.map((skill) => _buildSkillCard(skill, isDark)),
                if (_isCreatingSkill) ...[
                  SizedBox(height: Spacing.md),
                  _buildCreateSkillForm(isDark),
                ] else ...[
                  SizedBox(height: Spacing.md),
                  SizedBox(
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
                  ),
                ],
              ],
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, stack) => Container(
            padding: EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              color: BrandColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Column(
              children: [
                Icon(Icons.error, color: BrandColors.error),
                SizedBox(height: Spacing.md),
                Text(
                  'Error loading skills',
                  style: TextStyle(color: BrandColors.error),
                ),
                Text(
                  error.toString(),
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    color: BrandColors.driftwood,
                  ),
                ),
                SizedBox(height: Spacing.md),
                TextButton.icon(
                  onPressed: () => refreshSkills(ref),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: Spacing.lg),
      ],
    );
  }
}
