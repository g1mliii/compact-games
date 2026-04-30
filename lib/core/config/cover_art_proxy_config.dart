class CoverArtProxyConfig {
  const CoverArtProxyConfig({
    this.url = const String.fromEnvironment('COMPACT_GAMES_SGDB_PROXY_URL'),
    this.token = const String.fromEnvironment('COMPACT_GAMES_SGDB_TOKEN'),
  });

  final String url;
  final String token;

  bool get isConfigured => url.trim().isNotEmpty && token.trim().isNotEmpty;
}
