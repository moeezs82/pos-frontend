import 'package:flutter/foundation.dart';

class BranchProvider extends ChangeNotifier {
  int? _selectedBranchId;
  String? _selectedBranchName;
  bool _isMasterAdmin = false;
  bool _restored = true;

  int? get selectedBranchId => _selectedBranchId;
  String get label => _selectedBranchName ?? (_isMasterAdmin ? 'No Branch Selected' : 'No Branch Assigned');
  bool get isAll => _selectedBranchId == null;
  bool get hasActiveBranch => _selectedBranchId != null;
  bool get restored => _restored;
  bool get isMasterAdmin => _isMasterAdmin;

  /// Sync active branch from backend user payload.
  ///
  /// New backend rule:
  /// - Normal users use their own users.branch_id.
  /// - Master admin switches active branch by updating users.branch_id via API.
  /// - branch_id null for master admin means no working branch has been selected yet.
  void syncFromAuthUser(
    Map<String, dynamic>? user, {
    Map<String, dynamic>? activeBranch,
  }) {
    final nextIsMaster = _readBool(user?['is_master_admin']);
    final branch = activeBranch ?? _asMap(user?['active_branch']) ?? _asMap(user?['branch']);
    final nextId = _readInt(branch?['id']) ?? _readInt(user?['branch_id']);
    final nextName = nextId == null
        ? (nextIsMaster ? 'No Branch Selected' : 'No Branch Assigned')
        : _cleanName(branch?['name']) ?? _cleanName(user?['branch_name']) ?? 'Branch #$nextId';

    if (_selectedBranchId == nextId &&
        _selectedBranchName == nextName &&
        _isMasterAdmin == nextIsMaster &&
        _restored) {
      return;
    }

    _selectedBranchId = nextId;
    _selectedBranchName = nextName;
    _isMasterAdmin = nextIsMaster;
    _restored = true;
    notifyListeners();
  }

  /// Local mirror update after a successful backend branch switch.
  void setBranch({int? id, String? name}) {
    final nextName = id == null
        ? (_isMasterAdmin ? 'No Branch Selected' : 'No Branch Assigned')
        : (_cleanName(name) ?? 'Branch #$id');
    if (_selectedBranchId == id && _selectedBranchName == nextName) return;
    _selectedBranchId = id;
    _selectedBranchName = nextName;
    _restored = true;
    notifyListeners();
  }

  void clear() => setBranch(id: null);

  void reset() {
    if (_selectedBranchId == null &&
        _selectedBranchName == 'No Branch Assigned' &&
        !_isMasterAdmin &&
        _restored) {
      return;
    }
    _selectedBranchId = null;
    _selectedBranchName = 'No Branch Assigned';
    _isMasterAdmin = false;
    _restored = true;
    notifyListeners();
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

  static String? _cleanName(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }


}
