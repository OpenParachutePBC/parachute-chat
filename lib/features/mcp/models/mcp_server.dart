/// Represents an MCP (Model Context Protocol) server configuration.
/// Servers can be stdio-based (command + args) or HTTP-based (url).
class McpServer {
  final String name;
  final String? command;
  final List<String>? args;
  final Map<String, String>? env;
  final String? url;
  final String? description;
  final String displayType;
  final String displayCommand;

  McpServer({
    required this.name,
    this.command,
    this.args,
    this.env,
    this.url,
    this.description,
    String? displayType,
    String? displayCommand,
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
      description: json['_description'] as String?,
      displayType: json['displayType'] as String?,
      displayCommand: json['displayCommand'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final config = <String, dynamic>{};
    if (command != null) config['command'] = command;
    if (args != null) config['args'] = args;
    if (env != null) config['env'] = env;
    if (url != null) config['url'] = url;
    if (description != null) config['_description'] = description;
    return config;
  }

  /// Whether this is a stdio-based server (vs HTTP)
  bool get isStdio => command != null;

  /// Whether this is an HTTP-based server
  bool get isHttp => url != null;

  @override
  String toString() => 'McpServer($name: $displayType)';
}
