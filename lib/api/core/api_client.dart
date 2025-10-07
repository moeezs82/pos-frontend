import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  static const String baseUrl = "http://127.0.0.1:8003/api/v1";
  // static const String baseUrl = "http://localhost/backend-pos/public/api/v1";
  final String? token;

  ApiClient({this.token});

  Map<String, String> get _headers => {
    "Content-Type": "application/json",
    "Accept": "application/json",
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
}
