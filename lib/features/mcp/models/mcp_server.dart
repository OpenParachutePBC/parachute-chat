/// Represents an MCP (Model Context Protocol) server configuration.
/// Servers can be stdio-based (command + args) or HTTP-based (url).
class McpServer {
  final String name;
  final String? command;
  final List<String>? args;
  final Map<String, String>? env;
  final String? url;
  final Map<String, String>? headers; // Custom headers for HTTP servers
  final String? description;
  final String displayType;
  final String displayCommand;
  final bool builtin;

  // Remote server auth fields
  final String? auth; // 'none', 'bearer', 'oauth'
  final bool authRequired;
  final List<String>? scopes;
  final List<String>? validationErrors;

  McpServer({
    required this.name,
    this.command,
    this.args,
    this.env,
    this.url,
    this.headers,
    this.description,
    String? displayType,
    String? displayCommand,
    this.builtin = false,
    this.auth,
    this.authRequired = false,
    this.scopes,
    this.validationErrors,
  })  : displayType = displayType ?? (command != null ? 'stdio' : 'http'),
        displayCommand = displayCommand ??
            (command != null
                ? '$command ${args?.join(' ') ?? ''}'
                : url ?? 'N/A');

  factory McpServer.fromJson(Map<String, dynamic> json) {
    return McpServer(
      name: json['name'] as String,
      command: json['command'] as String?,
      args: (json['args'] as List<dynamic>?)?.cast<String>(),
      env: (json['env'] as Map<String, dynamic>?)?.cast<String, String>(),
      url: json['url'] as String?,
      headers: (json['headers'] as Map<String, dynamic>?)?.cast<String, String>(),
      description: json['_description'] as String?,
      displayType: json['displayType'] as String?,
      displayCommand: json['displayCommand'] as String?,
      builtin: json['builtin'] as bool? ?? false,
      auth: json['auth'] as String?,
      authRequired: json['authRequired'] as bool? ?? false,
      scopes: (json['scopes'] as List<dynamic>?)?.cast<String>(),
      validationErrors: (json['validationErrors'] as List<dynamic>?)?.cast<String>(),
    );
  }

  Map<String, dynamic> toJson() {
    final config = <String, dynamic>{};
    if (command != null) config['command'] = command;
    if (args != null) config['args'] = args;
    if (env != null) config['env'] = env;
    if (url != null) config['url'] = url;
    if (headers != null) config['headers'] = headers;
    if (description != null) config['_description'] = description;
    if (auth != null) config['auth'] = auth;
    if (scopes != null) config['scopes'] = scopes;
    return config;
  }

  /// Whether this is a stdio-based server (vs HTTP)
  bool get isStdio => command != null;

  /// Whether this is an HTTP-based server
  bool get isHttp => url != null;

  /// Whether this server uses OAuth authentication
  bool get isOAuth => auth == 'oauth';

  /// Whether this server uses bearer token authentication
  bool get isBearer => auth == 'bearer';

  /// Whether this server has configuration errors
  bool get hasValidationErrors => validationErrors?.isNotEmpty ?? false;

  @override
  String toString() => 'McpServer($name: $displayType)';
}
