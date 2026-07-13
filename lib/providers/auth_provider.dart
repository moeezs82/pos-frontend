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

  bool get isMasterAdmin => _readBool(_user?['is_master_admin']);
  int? get activeBranchId => _readInt(_user?['branch_id']) ?? _readInt(_asMap(_user?['branch'])?['id']);

  bool hasPermission(String permission) {
    if (isMasterAdmin) return true;
    final permissions = _user?['permissions'];
    if (permissions is! Iterable) return false;
    return permissions.any((item) {
      if (item is Map) return item['name']?.toString() == permission;
      return item.toString() == permission;
    });
  }

  void setRememberMe(bool value) {
    _rememberMe = value;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    try {
      final data = await auth.login(email, password);
      final payload = _asMap(data['data']) ?? data;
      _token = payload['token']?.toString();
      final loginUser = _asMap(payload['user']);
      _user = loginUser == null ? null : _normalizeUser(loginUser);

      if (_token == null || _user == null) {
        throw Exception('Invalid login response');
      }

      // Confirm the current user's master-admin flag from the backend immediately
      // after login. Role names are shown as labels only; they are not trusted for
      // branch-control access on the frontend.
      try {
        await refreshMe(notify: false);
      } catch (_) {
        _user = _normalizeUser({...?_user, 'is_master_admin': false});
      }

      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('token', _token!);
        await prefs.setString('user', jsonEncode(_user));
      } else {
        await prefs.remove('token');
        await prefs.remove('user');
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
    final rawUser = prefs.getString('user');
    _user = rawUser == null ? null : _asMap(jsonDecode(rawUser));
    _rememberMe = true;

    if (_token == null || _user == null) {
      await forceLogout();
      return;
    }

    // Confirm the active branch and master-admin flag from backend on app start.
    // If /me is temporarily unavailable, keep the login but do not expose any
    // master-only branch UI from stale local cache.
    try {
      await refreshMe();
      return;
    } catch (_) {
      _user = _normalizeUser({...?_user, 'is_master_admin': false});
    }

    notifyListeners();
  }

  /// Calls backend switch endpoint. Backend persists active branch in users.branch_id.
  /// Master admin must always work inside one selected branch from the dedicated Branch Control screen.
  Future<Map<String, dynamic>> switchBranch(int? branchId) async {
    if (_token == null) {
      throw Exception('Unauthenticated');
    }
    if (!isMasterAdmin) {
      throw Exception('Only master admin can switch branches.');
    }
    if (branchId == null) {
      throw Exception('Please select a working branch.');
    }

    final service = AuthService(token: _token!);
    final response = await service.switchBranch(branchId);
    final data = _asMap(response['data']) ?? response;
    final nextUser = _asMap(data['user']) ?? _asMap(data['auth_user']);
    final activeBranch = _asMap(data['active_branch']) ?? _asMap(data['branch']) ?? _asMap(nextUser?['branch']);

    // Some backend switch responses return a fresh User model without loaded role fields.
    // Never replace the auth user blindly here, otherwise master admin becomes "Unknown"
    // and loses access to the dedicated Branch Control screen after a successful switch.
    _user = _mergeUserPayload(
      current: _user,
      incoming: nextUser,
      forcedBranchId: branchId,
      activeBranch: activeBranch,
    );

    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe && _user != null) {
      await prefs.setString('user', jsonEncode(_user));
    }

    notifyListeners();
    return data;
  }

  Future<void> refreshMe({bool notify = true}) async {
    if (_token == null) return;
    final service = AuthService(token: _token!);
    final response = await service.me();
    final data = _asMap(response['data']) ?? response;
    final nextUser = _asMap(data['user']) ?? data;
    final activeBranch = _asMap(data['active_branch']) ?? _asMap(data['branch']) ?? _asMap(nextUser['branch']);

    // /me may return a compact user payload without roles. Merge it with the cached
    // login payload so master-admin permissions and role label are not lost.
    _user = _mergeUserPayload(
      current: _user,
      incoming: nextUser,
      activeBranch: activeBranch,
    );

    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe && _user != null) {
      await prefs.setString('user', jsonEncode(_user));
    }
    if (notify) notifyListeners();
  }


  static Map<String, dynamic> _normalizeUser(Map<String, dynamic> user) {
    final normalized = Map<String, dynamic>.from(user);
    normalized['is_master_admin'] = _readBool(normalized['is_master_admin']);
    return normalized;
  }

  static Map<String, dynamic> _mergeUserPayload({
    required Map<String, dynamic>? current,
    required Map<String, dynamic>? incoming,
    int? forcedBranchId,
    Map<String, dynamic>? activeBranch,
    bool forceMasterAdmin = false,
  }) {
    final merged = <String, dynamic>{
      if (current != null) ...current,
      if (incoming != null) ...incoming,
    };

    // Preserve auth/role fields when backend returns a compact user model after
    // branch switching. Without this, a valid master admin can become "Unknown".
    for (final key in const [
      'role',
      'roles',
      'role_name',
      'role_names',
      'permissions',
      'is_master_admin',
    ]) {
      if (!_hasMeaningfulValue(incoming?[key]) && _hasMeaningfulValue(current?[key])) {
        merged[key] = current![key];
      }
    }

    if (forcedBranchId != null) {
      merged['branch_id'] = forcedBranchId;
    }

    if (activeBranch != null) {
      merged['branch'] = activeBranch;
      merged['active_branch'] = activeBranch;
      merged['branch_id'] = _readInt(activeBranch['id']) ?? forcedBranchId ?? _readInt(merged['branch_id']);
    } else if (forcedBranchId != null) {
      merged['branch_id'] = forcedBranchId;
    }

    final incomingHasMasterFlag = incoming != null &&
        incoming.containsKey('is_master_admin') &&
        incoming['is_master_admin'] != null;
    merged['is_master_admin'] = incomingHasMasterFlag
        ? _readBool(incoming['is_master_admin'])
        : (forceMasterAdmin ||
            _readBool(current?['is_master_admin']) ||
            _readBool(merged['is_master_admin']));

    return _normalizeUser(merged);
  }

  static bool _hasMeaningfulValue(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty && value.trim().toLowerCase() != 'unknown';
    if (value is Iterable) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  String get roleLabel => displayRole(_user);

  static String displayRole(Map<String, dynamic>? user) {
    final candidates = <dynamic>[
      user?['role_name'],
      user?['role'],
      user?['roles'],
      user?['role_names'],
    ];

    for (final candidate in candidates) {
      final label = _roleValueToText(candidate);
      if (label != null) return label;
    }

    if (_readBool(user?['is_master_admin'])) return 'Master Admin';
    return 'Unknown';
  }

  static String? _roleValueToText(dynamic value) {
    if (value == null) return null;
    if (value is Iterable) {
      for (final item in value) {
        final text = _roleValueToText(item);
        if (text != null) return text;
      }
      return null;
    }
    if (value is Map) {
      return _roleValueToText(value['display_name'] ?? value['label'] ?? value['name'] ?? value['title']);
    }
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'unknown') return null;
    return text
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(RegExp(r'\s+'))
        .map((word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return null;
  }

  static int? _readInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value.toString());
    return parsed != null && parsed > 0 ? parsed : null;
  }

  static bool _readBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
  }

}
