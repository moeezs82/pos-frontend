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

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return ApiDownloadResponse(
        bytes: res.bodyBytes,
        filename: _filenameFromHeaders(res.headers) ?? _fallbackFilename(path, query),
        contentType: res.headers['content-type'] ?? 'application/octet-stream',
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

  String _fallbackFilename(String path, Map<String, String>? query) {
    final report = path.split('/').where((e) => e.isNotEmpty).last;
    final format = query?['format'] ?? 'xlsx';
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:\.]'), '-');
    return '${report}_$stamp.$format';
  }
}
