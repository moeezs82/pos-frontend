import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BranchProvider extends ChangeNotifier {
  static const _kIdKey = 'branch_id';
  static const _kNameKey = 'branch_name';

  int? _selectedBranchId; // null = All branches
  String? _selectedBranchName;

  bool _restored = false; // becomes true after first load

  BranchProvider() {
    _restore(); // fire-and-forget; notifies when done
  }

  int? get selectedBranchId => _selectedBranchId;
  String get label => _selectedBranchName ?? "All Branches";
  bool get isAll => _selectedBranchId == null;
  bool get restored => _restored;

  Future<void> _restore() async {
    // Enterprise-safe default: do not auto-select a previously cached branch.
    // If the backend has no branches or the old branch was deleted, stale storage
    // can silently filter sales/reports. Always start in All Branches mode; users
    // can still select a branch manually for the current session.
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kIdKey);
    await sp.setString(_kNameKey, "All Branches");

    _selectedBranchId = null;
    _selectedBranchName = "All Branches";
    _restored = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();

    if (_selectedBranchId == null) {
      await sp.remove(_kIdKey);
      await sp.setString(_kNameKey, "All Branches");
    } else {
      await sp.setInt(_kIdKey, _selectedBranchId!);
      await sp.setString(_kNameKey, _selectedBranchName ?? "All Branches");
    }
  }

  void setBranch({int? id, String? name}) {
    _selectedBranchId = id;
    _selectedBranchName = name ?? (id == null ? "All Branches" : "Branch #$id");
    _persist(); // no need to await
    notifyListeners();
  }

  void clear() => setBranch(id: null, name: "All Branches");
}
