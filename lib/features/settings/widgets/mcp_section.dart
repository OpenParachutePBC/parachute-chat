import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/features/mcp/models/mcp_server.dart';
import 'package:parachute_chat/features/mcp/providers/mcp_providers.dart';
import 'package:parachute_chat/features/mcp/services/mcp_service.dart';
import 'package:url_launcher/url_launcher.dart';
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
  final _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// Whether editing a remote (HTTP) server vs stdio
  bool _isRemoteServer = false;

  /// Environment variables as a list of key-value pairs for the form
  final List<_EnvVar> _envVars = [];

  /// Status of each MCP server (name -> test result)
  final Map<String, McpTestResult> _serverStatus = {};

  /// Currently testing servers
  final Set<String> _testingServers = {};

  /// Expanded servers (showing tools)
  final Set<String> _expandedServers = {};

  /// Tools for each server (name -> tools result)
  final Map<String, McpToolsResult> _serverTools = {};

  /// Currently loading tools for servers
  final Set<String> _loadingTools = {};

  /// OAuth status for remote servers
  final Map<String, McpOAuthStatus> _oauthStatus = {};

  /// Currently loading OAuth status
  final Set<String> _loadingOAuth = {};

  /// Currently connecting OAuth
  final Set<String> _connectingOAuth = {};

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
    _argsController.dispose();
    _descriptionController.dispose();
    _urlController.dispose();
    for (final env in _envVars) {
      env.dispose();
    }
    super.dispose();
  }

  void _resetForm() {
    _nameController.clear();
    _commandController.clear();
    _argsController.clear();
    _descriptionController.clear();
    _urlController.clear();
    for (final env in _envVars) {
      env.dispose();
    }
    _envVars.clear();
    setState(() {
      _isEditing = false;
      _editingServerName = null;
      _isRemoteServer = false;
    });
  }

  void _startEditing(McpServer server) {
    _nameController.text = server.name;
    _commandController.text = server.command ?? '';
    _argsController.text = server.args?.join(' ') ?? '';
    _descriptionController.text = server.description ?? '';
    _urlController.text = server.url ?? '';

    // Load environment variables
    for (final env in _envVars) {
      env.dispose();
    }
    _envVars.clear();
    if (server.env != null) {
      for (final entry in server.env!.entries) {
        _envVars.add(_EnvVar(key: entry.key, value: entry.value));
      }
    }

    setState(() {
      _isEditing = true;
      _editingServerName = server.name;
      _isRemoteServer = server.isHttp;
    });
  }

  void _startAdding() {
    _resetForm();
    setState(() {
      _isEditing = true;
      _editingServerName = null;
    });
  }

  /// Show dialog to paste and import MCP config
  /// Supports formats like:
  /// - Claude Desktop format: { "mcpServers": { "name": { config } } }
  /// - Direct format: { "name": { "command": "...", "args": [...] } }
  /// - Minimal format: { "command": "...", "args": [...] }
  Future<void> _showImportDialog() async {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    try {
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import MCP Config'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paste your MCP server JSON config below:',
                  style: TextStyle(
                    fontSize: TypographyTokens.bodySmall,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                ),
                SizedBox(height: Spacing.md),
                TextField(
                  controller: controller,
                  maxLines: 10,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    hintText: '{\n  "mcpServers": {\n    "name": {\n      "command": "npx",\n      ...\n    }\n  }\n}',
                    hintStyle: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: isDark
                          ? BrandColors.nightTextSecondary.withValues(alpha: 0.5)
                          : BrandColors.driftwood.withValues(alpha: 0.5),
                    ),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: isDark
                        ? BrandColors.nightSurface
                        : BrandColors.cream.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              style: FilledButton.styleFrom(
                backgroundColor: BrandColors.forest,
              ),
              child: const Text('Import'),
            ),
          ],
        ),
      );

      if (result == null || result.trim().isEmpty) return;

      _parseAndImportConfig(result.trim());
    } finally {
      // Always dispose the controller to prevent memory leaks
      controller.dispose();
    }
  }

  void _parseAndImportConfig(String text) {
    try {
      // Try to parse as JSON
      Map<String, dynamic> parsed;
      try {
        parsed = jsonDecode(text) as Map<String, dynamic>;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Invalid JSON format'),
              backgroundColor: BrandColors.error,
            ),
          );
        }
        return;
      }

      // Check for Claude Desktop format: { "mcpServers": { ... } }
      if (parsed.containsKey('mcpServers')) {
        final mcpServers = parsed['mcpServers'];
        if (mcpServers is Map<String, dynamic>) {
          parsed = mcpServers;
        }
      }

      // Check if it's a single MCP config (has "command" or "url" at top level)
      // or a wrapped config (server name as key)
      String? serverName;
      Map<String, dynamic>? serverConfig;

      if (parsed.containsKey('command') || parsed.containsKey('url')) {
        // Direct config without name wrapper - prompt for name
        serverConfig = parsed;
        serverName = null;
      } else if (parsed.length == 1) {
        // Wrapped config: { "name": { config } }
        serverName = parsed.keys.first;
        final configValue = parsed[serverName];
        if (configValue is Map<String, dynamic>) {
          serverConfig = configValue;
        }
      } else if (parsed.length > 1) {
        // Multiple servers - let user pick one or import all?
        // For now, just take the first one
        serverName = parsed.keys.first;
        final configValue = parsed[serverName];
        if (configValue is Map<String, dynamic>) {
          serverConfig = configValue;
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Found ${parsed.length} servers, importing "$serverName"'),
              backgroundColor: BrandColors.warning,
            ),
          );
        }
      }

      if (serverConfig == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Could not find MCP server config in JSON'),
              backgroundColor: BrandColors.error,
            ),
          );
        }
        return;
      }

      // Populate the form
      _resetForm();

      if (serverName != null) {
        _nameController.text = serverName;
      }

      // Check if it's a remote (URL-based) or stdio (command-based) server
      final isRemote = serverConfig.containsKey('url');

      if (isRemote) {
        _urlController.text = serverConfig['url'] as String? ?? '';
      } else {
        if (serverConfig['command'] != null) {
          _commandController.text = serverConfig['command'] as String;
        }

        if (serverConfig['args'] != null) {
          final args = serverConfig['args'] as List<dynamic>;
          _argsController.text = args.map((a) => a.toString()).join(' ');
        }

        // Load environment variables (only for stdio)
        if (serverConfig['env'] != null) {
          final envMap = serverConfig['env'] as Map<String, dynamic>;
          for (final entry in envMap.entries) {
            String value = entry.value.toString();
            // If value is a placeholder like ${VAR} or a dummy value, leave it empty
            if (value.startsWith(r'${') && value.endsWith('}')) {
              value = ''; // User needs to fill this in
            } else if (value == 'your-token-here' ||
                value == 'your-api-key-here' ||
                value == 'YOUR_API_KEY' ||
                value.toLowerCase().contains('your-') ||
                value.toLowerCase().contains('your_')) {
              value = ''; // Common placeholder values
            }
            _envVars.add(_EnvVar(key: entry.key, value: value));
          }
        }
      }

      if (serverConfig['_description'] != null) {
        _descriptionController.text = serverConfig['_description'] as String;
      }

      setState(() {
        _isEditing = true;
        _editingServerName = null;
        _isRemoteServer = isRemote;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(serverName != null
                ? 'Imported "$serverName" - fill in any empty values and save'
                : 'Imported config - add a name and save'),
            backgroundColor: BrandColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing config: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
  }

  Future<void> _saveServer() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();

    final isNew = _editingServerName == null;
    final oldName = _editingServerName;

    try {
      // If editing and name changed, remove old entry first
      if (!isNew && oldName != null && oldName != name) {
        await removeMcpServer(ref, oldName);
      }

      if (_isRemoteServer) {
        // Remote (HTTP) server
        final url = _urlController.text.trim();
        await addHttpMcpServer(
          ref,
          name: name,
          url: url,
          description: description.isEmpty ? null : description,
        );
      } else {
        // Stdio server
        final command = _commandController.text.trim();
        final argsText = _argsController.text.trim();
        final args = argsText.isEmpty
            ? <String>[]
            : argsText.split(' ').where((s) => s.isNotEmpty).toList();

        // Build environment variables map from non-empty entries
        final Map<String, String>? env = _envVars.isEmpty
            ? null
            : Map.fromEntries(
                _envVars
                    .where((e) => e.keyController.text.trim().isNotEmpty)
                    .map((e) => MapEntry(
                          e.keyController.text.trim(),
                          e.valueController.text.trim(),
                        )),
              );

        await addStdioMcpServer(
          ref,
          name: name,
          command: command,
          args: args,
          description: description.isEmpty ? null : description,
          env: env?.isEmpty == true ? null : env,
        );
      }

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

  Future<void> _testServer(String name) async {
    if (_testingServers.contains(name)) return;

    setState(() {
      _testingServers.add(name);
    });

    try {
      final service = ref.read(mcpServiceProvider);
      final result = await service.testServer(name);

      if (mounted) {
        setState(() {
          _serverStatus[name] = result;
          _testingServers.remove(name);
        });

        // Show snackbar with result
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.isOk
                ? '✓ ${result.name} is working'
                : '✗ ${result.name}: ${result.error ?? "Unknown error"}'),
            backgroundColor: result.isOk ? BrandColors.success : BrandColors.error,
            duration: Duration(seconds: result.isOk ? 2 : 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testingServers.remove(name);
        });
      }
    }
  }

  Future<void> _testAllServers(List<McpServer> servers) async {
    for (final server in servers) {
      await _testServer(server.name);
    }
  }

  /// Toggle showing tools for a server
  Future<void> _toggleServerTools(String name) async {
    if (_expandedServers.contains(name)) {
      setState(() {
        _expandedServers.remove(name);
      });
      return;
    }

    // Expand and load tools if not already loaded
    setState(() {
      _expandedServers.add(name);
    });

    if (!_serverTools.containsKey(name)) {
      await _loadServerTools(name);
    }
  }

  /// Load tools for a server
  Future<void> _loadServerTools(String name) async {
    if (_loadingTools.contains(name)) return;

    setState(() {
      _loadingTools.add(name);
    });

    try {
      final service = ref.read(mcpServiceProvider);
      final result = await service.getServerTools(name);

      if (mounted) {
        setState(() {
          _serverTools[name] = result;
          _loadingTools.remove(name);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingTools.remove(name);
        });
      }
    }
  }

  /// Load OAuth status for a remote server
  Future<void> _loadOAuthStatus(String name) async {
    if (_loadingOAuth.contains(name)) return;

    setState(() {
      _loadingOAuth.add(name);
    });

    try {
      final service = ref.read(mcpServiceProvider);
      final status = await service.getOAuthStatus(name);

      if (mounted) {
        setState(() {
          _oauthStatus[name] = status;
          _loadingOAuth.remove(name);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingOAuth.remove(name);
        });
      }
    }
  }

  /// Start OAuth flow for a remote server
  ///
  /// Uses localhost redirect. After authorization, the browser will try to
  /// redirect to localhost (which won't load), and the user copies the URL
  /// containing the authorization code.
  Future<void> _startOAuthFlow(McpServer server) async {
    if (_connectingOAuth.contains(server.name)) return;

    setState(() {
      _connectingOAuth.add(server.name);
    });

    try {
      final service = ref.read(mcpServiceProvider);

      // Use localhost redirect - browser will fail to load it, but the URL
      // will contain the authorization code for the user to copy
      const redirectUri = 'http://localhost:3333/oauth/callback';

      final result = await service.startOAuthFlow(
        server.name,
        redirectUri: redirectUri,
        scopes: server.scopes,
      );

      // Show OAuth flow dialog
      if (mounted) {
        final oauthResult = await _showOAuthFlow(
          serverName: server.name,
          authUrl: result.authorizationUrl,
          state: result.state,
          isOob: result.isOob,
        );

        if (oauthResult != null && oauthResult.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully connected to ${server.name}!'),
              backgroundColor: BrandColors.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('OAuth error: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _connectingOAuth.remove(server.name);
        });
        // Refresh status regardless of outcome
        await _loadOAuthStatus(server.name);
      }
    }
  }

  /// Show OAuth flow - opens browser and handles code entry
  Future<McpOAuthCallbackResult?> _showOAuthFlow({
    required String serverName,
    required String authUrl,
    required String state,
    required bool isOob,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final codeController = TextEditingController();

    // Open browser with the auth URL
    final uri = Uri.parse(authUrl);
    debugPrint('[OAuth] Attempting to launch URL: $authUrl');

    try {
      final canLaunch = await canLaunchUrl(uri);
      debugPrint('[OAuth] canLaunchUrl: $canLaunch');

      if (canLaunch) {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        debugPrint('[OAuth] launchUrl result: $launched');
        if (!launched) {
          // Try with platform default mode
          debugPrint('[OAuth] Trying with platformDefault mode...');
          await launchUrl(uri, mode: LaunchMode.platformDefault);
        }
      } else {
        debugPrint('[OAuth] Cannot launch URL, trying anyway...');
        // Some platforms return false for canLaunchUrl but still work
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[OAuth] Error launching URL: $e');
      // Show error but continue to show dialog - user can manually open URL
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open browser. Please open this URL manually:\n$authUrl'),
            backgroundColor: BrandColors.warning,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }

    // Show dialog to collect the authorization code
    // For OOB flow: just paste the code shown on the page
    // For localhost redirect: paste the whole URL from address bar
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.login, color: BrandColors.turquoise),
            SizedBox(width: Spacing.sm),
            Expanded(child: Text('Connect to $serverName')),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isOob
                    ? 'After authorizing in your browser, you\'ll see an authorization code. '
                      'Copy that code and paste it here:'
                    : 'After authorizing, your browser will try to go to a page that won\'t load '
                      '(starting with "localhost"). That\'s expected! Copy the entire URL from '
                      'your browser\'s address bar and paste it here:',
                style: TextStyle(
                  fontSize: TypographyTokens.bodySmall,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
              ),
              SizedBox(height: Spacing.md),
              // Button to copy/open URL if browser didn't launch
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: authUrl));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('URL copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                  // Also try to launch again
                  try {
                    await launchUrl(Uri.parse(authUrl), mode: LaunchMode.externalApplication);
                  } catch (_) {}
                },
                icon: const Icon(Icons.open_in_browser, size: 16),
                label: const Text('Open/Copy Auth URL'),
              ),
              SizedBox(height: Spacing.md),
              TextField(
                controller: codeController,
                decoration: InputDecoration(
                  labelText: isOob ? 'Authorization Code' : 'Callback URL',
                  hintText: isOob ? 'Paste the code here...' : 'http://localhost:3333/oauth/callback?code=...',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: isDark
                      ? BrandColors.nightSurface
                      : BrandColors.cream.withValues(alpha: 0.5),
                ),
                maxLines: isOob ? 1 : 2,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              if (!isOob) ...[
                SizedBox(height: Spacing.sm),
                Text(
                  'The URL will look like: http://localhost:3333/oauth/callback?code=ABC123&state=XYZ',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    color: isDark
                        ? BrandColors.nightTextSecondary.withValues(alpha: 0.7)
                        : BrandColors.driftwood.withValues(alpha: 0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, codeController.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: BrandColors.forest),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    codeController.dispose();

    if (result == null || result.isEmpty) {
      return null;
    }

    // Extract the authorization code
    try {
      String code;

      if (isOob) {
        // OOB flow: user pasted just the code
        code = result;
      } else {
        // Localhost redirect: user pasted the full URL
        final callbackUri = Uri.parse(result);
        final urlCode = callbackUri.queryParameters['code'];
        final returnedState = callbackUri.queryParameters['state'];
        final error = callbackUri.queryParameters['error'];

        if (error != null) {
          throw Exception('OAuth error: $error');
        }

        if (urlCode == null || urlCode.isEmpty) {
          throw Exception('No authorization code in callback URL');
        }

        // Verify state matches (CSRF protection)
        if (returnedState != state) {
          throw Exception('State mismatch - possible CSRF attack');
        }

        code = urlCode;
      }

      // Forward the code to our actual server to exchange for tokens
      final service = ref.read(mcpServiceProvider);
      return await service.handleOAuthCallback(
        serverName,
        code: code,
        state: state,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete OAuth: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
      return null;
    }
  }

  /// Disconnect from a remote server
  Future<void> _disconnectServer(String name) async {
    try {
      final service = ref.read(mcpServiceProvider);
      await service.logout(name);

      // Remove cached status
      setState(() {
        _oauthStatus.remove(name);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Disconnected from $name'),
            backgroundColor: BrandColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error disconnecting: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
  }

  /// Show dialog to enter API token for bearer auth
  Future<void> _showTokenDialog(McpServer server) async {
    final tokenController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String? token;
    try {
      token = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Add API Token for ${server.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter your API token or key:',
                style: TextStyle(
                  fontSize: TypographyTokens.bodySmall,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
              ),
              SizedBox(height: Spacing.md),
              TextField(
                controller: tokenController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'API Token',
                  hintText: 'sk-...',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: isDark
                      ? BrandColors.nightSurface
                      : BrandColors.cream.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, tokenController.text.trim()),
              style: FilledButton.styleFrom(backgroundColor: BrandColors.forest),
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } finally {
      // Always dispose the controller to prevent memory leaks
      tokenController.dispose();
    }

    if (token == null || token.isEmpty) return;

    try {
      final service = ref.read(mcpServiceProvider);
      await service.storeToken(server.name, token: token);

      // Refresh OAuth status
      await _loadOAuthStatus(server.name);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Token saved for ${server.name}'),
            backgroundColor: BrandColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving token: $e'),
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

  void _addEnvVar() {
    setState(() {
      _envVars.add(_EnvVar());
    });
  }

  void _removeEnvVar(int index) {
    setState(() {
      _envVars[index].dispose();
      _envVars.removeAt(index);
    });
  }

  Widget _buildEnvVarsSection(bool isDark) {
    final textColor = isDark ? BrandColors.nightText : BrandColors.charcoal;
    final subtitleColor = isDark
        ? BrandColors.nightTextSecondary
        : BrandColors.driftwood;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.vpn_key_outlined,
                  size: 18,
                  color: BrandColors.turquoise,
                ),
                SizedBox(width: Spacing.sm),
                Text(
                  'Environment Variables',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: TypographyTokens.bodyMedium,
                    color: textColor,
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: _addEnvVar,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add'),
              style: TextButton.styleFrom(
                foregroundColor: BrandColors.turquoise,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        SizedBox(height: Spacing.xs),
        Text(
          'API keys and secrets needed by this MCP server',
          style: TextStyle(
            fontSize: TypographyTokens.labelSmall,
            color: subtitleColor,
          ),
        ),
        if (_envVars.isEmpty) ...[
          SizedBox(height: Spacing.md),
          Container(
            padding: EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: isDark
                  ? BrandColors.nightSurface
                  : BrandColors.stone.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: subtitleColor,
                ),
                SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    'No environment variables configured',
                    style: TextStyle(
                      fontSize: TypographyTokens.labelSmall,
                      color: subtitleColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          SizedBox(height: Spacing.md),
          ..._envVars.asMap().entries.map((entry) {
            final index = entry.key;
            final envVar = entry.value;
            return Padding(
              padding: EdgeInsets.only(bottom: Spacing.sm),
              child: Row(
                children: [
                  // Key field
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: envVar.keyController,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        hintText: 'GLIF_API_KEY',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: isDark
                            ? BrandColors.nightSurface
                            : BrandColors.cream.withValues(alpha: 0.5),
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                  SizedBox(width: Spacing.sm),
                  // Value field
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: envVar.valueController,
                      obscureText: envVar.obscured,
                      decoration: InputDecoration(
                        labelText: 'Value',
                        hintText: 'sk-...',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: isDark
                            ? BrandColors.nightSurface
                            : BrandColors.cream.withValues(alpha: 0.5),
                        suffixIcon: IconButton(
                          icon: Icon(
                            envVar.obscured
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 18,
                          ),
                          onPressed: () {
                            setState(() {
                              envVar.obscured = !envVar.obscured;
                            });
                          },
                          tooltip: envVar.obscured ? 'Show' : 'Hide',
                        ),
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                  SizedBox(width: Spacing.xs),
                  // Delete button
                  IconButton(
                    icon: Icon(Icons.close, color: BrandColors.error, size: 18),
                    onPressed: () => _removeEnvVar(index),
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildServerCard(McpServer server, bool isDark) {
    final cardColor = isDark
        ? BrandColors.nightSurfaceElevated
        : Colors.white;
    final textColor = isDark ? BrandColors.nightText : BrandColors.charcoal;
    final subtitleColor = isDark
        ? BrandColors.nightTextSecondary
        : BrandColors.driftwood;

    // Get status for this server
    final status = _serverStatus[server.name];
    final isTesting = _testingServers.contains(server.name);
    final isExpanded = _expandedServers.contains(server.name);
    final isLoadingTools = _loadingTools.contains(server.name);
    final tools = _serverTools[server.name];

    // OAuth status for remote servers
    final oauthStatus = _oauthStatus[server.name];
    final isLoadingOAuth = _loadingOAuth.contains(server.name);
    final isConnectingOAuth = _connectingOAuth.contains(server.name);

    // Load OAuth status on first render if it's a remote server
    // This will discover OAuth support even if not explicitly configured
    if (server.isHttp && !_oauthStatus.containsKey(server.name) && !_loadingOAuth.contains(server.name)) {
      // Schedule this after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadOAuthStatus(server.name);
      });
    }

    // Determine border color based on status
    Color borderColor;
    if (status != null) {
      if (status.isOk) {
        borderColor = BrandColors.success.withValues(alpha: 0.5);
      } else if (status.isError) {
        borderColor = BrandColors.error.withValues(alpha: 0.5);
      } else {
        borderColor = isDark
            ? BrandColors.nightForest.withValues(alpha: 0.3)
            : BrandColors.forest.withValues(alpha: 0.2);
      }
    } else {
      borderColor = isDark
          ? BrandColors.nightForest.withValues(alpha: 0.3)
          : BrandColors.forest.withValues(alpha: 0.2);
    }

    return Container(
      margin: EdgeInsets.only(bottom: Spacing.sm),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: borderColor, width: status != null ? 2 : 1),
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
      child: Column(
        children: [
          // Main card content
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _toggleServerTools(server.name),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(Radii.md),
                bottom: isExpanded ? Radius.zero : Radius.circular(Radii.md),
              ),
              child: Padding(
                padding: EdgeInsets.all(Spacing.md),
                child: Row(
                  children: [
                    // Icon with status indicator
                    Stack(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: server.isHttp
                                ? BrandColors.turquoise.withValues(alpha: 0.1)
                                : BrandColors.forest.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(Radii.sm),
                          ),
                          child: Icon(
                            server.isStdio ? Icons.terminal : Icons.cloud,
                            color: server.isHttp ? BrandColors.turquoise : BrandColors.forest,
                            size: 20,
                          ),
                        ),
                        // Status indicator dot (for stdio) or OAuth indicator (for http)
                        if (server.isHttp && server.authRequired)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: oauthStatus?.authenticated == true
                                    ? BrandColors.success
                                    : BrandColors.warning,
                                shape: BoxShape.circle,
                                border: Border.all(color: cardColor, width: 2),
                              ),
                              child: Icon(
                                oauthStatus?.authenticated == true
                                    ? Icons.check
                                    : Icons.key,
                                size: 8,
                                color: Colors.white,
                              ),
                            ),
                          )
                        else if (status != null)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: status.isOk
                                    ? BrandColors.success
                                    : BrandColors.error,
                                shape: BoxShape.circle,
                                border: Border.all(color: cardColor, width: 2),
                              ),
                              child: Icon(
                                status.isOk ? Icons.check : Icons.close,
                                size: 8,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(width: Spacing.md),
                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                server.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: TypographyTokens.bodyMedium,
                                  color: textColor,
                                ),
                              ),
                              // Show tools count if loaded
                              if (tools != null && tools.hasTools) ...[
                                SizedBox(width: Spacing.sm),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: Spacing.sm,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: BrandColors.turquoise.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${tools.tools.length} tools',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: BrandColors.turquoise,
                                    ),
                                  ),
                                ),
                              ],
                              // Show status text if error
                              if (status != null && status.isError) ...[
                                SizedBox(width: Spacing.sm),
                                Expanded(
                                  child: Text(
                                    status.error ?? 'Error',
                                    style: TextStyle(
                                      fontSize: TypographyTokens.labelSmall,
                                      color: BrandColors.error,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
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
                          // Show auth status for remote servers that need auth
                          if (server.isHttp && (server.authRequired || oauthStatus?.authRequired == true)) ...[
                            SizedBox(height: Spacing.xs),
                            Row(
                              children: [
                                Icon(
                                  oauthStatus?.authenticated == true
                                      ? Icons.check_circle_outline
                                      : Icons.warning_amber_outlined,
                                  size: 14,
                                  color: oauthStatus?.authenticated == true
                                      ? BrandColors.success
                                      : BrandColors.warning,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  isLoadingOAuth
                                      ? 'Checking auth...'
                                      : oauthStatus?.authenticated == true
                                          ? oauthStatus?.isExpired == true
                                              ? 'Token expired'
                                              : 'Connected'
                                          : (oauthStatus?.supportsOAuth ?? server.isOAuth)
                                              ? 'OAuth required'
                                              : 'Token required',
                                  style: TextStyle(
                                    fontSize: TypographyTokens.labelSmall,
                                    color: oauthStatus?.authenticated == true
                                        ? BrandColors.success
                                        : BrandColors.warning,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          // Show validation errors
                          if (server.hasValidationErrors) ...[
                            SizedBox(height: Spacing.xs),
                            Text(
                              '⚠️ ${server.validationErrors!.first}',
                              style: TextStyle(
                                fontSize: TypographyTokens.labelSmall,
                                color: BrandColors.error,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          // Show hint if available
                          if (status?.hint != null) ...[
                            SizedBox(height: Spacing.xs),
                            Text(
                              '💡 ${status!.hint}',
                              style: TextStyle(
                                fontSize: TypographyTokens.labelSmall,
                                color: BrandColors.warning,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Expand/collapse indicator
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: subtitleColor,
                      size: 20,
                    ),
                    SizedBox(width: Spacing.xs),
                    // Actions
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // OAuth Connect/Disconnect button for remote servers
                        // Show for HTTP servers that either have authRequired or have discovered OAuth
                        if (server.isHttp && (server.authRequired || oauthStatus?.authRequired == true)) ...[
                          if (isConnectingOAuth)
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(BrandColors.turquoise),
                              ),
                            )
                          else if (oauthStatus?.authenticated == true)
                            IconButton(
                              icon: Icon(Icons.logout,
                                  color: BrandColors.warning, size: 20),
                              onPressed: () => _disconnectServer(server.name),
                              tooltip: 'Disconnect',
                              visualDensity: VisualDensity.compact,
                            )
                          else
                            IconButton(
                              icon: Icon(Icons.login,
                                  color: BrandColors.turquoise, size: 20),
                              onPressed: () => (oauthStatus?.supportsOAuth ?? server.isOAuth)
                                  ? _startOAuthFlow(server)
                                  : _showTokenDialog(server),
                              tooltip: (oauthStatus?.supportsOAuth ?? server.isOAuth)
                                  ? 'Connect with OAuth'
                                  : 'Add API Token',
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                        // Test button
                        isTesting
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(BrandColors.forest),
                                ),
                              )
                            : IconButton(
                                icon: Icon(Icons.play_circle_outline,
                                    color: BrandColors.forest, size: 20),
                                onPressed: () => _testServer(server.name),
                                tooltip: 'Test server',
                                visualDensity: VisualDensity.compact,
                              ),
                        // Don't show edit for built-in or remote servers (config is different)
                        if (!server.builtin && server.isStdio)
                          IconButton(
                            icon: Icon(Icons.edit_outlined,
                                color: BrandColors.turquoise, size: 20),
                            onPressed: () => _startEditing(server),
                            tooltip: 'Edit',
                            visualDensity: VisualDensity.compact,
                          ),
                        // Don't show delete for built-in servers
                        if (!server.builtin)
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
          // Expanded tools section
          if (isExpanded) ...[
            Divider(height: 1, color: borderColor),
            _buildToolsSection(server.name, isDark, isLoadingTools, tools),
          ],
        ],
      ),
    );
  }

  Widget _buildToolsSection(
    String serverName,
    bool isDark,
    bool isLoading,
    McpToolsResult? tools,
  ) {
    final subtitleColor = isDark
        ? BrandColors.nightTextSecondary
        : BrandColors.driftwood;

    return Container(
      padding: EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.build_outlined,
                size: 16,
                color: BrandColors.turquoise,
              ),
              SizedBox(width: Spacing.sm),
              Text(
                'Available Tools',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: TypographyTokens.bodySmall,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),
              if (isLoading) ...[
                SizedBox(width: Spacing.sm),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(BrandColors.turquoise),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: Spacing.sm),
          if (isLoading)
            Padding(
              padding: EdgeInsets.symmetric(vertical: Spacing.md),
              child: Text(
                'Loading tools...',
                style: TextStyle(
                  fontSize: TypographyTokens.labelSmall,
                  color: subtitleColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else if (tools == null)
            Padding(
              padding: EdgeInsets.symmetric(vertical: Spacing.md),
              child: Text(
                'Tap to load tools',
                style: TextStyle(
                  fontSize: TypographyTokens.labelSmall,
                  color: subtitleColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else if (tools.hasError)
            Container(
              padding: EdgeInsets.all(Spacing.sm),
              decoration: BoxDecoration(
                color: BrandColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: BrandColors.error),
                  SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      tools.error!,
                      style: TextStyle(
                        fontSize: TypographyTokens.labelSmall,
                        color: BrandColors.error,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _loadServerTools(serverName),
                    style: TextButton.styleFrom(
                      foregroundColor: BrandColors.error,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (!tools.hasTools)
            Padding(
              padding: EdgeInsets.symmetric(vertical: Spacing.md),
              child: Text(
                'No tools available',
                style: TextStyle(
                  fontSize: TypographyTokens.labelSmall,
                  color: subtitleColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: tools.tools.map((tool) {
                return Tooltip(
                  message: tool.description ?? 'No description',
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: Spacing.sm,
                      vertical: Spacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? BrandColors.nightSurface
                          : BrandColors.stone.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isDark
                            ? BrandColors.nightForest.withValues(alpha: 0.3)
                            : BrandColors.forest.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.code,
                          size: 12,
                          color: BrandColors.forest,
                        ),
                        SizedBox(width: 4),
                        Text(
                          tool.name,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: isDark
                                ? BrandColors.nightText
                                : BrandColors.charcoal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
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

            // Server type toggle (only for new servers)
            if (isNew) ...[
              Row(
                children: [
                  Text(
                    'Server Type:',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: TypographyTokens.bodySmall,
                      color: isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood,
                    ),
                  ),
                  SizedBox(width: Spacing.md),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Local (stdio)'),
                        icon: Icon(Icons.terminal, size: 16),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Remote (URL)'),
                        icon: Icon(Icons.cloud, size: 16),
                      ),
                    ],
                    selected: {_isRemoteServer},
                    onSelectionChanged: (selected) {
                      setState(() {
                        _isRemoteServer = selected.first;
                      });
                    },
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              SizedBox(height: Spacing.lg),
            ],

            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Server Name',
                hintText: 'e.g., glif, tally',
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

            // Show different fields based on server type
            if (_isRemoteServer) ...[
              // Remote server: URL field
              TextFormField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://mcp.example.com',
                  prefixIcon: const Icon(Icons.link),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: isDark
                      ? BrandColors.nightSurface
                      : BrandColors.cream.withValues(alpha: 0.5),
                  helperText: 'Remote MCP server endpoint',
                ),
                validator: (value) {
                  if (!_isRemoteServer) return null;
                  if (value == null || value.trim().isEmpty) {
                    return 'URL is required for remote servers';
                  }
                  final uri = Uri.tryParse(value.trim());
                  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                    return 'Enter a valid URL (https://...)';
                  }
                  return null;
                },
              ),
              SizedBox(height: Spacing.sm),
              Container(
                padding: EdgeInsets.all(Spacing.sm),
                decoration: BoxDecoration(
                  color: BrandColors.turquoise.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: BrandColors.turquoise,
                    ),
                    SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        'After adding, you\'ll be prompted to connect via OAuth or API key.',
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
            ] else ...[
              // Stdio server: command + args
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
                  if (_isRemoteServer) return null;
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
            ],
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

            // Environment Variables section (only for stdio servers)
            if (!_isRemoteServer) ...[
              SizedBox(height: Spacing.lg),
              _buildEnvVarsSection(isDark),
            ],

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
                  // Test All button when there are servers
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: _testingServers.isEmpty
                            ? () => _testAllServers(servers)
                            : null,
                        icon: _testingServers.isNotEmpty
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(BrandColors.forest),
                                ),
                              )
                            : Icon(Icons.play_arrow, size: 16),
                        label: Text(
                            _testingServers.isNotEmpty ? 'Testing...' : 'Test All'),
                        style: TextButton.styleFrom(
                          foregroundColor: BrandColors.forest,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: Spacing.sm),
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
    return Row(
      children: [
        Expanded(
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
        ),
        SizedBox(width: Spacing.sm),
        OutlinedButton.icon(
          onPressed: _showImportDialog,
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Import'),
          style: OutlinedButton.styleFrom(
            foregroundColor: BrandColors.turquoise,
            side: BorderSide(color: BrandColors.turquoise),
            padding: EdgeInsets.symmetric(
              vertical: Spacing.md,
              horizontal: Spacing.md,
            ),
          ),
        ),
      ],
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

/// Helper class for managing environment variable form fields
class _EnvVar {
  final TextEditingController keyController;
  final TextEditingController valueController;
  bool obscured;

  _EnvVar({String key = '', String value = ''})
      : keyController = TextEditingController(text: key),
        valueController = TextEditingController(text: value),
        obscured = true;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}
