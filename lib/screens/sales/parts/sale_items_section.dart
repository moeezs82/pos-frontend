import 'package:flutter/material.dart';

class SaleItemsSection extends StatelessWidget {
  final Map<String, dynamic> sale;
  final VoidCallback onPickVendor;
  final Map<String, dynamic>? selectedVendor;
  final VoidCallback onAddItem;
  final void Function(Map item) onEditItem;
  final void Function(int itemId) onDeleteItem;

  const SaleItemsSection({
    super.key,
    required this.sale,
    required this.onPickVendor,
    required this.selectedVendor,
    required this.onAddItem,
    required this.onEditItem,
    required this.onDeleteItem,
  });

  @override
  Widget build(BuildContext context) {
    final items = (sale['items'] as List);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + vendor filter + add
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Expanded(
                  child: Text("Items",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                // OutlinedButton.icon(
                //   onPressed: onPickVendor,
                //   icon: const Icon(Icons.storefront_outlined),
                //   label: Text(
                //     selectedVendor == null
                //         ? "Filter Vendor"
                //         : "Vendor: ${selectedVendor?['first_name'] ?? ''}",
                //     overflow: TextOverflow.ellipsis,
                //   ),
                // ),
                // const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: onAddItem,
                  icon: const Icon(Icons.add),
                  label: const Text("Add Item"),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...items.map((i) => ListTile(
                title: Text(i['product']['name']),
                subtitle: Text("Qty: ${i['quantity']} × \$${i['price']}"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.edit), onPressed: () => onEditItem(i)),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => onDeleteItem(i['id'] as int),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
