/// Encodes a POS cart row's discount model into the API wire shape shared by
/// the Sale and Sales Order contracts.
///
/// Packaged `fixed` lines send the amount per PACK, while the cart row stores
/// it per base unit in `discount_pct` — see create_sale_items_section.dart.
/// This asymmetry is the contract; do not "simplify" it.
class SaleDiscountPayload {
  static Map<String, dynamic> encode(Map<String, dynamic> it) {
    final type = (it['discount_type'] ?? 'percentage').toString();
    final packaged = it['packaging_id'] != null;
    final perPack = it['packaging_discount_snapshot'] ?? it['discount_pct'];
    final packagedFixed = packaged && type == 'fixed';
    return <String, dynamic>{
      'discount_pct': packagedFixed ? perPack : it['discount_pct'],
      'discount_type': type,
      'extra_discount': it['extra_discount'] ?? 0,
      if (packagedFixed) 'packaging_discount_snapshot': perPack,
    };
  }
}
