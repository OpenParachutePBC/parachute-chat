import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/features/mcp/models/mcp_server.dart';
import 'package:parachute_chat/features/mcp/providers/mcp_providers.dart';
import './settings_section_header.dart';

/// MCP Servers settings section
///
/// Displays configured MCP (Model Context Protocol) servers
/// and allows adding/removing them.
class McpSection extends ConsumerStatefulWidget {
  const McpSection({super.key});

  @override
  ConsumerState<McpSection> createState() => _McpSectionState();
}

class _McpSectionState extends ConsumerState<McpSection> {
  bool _isAddingServer = false;
  final _nameController = TextEditingController();
  final _commandController = TextEditingController();
  final _argsController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
    _argsController.dispose();
    super.dispose();
  }

  void _resetForm() {
    _nameController.clear();
    _commandController.clear();
    _argsController.clear();
    setState(() => _isAddingServer = false);
  }

  Future<void> _addServer() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final command = _commandController.text.trim();
    final argsText = _argsController.text.trim();
    final args = argsText.isEmpty
        ? <String>[]
        : argsText.split(' ').where((s) => s.isNotEmpty).toList();

    try {
      await addStdioMcpServer(
        ref,
        name: name,
        command: command,
        args: args,
      );

      _resetForm();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('MCP server "$name" added'),
            backgroundColor: BrandColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding server: $e'),
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
    return Card(
      margin: EdgeInsets.only(bottom: Spacing.sm),
      color: isDark
          ? BrandColors.nightSurfaceElevated
          : BrandColors.stone.withValues(alpha: 0.3),
      child: ListTile(
        leading: Icon(
          server.isStdio ? Icons.terminal : Icons.cloud,
          color: BrandColors.forest,
        ),
        title: Text(
          server.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              server.displayCommand,
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
                fontFamily: 'monospace',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (server.description != null) ...[
              SizedBox(height: Spacing.xs),
              Text(
                server.description!,
                style: TextStyle(
                  fontSize: TypographyTokens.labelSmall,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: BrandColors.error),
          onPressed: () => _removeServer(server.name),
          tooltip: 'Remove server',
        ),
      ),
    );
  }

  Widget _buildAddServerForm(bool isDark) {
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
              'Add MCP Server',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            SizedBox(height: Spacing.md),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Server Name',
                hintText: 'e.g., glif',
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
              controller: _commandController,
              decoration: const InputDecoration(
                labelText: 'Command',
                hintText: 'e.g., npx',
                border: OutlineInputBorder(),
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
              decoration: const InputDecoration(
                labelText: 'Arguments (space-separated)',
                hintText: 'e.g., -y @glifxyz/glif-mcp-server@latest',
                border: OutlineInputBorder(),
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
                  onPressed: _addServer,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Server'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BrandColors.forest,
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
          subtitle: 'Model Context Protocol servers for extended capabilities',
          icon: Icons.extension,
        ),
        SizedBox(height: Spacing.lg),

        // Server list
        serversAsync.when(
          data: (servers) {
            if (servers.isEmpty && !_isAddingServer) {
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
                      Icons.extension_off,
                      size: 48,
                      color: BrandColors.driftwood,
                    ),
                    SizedBox(height: Spacing.md),
                    Text(
                      'No MCP servers configured',
                      style: TextStyle(
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                    ),
                    SizedBox(height: Spacing.md),
                    FilledButton.icon(
                      onPressed: () => setState(() => _isAddingServer = true),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Server'),
                      style: FilledButton.styleFrom(
                        backgroundColor: BrandColors.forest,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                ...servers.map((server) => _buildServerCard(server, isDark)),
                if (_isAddingServer) ...[
                  SizedBox(height: Spacing.md),
                  _buildAddServerForm(isDark),
                ] else ...[
                  SizedBox(height: Spacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _isAddingServer = true),
                      icon: const Icon(Icons.add),
                      label: const Text('Add MCP Server'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BrandColors.forest,
                        side: BorderSide(color: BrandColors.forest),
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
                  'Error loading MCP servers',
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
                  onPressed: () => refreshMcpServers(ref),
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
