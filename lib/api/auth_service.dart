import 'package:enterprise_pos/api/core/api_client.dart';

class AuthService {
  final ApiClient _client;

  AuthService({String? token}) : _client = ApiClient(token: token);

  /// Login with email & password
  Future<Map<String, dynamic>> login(String email, String password) async {
    return await _client.post(
      "/login",
      body: {"email": email, "password": password},
    );
  }

  /// Logout the current user (requires token)
  Future<void> logout() async {
    await _client.post("/logout");
  }

  /// Optional: register new account
  Future<Map<String, dynamic>> register(Map<String, dynamic> data) async {
    return await _client.post("/register", body: data);
  }

  /// Optional: refresh token (if API supports it)
  Future<Map<String, dynamic>> refreshToken() async {
    return await _client.post("/refresh");
  }

  /// Optional: get user profile
  Future<Map<String, dynamic>> me() async {
    return await _client.get("/me");
  }
}
