import 'package:flutter/foundation.dart';

class BranchProvider extends ChangeNotifier {
  int? _selectedBranchId; // null = All branches
  String? _selectedBranchName;

  int? get selectedBranchId => _selectedBranchId;
  String get label => _selectedBranchName ?? "All Branches";
  bool get isAll => _selectedBranchId == null;

  void setBranch({int? id, String? name}) {
    _selectedBranchId = id;
    _selectedBranchName = name ?? "All Branches";
    notifyListeners();
  }

  void clear() => setBranch(id: null, name: "All Branches");
}
