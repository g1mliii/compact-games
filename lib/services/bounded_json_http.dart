import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_constants.dart';

/// Coerces an untrusted JSON value to an int, or null when it is not one.
///
/// Remote payloads are inconsistent about whether numeric ids arrive as JSON
/// numbers or strings, so every reader of these endpoints needs the same
/// coercion rather than its own.
int? readJsonInt(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v),
  _ => null,
};

/// GETs [uri] and decodes a JSON object, returning null for anything unusable.
///
/// Shared by the services that read Steam's public JSON endpoints so the
/// transport rules — headers, timeout, status check, and the response size
/// bound that keeps a hostile or truncated body from being parsed — are stated
/// once. Callers pass their own [client] so a disabled or offline feature still
/// performs no work in another feature's connection pool.
///
/// Never throws: timeouts, transport errors, non-200 responses, oversized
/// bodies, and malformed JSON all collapse to null, which every caller already
/// treats as "no data".
Future<Map<String, dynamic>?> getBoundedJson(
  http.Client client,
  Uri uri, {
  required Duration timeout,
  required int maxResponseBytes,
}) async {
  try {
    final response = await client
        .get(
          uri,
          headers: const <String, String>{
            'Accept': 'application/json',
            'User-Agent': AppConstants.userAgent,
          },
        )
        .timeout(timeout);
    if (response.statusCode != 200 ||
        response.bodyBytes.length > maxResponseBytes) {
      return null;
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
