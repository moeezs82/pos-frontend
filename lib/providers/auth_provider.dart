import 'dart:convert';
import 'package:enterprise_pos/api/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider with ChangeNotifier {
  String? _token;
  Map<String, dynamic>? _user;
  bool _rememberMe = false;
  final auth = AuthService();

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isAuthenticated => _token != null;
  bool get rememberMe => _rememberMe;

  void setRememberMe(bool value) {
    _rememberMe = value;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    try {
      final data = await auth.login(email, password);
      _token = data['data']['token'];
      _user = data['data']['user'];

      final prefs = await SharedPreferences.getInstance();
      // await prefs.setString('token', _token!);
      // await prefs.setString('user', jsonEncode(_user));

      // Only save if rememberMe is true
      if (_rememberMe) {
        await prefs.setString('token', _token!);
        await prefs.setString('user', jsonEncode(_user));
      }

      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Local-only, no server call. Use this for 401 auto sign-out.
  Future<void> forceLogout() async {
    _token = null;
    _user = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user');

    notifyListeners();
  }

  Future<void> logout() async {
    try {
      if (_token != null) {
        final authWithToken = AuthService(token: _token!);
        await authWithToken.logout(); // best-effort
      }
    } catch (_) {
      // ignore – still log out locally
    } finally {
      await forceLogout();
    }
  }

  Future<void> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('token')) return;

    _token = prefs.getString('token');
    _user = jsonDecode(prefs.getString('user')!);
    _rememberMe = true;
    notifyListeners();
  }
}
