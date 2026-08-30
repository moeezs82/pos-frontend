class CustomerDisplayUtils {
  CustomerDisplayUtils._();

  static String fullName(Map<String, dynamic> customer) {
    for (final key in const ['full_name', 'name']) {
      final explicit = (customer[key] ?? '').toString().trim();
      if (explicit.isNotEmpty) return explicit;
    }
    final first = (customer['first_name'] ?? '').toString().trim();
    final last = (customer['last_name'] ?? '').toString().trim();
    return [first, last].where((v) => v.isNotEmpty).join(' ').trim();
  }

  static String typeLabel(Map<String, dynamic> customer) {
    final raw = (customer['customer_type'] ?? 'retail').toString().trim().toLowerCase();
    switch (raw) {
      case 'wholesale':
        return 'Wholesale';
      case 'reseller':
        return 'Reseller';
      default:
        return 'Retail';
    }
  }

  static String areaName(Map<String, dynamic> customer) {
    final direct = (customer['area_name'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final area = customer['area'];
    if (area is Map) {
      final nested = (area['name'] ?? '').toString().trim();
      if (nested.isNotEmpty) return nested;
    }
    return '';
  }

  static String subtitle(
    Map<String, dynamic> customer, {
    bool includePhone = true,
    bool includeEmail = false,
  }) {
    final code = (customer['customer_code'] ?? '').toString().trim();
    final phone = (customer['phone'] ?? '').toString().trim();
    final email = (customer['email'] ?? '').toString().trim();
    final area = areaName(customer);
    return [
      if (code.isNotEmpty) code,
      typeLabel(customer),
      if (area.isNotEmpty) area,
      if (includePhone && phone.isNotEmpty) phone,
      if (includeEmail && email.isNotEmpty) email,
    ].join(' • ');
  }

  static String nameWithArea(Map<String, dynamic> customer, {String fallback = ''}) {
    final name = fullName(customer);
    final area = areaName(customer);
    final base = name.isNotEmpty ? name : fallback;
    if (area.isEmpty) return base;
    if (base.isEmpty) return area;
    return '$base • $area';
  }

  static String searchText(Map<String, dynamic> customer) {
    return [
      fullName(customer),
      customer['customer_code'],
      customer['customer_type'],
      typeLabel(customer),
      areaName(customer),
      customer['phone'],
      customer['email'],
    ]
        .where((v) => v != null && v.toString().trim().isNotEmpty)
        .map((v) => v.toString().trim())
        .join(' ')
        .toLowerCase();
  }
}
