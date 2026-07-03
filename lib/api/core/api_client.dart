import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

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
  // static const String baseUrl = "http://127.0.0.1:8003/api/v1";
  static const String baseUrl = "http://localhost/pos-backend/public/api/v1";
  final String? token;

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
    final body = jsonDecode(res.body);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    } else {
      throw Exception(body["message"] ?? "Delete failed: ${res.body}");
    }
  }

  Map<String, dynamic> _handleResponse(http.Response res) {
    final json = jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return json;
    throw Exception(json['message'] ?? "API Error: ${res.statusCode}");
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
