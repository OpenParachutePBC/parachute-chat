import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/features/mcp/models/mcp_server.dart';
import 'package:parachute_chat/features/mcp/providers/mcp_providers.dart';
import './settings_section_header.dart';

/// MCP Servers settings section
///
/// Displays configured MCP (Model Context Protocol) servers
/// and allows adding, editing, and removing them.
///
/// MCPs are stored in {vault}/.mcp.json and are available to all chats.
class McpSection extends ConsumerStatefulWidget {
  const McpSection({super.key});

  @override
  ConsumerState<McpSection> createState() => _McpSectionState();
}

class _McpSectionState extends ConsumerState<McpSection> {
  bool _isEditing = false;
  String? _editingServerName; // null = adding new, non-null = editing existing
  final _nameController = TextEditingController();
  final _commandController = TextEditingController();
  final _argsController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
    _argsController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _resetForm() {
    _nameController.clear();
    _commandController.clear();
    _argsController.clear();
    _descriptionController.clear();
    setState(() {
      _isEditing = false;
      _editingServerName = null;
    });
  }

  void _startEditing(McpServer server) {
    _nameController.text = server.name;
    _commandController.text = server.command ?? '';
    _argsController.text = server.args?.join(' ') ?? '';
    _descriptionController.text = server.description ?? '';
    setState(() {
      _isEditing = true;
      _editingServerName = server.name;
    });
  }

  void _startAdding() {
    _resetForm();
    setState(() {
      _isEditing = true;
      _editingServerName = null;
    });
  }

  Future<void> _saveServer() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final command = _commandController.text.trim();
    final argsText = _argsController.text.trim();
    final description = _descriptionController.text.trim();
    final args = argsText.isEmpty
        ? <String>[]
        : argsText.split(' ').where((s) => s.isNotEmpty).toList();

    final isNew = _editingServerName == null;
    final oldName = _editingServerName;

    try {
      // If editing and name changed, remove old entry first
      if (!isNew && oldName != null && oldName != name) {
        await removeMcpServer(ref, oldName);
      }

      await addStdioMcpServer(
        ref,
        name: name,
        command: command,
        args: args,
        description: description.isEmpty ? null : description,
      );

      _resetForm();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isNew
                ? 'MCP server "$name" added'
                : 'MCP server "$name" updated'),
            backgroundColor: BrandColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving server: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
  }

  Future<void> _removeServer(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove MCP Server'),
        content: Text('Are you sure you want to remove "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: BrandColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await removeMcpServer(ref, name);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('MCP server "$name" removed'),
            backgroundColor: BrandColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing server: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
  }

  Widget _buildServerCard(McpServer server, bool isDark) {
    final cardColor = isDark
        ? BrandColors.nightSurfaceElevated
        : Colors.white;
    final borderColor = isDark
        ? BrandColors.nightForest.withValues(alpha: 0.3)
        : BrandColors.forest.withValues(alpha: 0.2);
    final textColor = isDark ? BrandColors.nightText : BrandColors.charcoal;
    final subtitleColor = isDark
        ? BrandColors.nightTextSecondary
        : BrandColors.driftwood;

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
          onTap: () => _startEditing(server),
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
                    color: BrandColors.forest.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Icon(
                    server.isStdio ? Icons.terminal : Icons.cloud,
                    color: BrandColors.forest,
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
                        server.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: TypographyTokens.bodyMedium,
                          color: textColor,
                        ),
                      ),
                      SizedBox(height: Spacing.xs),
                      Text(
                        server.displayCommand,
                        style: TextStyle(
                          fontSize: TypographyTokens.labelSmall,
                          color: subtitleColor,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (server.description != null) ...[
                        SizedBox(height: Spacing.xs),
                        Text(
                          server.description!,
                          style: TextStyle(
                            fontSize: TypographyTokens.labelSmall,
                            color: subtitleColor.withValues(alpha: 0.8),
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Actions
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.edit_outlined,
                          color: BrandColors.turquoise, size: 20),
                      onPressed: () => _startEditing(server),
                      tooltip: 'Edit',
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: BrandColors.error, size: 20),
                      onPressed: () => _removeServer(server.name),
                      tooltip: 'Remove',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServerForm(bool isDark) {
    final isNew = _editingServerName == null;
    final cardColor = isDark
        ? BrandColors.nightSurfaceElevated
        : Colors.white;
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
                  isNew ? Icons.add_circle_outline : Icons.edit,
                  color: BrandColors.turquoise,
                  size: 20,
                ),
                SizedBox(width: Spacing.sm),
                Text(
                  isNew ? 'Add MCP Server' : 'Edit MCP Server',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: TypographyTokens.bodyLarge,
                    color: isDark
                        ? BrandColors.nightText
                        : BrandColors.charcoal,
                  ),
                ),
              ],
            ),
            SizedBox(height: Spacing.lg),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Server Name',
                hintText: 'e.g., glif, filesystem',
                prefixIcon: const Icon(Icons.label_outline),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: isDark
                    ? BrandColors.nightSurface
                    : BrandColors.cream.withValues(alpha: 0.5),
              ),
              enabled: isNew, // Can't rename existing servers
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Name is required';
                }
                if (!RegExp(r'^[a-z0-9-]+$').hasMatch(value.trim())) {
                  return 'Use lowercase letters, numbers, and hyphens only';
                }
                return null;
              },
            ),
            SizedBox(height: Spacing.md),
            TextFormField(
              controller: _commandController,
              decoration: InputDecoration(
                labelText: 'Command',
                hintText: 'e.g., npx, node, python',
                prefixIcon: const Icon(Icons.terminal),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: isDark
                    ? BrandColors.nightSurface
                    : BrandColors.cream.withValues(alpha: 0.5),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Command is required';
                }
                return null;
              },
            ),
            SizedBox(height: Spacing.md),
            TextFormField(
              controller: _argsController,
              decoration: InputDecoration(
                labelText: 'Arguments',
                hintText: 'e.g., -y @glifxyz/glif-mcp-server@latest',
                prefixIcon: const Icon(Icons.code),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: isDark
                    ? BrandColors.nightSurface
                    : BrandColors.cream.withValues(alpha: 0.5),
                helperText: 'Space-separated arguments',
              ),
            ),
            SizedBox(height: Spacing.md),
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'What does this MCP do?',
                prefixIcon: const Icon(Icons.description_outlined),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: isDark
                    ? BrandColors.nightSurface
                    : BrandColors.cream.withValues(alpha: 0.5),
              ),
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
                  onPressed: _saveServer,
                  icon: Icon(isNew ? Icons.add : Icons.save),
                  label: Text(isNew ? 'Add Server' : 'Save Changes'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BrandColors.forest,
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
    final serversAsync = ref.watch(mcpServersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'MCP Servers',
          subtitle: 'External tools available to all chats (stored in vault)',
          icon: Icons.extension,
        ),
        SizedBox(height: Spacing.md),

        // Info text
        Container(
          padding: EdgeInsets.all(Spacing.sm),
          decoration: BoxDecoration(
            color: isDark
                ? BrandColors.nightForest.withValues(alpha: 0.2)
                : BrandColors.forest.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: BrandColors.forest,
              ),
              SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'MCPs extend Claude with external tools like image generation, file access, and more.',
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

        // Server list or form
        if (_isEditing)
          _buildServerForm(isDark)
        else
          serversAsync.when(
            data: (servers) {
              if (servers.isEmpty) {
                return _buildEmptyState(isDark);
              }

              return Column(
                children: [
                  ...servers.map((server) => _buildServerCard(server, isDark)),
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
              ? BrandColors.nightForest.withValues(alpha: 0.3)
              : BrandColors.stone,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.extension_outlined,
            size: 48,
            color: BrandColors.driftwood.withValues(alpha: 0.5),
          ),
          SizedBox(height: Spacing.md),
          Text(
            'No MCP servers configured',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
            ),
          ),
          SizedBox(height: Spacing.sm),
          Text(
            'Add servers to extend Claude\'s capabilities',
            style: TextStyle(
              fontSize: TypographyTokens.labelSmall,
              color: isDark
                  ? BrandColors.nightTextSecondary.withValues(alpha: 0.7)
                  : BrandColors.driftwood.withValues(alpha: 0.7),
            ),
          ),
          SizedBox(height: Spacing.lg),
          FilledButton.icon(
            onPressed: _startAdding,
            icon: const Icon(Icons.add),
            label: const Text('Add MCP Server'),
            style: FilledButton.styleFrom(
              backgroundColor: BrandColors.forest,
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
        onPressed: _startAdding,
        icon: const Icon(Icons.add),
        label: const Text('Add MCP Server'),
        style: OutlinedButton.styleFrom(
          foregroundColor: BrandColors.forest,
          side: BorderSide(color: BrandColors.forest),
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
            'Failed to load MCP servers',
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
            onPressed: () => refreshMcpServers(ref),
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
