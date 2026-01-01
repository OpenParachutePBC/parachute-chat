import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/providers/feature_flags_provider.dart';
import '../models/mcp_server.dart';
import '../services/mcp_service.dart';

// ============================================================
// Service Provider
// ============================================================

/// Provider for McpService
///
/// Creates a new McpService instance with the configured server URL.
final mcpServiceProvider = Provider<McpService>((ref) {
  final urlAsync = ref.watch(aiServerUrlProvider);
  final baseUrl = urlAsync.valueOrNull ?? 'http://localhost:3333';

  final service = McpService(baseUrl: baseUrl);

  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

// ============================================================
// Data Providers
// ============================================================

/// Provider for fetching all MCP servers
///
/// Returns the list of configured MCP servers from the agent.
final mcpServersProvider = FutureProvider<List<McpServer>>((ref) async {
  final service = ref.watch(mcpServiceProvider);

  try {
    final servers = await service.listServers();
    debugPrint('[McpProviders] Loaded ${servers.length} MCP servers');
    return servers;
  } catch (e) {
    debugPrint('[McpProviders] Error loading MCP servers: $e');
    rethrow;
  }
});

/// Provider for getting a specific MCP server
final mcpServerProvider =
    FutureProvider.family<McpServer?, String>((ref, name) async {
  final service = ref.watch(mcpServiceProvider);

  try {
    return await service.getServer(name);
  } catch (e) {
    debugPrint('[McpProviders] Error getting MCP server $name: $e');
    rethrow;
  }
});

// ============================================================
// Mutation Helpers
// ============================================================

/// Add a new MCP server and refresh the list
Future<McpServer> addMcpServer(
  WidgetRef ref, {
  required String name,
  required Map<String, dynamic> config,
}) async {
  final service = ref.read(mcpServiceProvider);
  final result = await service.addServer(name, config);
  ref.invalidate(mcpServersProvider);
  return result;
}

/// Add a stdio-based MCP server
Future<McpServer> addStdioMcpServer(
  WidgetRef ref, {
  required String name,
  required String command,
  List<String>? args,
  Map<String, String>? env,
  String? description,
}) async {
  final service = ref.read(mcpServiceProvider);
  final result = await service.addStdioServer(
    name: name,
    command: command,
    args: args,
    env: env,
    description: description,
  );
  ref.invalidate(mcpServersProvider);
  return result;
}

/// Remove an MCP server and refresh the list
Future<bool> removeMcpServer(WidgetRef ref, String name) async {
  final service = ref.read(mcpServiceProvider);
  final result = await service.removeServer(name);
  ref.invalidate(mcpServersProvider);
  return result;
}

/// Refresh the MCP servers list
void refreshMcpServers(WidgetRef ref) {
  ref.invalidate(mcpServersProvider);
}
