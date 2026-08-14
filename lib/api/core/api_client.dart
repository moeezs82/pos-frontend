import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../../config/backend_config.dart';

/// A non-2xx HTTP response surfaced as a typed error.
///
/// Before this existed, [ApiClient._handleResponse] threw a bare
/// `Exception(message)` that carried no status code, so the offline-sync
/// layer couldn't tell a transient 503/429 (retry with backoff) apart from
/// a 401 (re-auth) or a permanent 422 (dead-letter). Every non-2xx response
/// now carries its [statusCode] so callers can classify it — this is the
/// foundation the sync error-taxonomy (handover doc G3/G4/G6) is built on.
///
/// Network-unreachable failures (no HTTP response at all) are still surfaced
/// as SocketException/TimeoutException/etc. and detected by isNetworkFailure;
/// an ApiException always means the server *did* answer, just not with 2xx.
class ApiException implements Exception {
  final int statusCode;
  final String message;

  /// The decoded JSON body when the server returned one, so callers that
  /// need field-level validation detail (e.g. a 422) can read it without a
  /// second parse. Null when the body wasn't JSON.
  final Map<String, dynamic>? body;

  ApiException(this.statusCode, this.message, {this.body});

  /// Transient server/infra conditions worth retrying with backoff.
  bool get isRetryable =>
      statusCode == 408 || // Request Timeout
      statusCode == 425 || // Too Early
      statusCode == 429 || // Too Many Requests
      statusCode == 500 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;

  /// Auth failures — Laravel returns 401, or 419 for an expired session.
  /// The queued sale should NOT be marked failed; it should trigger re-auth
  /// and stay pending (handover doc G4).
  bool get isAuthFailure => statusCode == 401 || statusCode == 419;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiDownloadResponse {
  final Uint8List bytes;
  final String filename;
  final String contentType;
  final int statusCode;

  ApiDownloadResponse({
    required this.bytes,
    required this.filename,
    required this.contentType,
    required this.statusCode,
  });
}

class ApiClient {
  /// Selected at build time by [BackendConfig]. Existing API callers can keep
  /// using ApiClient.baseUrl without knowing whether this is a local or server
  /// distribution.
  static const String baseUrl = BackendConfig.apiBaseUrl;
  final String? token;

  /// Set this callback in main.dart to be notified whenever any API call
  /// returns 402 BRANCH_SUBSCRIPTION_EXPIRED.  The callback receives the full
  /// decoded response body so the SubscriptionProvider can update state
  /// without a separate server round-trip.
  ///
  /// Deliberately static (not per-instance) so every ApiClient instance —
  /// regardless of which service created it — fires the same interceptor.
  static void Function(Map<String, dynamic> body)? onSubscriptionExpired;

  /// Notifies the auth layer when server-side authorization rejects a request.
  /// This lets the app refresh permissions immediately after another admin
  /// changes the current user's role instead of trusting stale local flags.
  static Future<void> Function(Map<String, dynamic> body)? onForbidden;

  ApiClient({this.token});

  Map<String, String> get _headers => {
    "Content-Type": "application/json",
    "Accept": "application/json",
    if (token != null) "Authorization": "Bearer $token",
  };

  Map<String, String> get _downloadHeaders => {
    "Accept": "application/octet-stream, application/pdf, application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    // Laravel decides whether an auth failure gets a 401 JSON response or a
    // redirect to a "login" page by checking Request::expectsJson(), which
    // treats X-Requested-With: XMLHttpRequest as an AJAX/API call. Without
    // this header (and with our Accept header not starting with
    // application/json), an expired/invalid token made Laravel redirect to
    // the app's root route instead of returning 401 — and this client
    // followed the redirect and saved the resulting HTML page as if it were
    // the exported file. This header keeps auth failures as a clean JSON
    // 401 that the catch-branch below can surface as a real error.
    "X-Requested-With": "XMLHttpRequest",
    if (token != null) "Authorization": "Bearer $token",
  };

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse("$baseUrl$path").replace(queryParameters: query);
    final res = await http.get(uri, headers: _headers);
    return _handleResponse(res);
  }

  Future<ApiDownloadResponse> download(
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse("$baseUrl$path").replace(queryParameters: query);
    final res = await http.get(uri, headers: _downloadHeaders);
    final contentType = res.headers['content-type'] ?? '';

    if (res.statusCode >= 200 && res.statusCode < 300) {
      // Belt-and-braces check: if something upstream (an expired-token
      // redirect, a misconfigured URL, maintenance mode, a proxy error
      // page, ...) causes an HTML/JSON page to come back with a 200 status,
      // don't silently save it to disk as if it were the requested file —
      // that's exactly how a login/welcome page ends up saved as
      // "report.xlsx" and fails to open later. Surface it as a real error
      // instead.
      if (contentType.contains('text/html')) {
        throw Exception(
          "Download failed: the server returned a web page instead of a file "
          "(HTTP ${res.statusCode}, requested $uri). ${_htmlSnippet(res.body)}",
        );
      }

      return ApiDownloadResponse(
        bytes: res.bodyBytes,
        filename: _filenameFromHeaders(res.headers) ?? _fallbackFilename(path, query),
        contentType: contentType.isNotEmpty ? contentType : 'application/octet-stream',
        statusCode: res.statusCode,
      );
    }

    String? apiMessage;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        apiMessage = decoded['message']?.toString();
      }
    } catch (_) {
      // Response is probably binary or plain text. Use generic error below.
    }
    throw Exception(apiMessage ?? "Download failed: ${res.statusCode}");
  }

  Future<Map<String, dynamic>> post(String path, {Map? body}) async {
    final res = await http.post(
      Uri.parse("$baseUrl$path"),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _handleResponse(res);
  }

  Future<Map<String, dynamic>> put(String path, {Map? body}) async {
    final res = await http.put(
      Uri.parse("$baseUrl$path"),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _handleResponse(res);
  }

  /// Sends a multipart/form-data request with form fields and an optional
  /// file attachment. Supports POST (create) and real PUT/PATCH requests.
  ///
  /// CounterIQ's current Go API routes multipart product updates directly on
  /// PUT, so do not use Laravel/PHP `_method` spoofing here. Go's
  /// ParseMultipartForm handles multipart bodies for PUT correctly.
  ///
  /// Null values in [fields] are omitted from the request (the server treats
  /// missing fields as "not provided", honouring its `sometimes` rules).
  Future<Map<String, dynamic>> multipartWithFields(
    String method,
    String path, {
    String? filePath,
    String? filename,
    String fieldName = 'image',
    required Map<String, String?> fields,
  }) async {
    final uri = Uri.parse("$baseUrl$path");
    final request = http.MultipartRequest(method, uri);
    request.headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    for (final entry in fields.entries) {
      if (entry.value != null) request.fields[entry.key] = entry.value!;
    }

    if (filePath != null && filename != null) {
      request.files.add(
        await http.MultipartFile.fromPath(fieldName, filePath,
            filename: filename),
      );
    }

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return _handleResponse(res);
  }

  /// Uploads a single file as multipart/form-data (used for CSV/XLSX
  /// imports). [fields] can carry extra form fields alongside the file.
  Future<Map<String, dynamic>> uploadFile(
    String path, {
    required String filePath,
    required String filename,
    String fieldName = 'file',
    Map<String, String>? fields,
  }) async {
    final uri = Uri.parse("$baseUrl$path");
    final request = http.MultipartRequest('POST', uri);
    request.headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (fields != null) request.fields.addAll(fields);
    request.files.add(await http.MultipartFile.fromPath(fieldName, filePath, filename: filename));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return _handleResponse(res);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final res = await http.delete(
      Uri.parse("$baseUrl$path"),
      headers: _headers,
    );
    return _handleResponse(res);
  }

  Map<String, dynamic> _handleResponse(http.Response res) {
    // A non-2xx response may not be JSON (proxy error page, maintenance
    // HTML, etc.). Decode defensively so the status code is never lost just
    // because the body wasn't parseable.
    Map<String, dynamic>? decoded;
    try {
      final json = jsonDecode(res.body);
      if (json is Map<String, dynamic>) decoded = json;
    } catch (_) {
      // Non-JSON body — fall through with decoded == null.
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return decoded ?? <String, dynamic>{};
    }

    // Intercept branch-subscription failures before throwing so the
    // SubscriptionProvider can update state from any API call, not just
    // explicit status checks.  Both codes (not_configured and expired/suspended)
    // use the same callback — the provider reads the 'code' field to distinguish.
    if (res.statusCode == 402 && decoded != null) {
      final code = decoded['code']?.toString();
      if (code == 'BRANCH_SUBSCRIPTION_EXPIRED' ||
          code == 'BRANCH_SUBSCRIPTION_NOT_CONFIGURED') {
        ApiClient.onSubscriptionExpired?.call(decoded);
      }
    }

    if (res.statusCode == 403 && decoded != null && ApiClient.onForbidden != null) {
      unawaited(ApiClient.onForbidden!.call(decoded));
    }

    final message = decoded?['message']?.toString() ?? "API Error: ${res.statusCode}";
    throw ApiException(res.statusCode, message, body: decoded);
  }

  String? _filenameFromHeaders(Map<String, String> headers) {
    final disposition = headers['content-disposition'];
    if (disposition == null || disposition.isEmpty) return null;

    final utf8Match = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false).firstMatch(disposition);
    if (utf8Match != null) {
      return Uri.decodeComponent(utf8Match.group(1)!.replaceAll('"', '').trim());
    }

    final regularMatch = RegExp(r'filename="?([^";]+)"?', caseSensitive: false).firstMatch(disposition);
    return regularMatch?.group(1)?.trim();
  }

  /// Extracts the <title> from an HTML error/redirect page so the thrown
  /// error is self-diagnosing (e.g. "Let's get started" = Laravel's default
  /// welcome page = wrong route/redirect; "Whoops"/exception class name =
  /// a real server-side error; "403 Forbidden" = a web-server/proxy block).
  String _htmlSnippet(String body) {
    final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true).firstMatch(body);
    final title = titleMatch?.group(1)?.trim();
    if (title != null && title.isNotEmpty) {
      return 'Page title: "$title".';
    }
    final snippet = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return 'Body starts with: "${snippet.substring(0, snippet.length < 200 ? snippet.length : 200)}"';
  }

  String _fallbackFilename(String path, Map<String, String>? query) {
    final report = path.split('/').where((e) => e.isNotEmpty).last;
    final format = query?['format'] ?? 'xlsx';
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:\.]'), '-');
    return '${report}_$stamp.$format';
  }
}
