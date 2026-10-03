import 'package:enterprise_pos/models/sales_order.dart';
import 'package:enterprise_pos/screens/sales/sale_create.dart';
import 'package:flutter/material.dart';

/// Sales order creation and edit screen.
///
/// Reuses the rich POS [CreateSaleScreen] workspace with identical 2-panel/3-panel
/// layout, catalog search, barcode scanning, packaging canonicalisation, pricing rules,
/// and quantity rules, while adapting headers, shortcuts, and persisting via
/// Sales Order endpoints.
class SalesOrderFormScreen extends StatelessWidget {
  /// Pre-selects a customer when opened from a customer screen.
  final Map<String, dynamic>? initialCustomer;

  /// When supplied, the screen edits that existing order through
  /// PUT /sales-orders/{id} instead of creating a new one.
  final SalesOrder? editOrder;

  const SalesOrderFormScreen({
    super.key,
    this.initialCustomer,
    this.editOrder,
  });

  @override
  Widget build(BuildContext context) {
    return CreateSaleScreen(
      key: key,
      isSalesOrder: true,
      editSalesOrder: editOrder,
      initialCustomer: initialCustomer,
    );
  }
}
