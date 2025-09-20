import 'package:enterprise_pos/api/core/api_client.dart';

class CommonService {
  final ApiClient _client;

  CommonService({required String token}) : _client = ApiClient(token: token);

  /// Get all categories
  Future<List<Map<String, dynamic>>> getCategories() async {
    final res = await _client.get("/categories");
    final list = res["data"]["categories"] as List;
    return list.cast<Map<String, dynamic>>();
  }

  /// Create new category
  Future<Map<String, dynamic>> createCategory(String name) async {
    final res = await _client.post("/categories", body: {"name": name});
    return res["data"]["category"] ?? res["data"];
  }

  /// Get all brands
  Future<List<Map<String, dynamic>>> getBrands() async {
    final res = await _client.get("/brands");
    final list = res["data"]["brands"] as List;
    return list.cast<Map<String, dynamic>>();
  }

  /// Create new brand
  Future<Map<String, dynamic>> createBrand(String name) async {
    final res = await _client.post("/brands", body: {"name": name});
    return res["data"]["brand"] ?? res["data"];
  }

  /// Get all branches
  Future<List<Map<String, dynamic>>> getBranches({String? search}) async {
    final queryParams = {
      if (search != null && search.isNotEmpty) "search": search,
    };
    final res = await _client.get("/branches", query: queryParams);
    final list = res["data"]["branches"] as List;
    return list.cast<Map<String, dynamic>>();
  }

  /// Create new branch
  Future<Map<String, dynamic>> createBranch(Map<String, dynamic> branch) async {
    final res = await _client.post("/branches", body: branch);
    return res["data"]["branch"] ?? res["data"];
  }
}