import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/mcp_server.dart';

/// Service for managing MCP (Model Context Protocol) servers
///
/// Communicates with parachute-base server to:
/// - List configured MCP servers
/// - Add new MCP servers
/// - Remove MCP servers
class McpService {
  final String baseUrl;
  final http.Client _client;

  static const Duration requestTimeout = Duration(seconds: 30);

  McpService({required this.baseUrl}) : _client = http.Client();

  /// List all configured MCP servers
  Future<List<McpServer>> listServers() async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/mcps'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to list MCP servers: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final serversList = data['servers'] as List<dynamic>? ?? [];
      return serversList
          .map((json) => McpServer.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[McpService] Error listing servers: $e');
      rethrow;
    }
  }

  /// Get a specific MCP server by name
  Future<McpServer?> getServer(String name) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/mcps/$name'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(requestTimeout);

      if (response.statusCode == 404) {
        return null;
      }

      if (response.statusCode != 200) {
        throw Exception('Failed to get MCP server: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return McpServer.fromJson(data);
    } catch (e) {
      debugPrint('[McpService] Error getting server $name: $e');
      rethrow;
    }
  }

  /// Add or update an MCP server
  ///
  /// [name] - Server identifier
  /// [config] - Server configuration (command/args for stdio, url for HTTP)
  Future<McpServer> addServer(String name, Map<String, dynamic> config) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/mcps'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': name,
              'config': config,
            }),
          )
          .timeout(requestTimeout);

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
        throw Exception('Failed to add MCP server: $error');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return McpServer.fromJson(data['server'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[McpService] Error adding server $name: $e');
      rethrow;
    }
  }

  /// Add a stdio-based MCP server
  Future<McpServer> addStdioServer({
    required String name,
    required String command,
    List<String>? args,
    Map<String, String>? env,
    String? description,
  }) async {
    final config = <String, dynamic>{
      'command': command,
      if (args != null) 'args': args,
      if (env != null) 'env': env,
      if (description != null) '_description': description,
    };
    return addServer(name, config);
  }

  /// Add an HTTP-based MCP server
  Future<McpServer> addHttpServer({
    required String name,
    required String url,
    String? description,
  }) async {
    final config = <String, dynamic>{
      'url': url,
      if (description != null) '_description': description,
    };
    return addServer(name, config);
  }

  /// Remove an MCP server
  Future<bool> removeServer(String name) async {
    try {
      final response = await _client
          .delete(
            Uri.parse('$baseUrl/api/mcps/$name'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(requestTimeout);

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
        throw Exception('Failed to remove MCP server: $error');
      }

      return true;
    } catch (e) {
      debugPrint('[McpService] Error removing server $name: $e');
      rethrow;
    }
  }

  /// Test if an MCP server can start successfully
  ///
  /// Returns a [McpTestResult] with status and any error details
  Future<McpTestResult> testServer(String name) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/mcps/$name/test'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10)); // Longer timeout for test

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      return McpTestResult(
        name: data['name'] as String? ?? name,
        status: data['status'] as String? ?? 'unknown',
        message: data['message'] as String?,
        error: data['error'] as String?,
        hint: data['hint'] as String?,
      );
    } catch (e) {
      debugPrint('[McpService] Error testing server $name: $e');
      return McpTestResult(
        name: name,
        status: 'error',
        error: 'Connection failed: $e',
      );
    }
  }

  /// Get the list of tools provided by an MCP server
  ///
  /// Returns [McpToolsResult] with the list of tools or error
  Future<McpToolsResult> getServerTools(String name) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/mcps/$name/tools'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 15)); // Longer timeout for tools query

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final toolsList = data['tools'] as List<dynamic>? ?? [];
      final tools = toolsList
          .map((t) => McpTool.fromJson(t as Map<String, dynamic>))
          .toList();

      return McpToolsResult(
        name: data['name'] as String? ?? name,
        tools: tools,
        error: data['error'] as String?,
      );
    } catch (e) {
      debugPrint('[McpService] Error getting tools for $name: $e');
      return McpToolsResult(
        name: name,
        tools: [],
        error: 'Connection failed: $e',
      );
    }
  }

  void dispose() {
    _client.close();
  }
}

/// A tool provided by an MCP server
class McpTool {
  final String name;
  final String? description;
  final Map<String, dynamic>? inputSchema;

  const McpTool({
    required this.name,
    this.description,
    this.inputSchema,
  });

  factory McpTool.fromJson(Map<String, dynamic> json) {
    return McpTool(
      name: json['name'] as String,
      description: json['description'] as String?,
      inputSchema: json['inputSchema'] as Map<String, dynamic>?,
    );
  }
}

/// Result of getting MCP server tools
class McpToolsResult {
  final String name;
  final List<McpTool> tools;
  final String? error;

  const McpToolsResult({
    required this.name,
    required this.tools,
    this.error,
  });

  bool get hasTools => tools.isNotEmpty;
  bool get hasError => error != null;
}

/// Result of testing an MCP server
class McpTestResult {
  final String name;
  final String status; // 'ok', 'error', 'unknown'
  final String? message;
  final String? error;
  final String? hint;

  const McpTestResult({
    required this.name,
    required this.status,
    this.message,
    this.error,
    this.hint,
  });

  bool get isOk => status == 'ok';
  bool get isError => status == 'error';
}
