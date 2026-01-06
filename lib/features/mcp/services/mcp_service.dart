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
  ///
  /// The SDK requires `type: "http"` for remote MCP servers.
  Future<McpServer> addHttpServer({
    required String name,
    required String url,
    String? description,
    Map<String, String>? headers,
  }) async {
    final config = <String, dynamic>{
      'type': 'http', // Required by Claude SDK for HTTP servers
      'url': url,
      if (headers != null) 'headers': headers,
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

  // ==========================================================================
  // OAuth Methods for Remote Servers
  // ==========================================================================

  /// Get OAuth authentication status for a remote MCP server
  Future<McpOAuthStatus> getOAuthStatus(String name) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/mcps/$name/oauth/status'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to get OAuth status: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return McpOAuthStatus.fromJson(data);
    } catch (e) {
      debugPrint('[McpService] Error getting OAuth status for $name: $e');
      rethrow;
    }
  }

  /// Start OAuth flow for a remote MCP server
  ///
  /// Returns the authorization URL to open in a browser
  Future<McpOAuthStartResult> startOAuthFlow(
    String name, {
    required String redirectUri,
    List<String>? scopes,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/mcps/$name/oauth/start'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'redirect_uri': redirectUri,
              if (scopes != null) 'scopes': scopes,
            }),
          )
          .timeout(requestTimeout);

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body)['detail'] ?? 'Unknown error';
        throw Exception('Failed to start OAuth flow: $error');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return McpOAuthStartResult.fromJson(data);
    } catch (e) {
      debugPrint('[McpService] Error starting OAuth flow for $name: $e');
      rethrow;
    }
  }

  /// Handle OAuth callback after user authorizes
  Future<McpOAuthCallbackResult> handleOAuthCallback(
    String name, {
    required String code,
    required String state,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/mcps/$name/oauth/callback'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
              'state': state,
            }),
          )
          .timeout(const Duration(seconds: 30)); // Token exchange can take longer

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body)['detail'] ?? 'Unknown error';
        throw Exception('OAuth callback failed: $error');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return McpOAuthCallbackResult.fromJson(data);
    } catch (e) {
      debugPrint('[McpService] Error handling OAuth callback for $name: $e');
      rethrow;
    }
  }

  /// Store an API token directly (for bearer auth)
  Future<bool> storeToken(
    String name, {
    required String token,
    String tokenType = 'Bearer',
    int? expiresIn,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/mcps/$name/oauth/token'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'token': token,
              'token_type': tokenType,
              if (expiresIn != null) 'expires_in': expiresIn,
            }),
          )
          .timeout(requestTimeout);

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body)['detail'] ?? 'Unknown error';
        throw Exception('Failed to store token: $error');
      }

      return true;
    } catch (e) {
      debugPrint('[McpService] Error storing token for $name: $e');
      rethrow;
    }
  }

  /// Log out from a remote MCP server (delete stored token)
  Future<bool> logout(String name) async {
    try {
      final response = await _client
          .delete(
            Uri.parse('$baseUrl/api/mcps/$name/oauth/logout'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to logout: ${response.statusCode}');
      }

      return true;
    } catch (e) {
      debugPrint('[McpService] Error logging out from $name: $e');
      rethrow;
    }
  }

  void dispose() {
    _client.close();
  }
}

/// OAuth status for a remote MCP server
class McpOAuthStatus {
  final String name;
  final String type;
  final String? auth;
  final bool authRequired;
  final bool authenticated;
  final bool? expired;
  final List<String>? scopes;
  final List<String>? discoveredScopes;
  final String? expiresAt;

  const McpOAuthStatus({
    required this.name,
    required this.type,
    this.auth,
    required this.authRequired,
    required this.authenticated,
    this.expired,
    this.scopes,
    this.discoveredScopes,
    this.expiresAt,
  });

  factory McpOAuthStatus.fromJson(Map<String, dynamic> json) {
    return McpOAuthStatus(
      name: json['name'] as String,
      type: json['type'] as String,
      auth: json['auth'] as String?,
      authRequired: json['authRequired'] as bool? ?? false,
      authenticated: json['authenticated'] as bool? ?? false,
      expired: json['expired'] as bool?,
      scopes: (json['scopes'] as List<dynamic>?)?.cast<String>(),
      discoveredScopes: (json['discoveredScopes'] as List<dynamic>?)?.cast<String>(),
      expiresAt: json['expiresAt'] as String?,
    );
  }

  /// Whether this server needs authentication and isn't authenticated yet
  bool get needsAuth => authRequired && !authenticated;

  /// Whether token is expired but was previously authenticated
  bool get isExpired => expired ?? false;

  /// Whether this server supports OAuth (vs just API token)
  bool get supportsOAuth => auth == 'oauth';
}

/// Result of starting OAuth flow
class McpOAuthStartResult {
  final String authorizationUrl;
  final String state;
  final String? redirectUri;  // Actual redirect being used (may differ from requested)
  final bool isOob;  // True if using out-of-band flow (user copies code)

  const McpOAuthStartResult({
    required this.authorizationUrl,
    required this.state,
    this.redirectUri,
    this.isOob = false,
  });

  factory McpOAuthStartResult.fromJson(Map<String, dynamic> json) {
    return McpOAuthStartResult(
      authorizationUrl: json['authorizationUrl'] as String,
      state: json['state'] as String,
      redirectUri: json['redirectUri'] as String?,
      isOob: json['isOob'] as bool? ?? false,
    );
  }
}

/// Result of OAuth callback
class McpOAuthCallbackResult {
  final bool success;
  final String serverName;
  final String? tokenType;
  final String? expiresAt;
  final List<String>? scopes;

  const McpOAuthCallbackResult({
    required this.success,
    required this.serverName,
    this.tokenType,
    this.expiresAt,
    this.scopes,
  });

  factory McpOAuthCallbackResult.fromJson(Map<String, dynamic> json) {
    return McpOAuthCallbackResult(
      success: json['success'] as bool? ?? false,
      serverName: json['serverName'] as String,
      tokenType: json['tokenType'] as String?,
      expiresAt: json['expiresAt'] as String?,
      scopes: (json['scopes'] as List<dynamic>?)?.cast<String>(),
    );
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
