import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl =
      "http://127.0.0.1:8003/api/v1"; // change in production

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/login"),
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode({"email": email, "password": password}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Login failed: ${response.body}");
    }
  }

  static Future<void> logout(String token) async {
    await http.post(
      Uri.parse("$baseUrl/logout"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
        "Accept": "application/json",
      },
    );
  }

  static Future<Map<String, dynamic>> getProducts(
    String token, {
    int page = 1,
    String? search,
  }) async {
    final queryParams = {
      "page": page.toString(),
      if (search != null && search.isNotEmpty) "search": search,
    };

    final uri = Uri.parse(
      "$baseUrl/products",
    ).replace(queryParameters: queryParams);

    final response = await http.get(
      uri,
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to load products: ${response.body}");
    }
  }

  static Future<Map<String, dynamic>> createProduct(
    String token,
    Map<String, dynamic> product,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/products"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode(product),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to create product: ${response.body}");
    }
  }

  static Future<Map<String, dynamic>> updateProduct(
    String token,
    int id,
    Map<String, dynamic> product,
  ) async {
    final response = await http.put(
      Uri.parse("$baseUrl/products/$id"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode(product),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to update product: ${response.body}");
    }
  }

  static Future<void> deleteProduct(String token, int id) async {
    final response = await http.delete(
      Uri.parse("$baseUrl/products/$id"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to delete product: ${response.body}");
    }
  }

  // 🔹 Fetch categories
  static Future<List<Map<String, dynamic>>> getCategories(String token) async {
    final res = await http.get(
      Uri.parse("$baseUrl/categories"),
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );
    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      final list = json['data']['categories'] as List;
      return list.cast<Map<String, dynamic>>();
    }
    throw Exception("Failed to load categories");
  }

  // 🔹 Create category
  static Future<Map<String, dynamic>> createCategory(
    String token,
    String name,
  ) async {
    final res = await http.post(
      Uri.parse("$baseUrl/categories"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode({"name": name}),
    );
    if (res.statusCode == 201) {
      final json = jsonDecode(res.body);
      return json['data']['category'];
    }
    throw Exception("Failed to create category");
  }

  // 🔹 Fetch brands
  static Future<List<Map<String, dynamic>>> getBrands(String token) async {
    final res = await http.get(
      Uri.parse("$baseUrl/brands"),
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );
    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      final list = json['data']['brands'] as List;
      return list.cast<Map<String, dynamic>>();
    }
    throw Exception("Failed to load brands");
  }

  // 🔹 Create brand
  static Future<Map<String, dynamic>> createBrand(
    String token,
    String name,
  ) async {
    final res = await http.post(
      Uri.parse("$baseUrl/brands"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode({"name": name}),
    );
    if (res.statusCode == 201) {
      final json = jsonDecode(res.body);
      return json['data']['brand'];
    }
    throw Exception("Failed to create brand");
  }

  // Get all branches
  static Future<List<Map<String, dynamic>>> getBranches(String token) async {
    final res = await http.get(
      Uri.parse("$baseUrl/branches"),
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      return (body['data']['branches'] as List).cast<Map<String, dynamic>>();
    } else {
      throw Exception("Failed to fetch branches: ${res.body}");
    }
  }

  // Create a new branch
  static Future<Map<String, dynamic>> createBranch(
    String token,
    Map<String, dynamic> branch,
  ) async {
    final res = await http.post(
      Uri.parse("$baseUrl/branches"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode(branch),
    );
    if (res.statusCode == 201) {
      final body = jsonDecode(res.body);
      return body['data']['branch'] ??
          body['data']; // depending on backend wrapper
    } else {
      throw Exception("Failed to create branch: ${res.body}");
    }
  }

  static Future<Map<String, dynamic>> getCustomers(
    String token, {
    int page = 1,
    String? search,
  }) async {
    final queryParams = {
      "page": page.toString(),
      if (search != null && search.isNotEmpty) "search": search,
    };

    final uri = Uri.parse(
      "$baseUrl/customers",
    ).replace(queryParameters: queryParams);
    final res = await http.get(
      uri,
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );
    final body = jsonDecode(res.body);
    if (res.statusCode == 200 && body['success'] == true) {
      return jsonDecode(res.body); // because of pagination
    }
    throw Exception("Failed to load products: ${res.body}");
  }

  static Future<Map<String, dynamic>> getCustomer(String token, int id) async {
    final res = await http.get(
      Uri.parse("$baseUrl/customers/$id"),
      headers: {"Authorization": "Bearer $token", "Accept": "application/json"},
    );
    final body = jsonDecode(res.body);
    if (res.statusCode == 200 && body['success'] == true) {
      return body['data'];
    }
    throw Exception(body['message'] ?? "Failed to fetch customer");
  }

  static Future<void> createCustomer(
    String token,
    Map<String, dynamic> data,
  ) async {
    final res = await http.post(
      Uri.parse("$baseUrl/customers"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode(data),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(body['message'] ?? "Failed to create customer");
    }
  }

  static Future<void> updateCustomer(
    String token,
    int id,
    Map<String, dynamic> data,
  ) async {
    // 👇 ensure id is included in payload
    final payload = {...data, "id": id};

    final res = await http.put(
      Uri.parse("$baseUrl/customers/$id"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: jsonEncode(payload),
    );

    final body = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(body['message'] ?? "Failed to update customer");
    }
  }

  static Future<void> deleteCustomer(String token, int id) async {
    final res = await http.delete(
      Uri.parse("$baseUrl/customers/$id"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(body['message'] ?? "Failed to delete customer");
    }
  }
}
