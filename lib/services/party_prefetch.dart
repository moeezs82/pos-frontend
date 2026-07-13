import 'package:enterprise_pos/api/customer_service.dart';
import 'package:enterprise_pos/api/product_service.dart';
import 'package:enterprise_pos/api/user_service.dart';
import 'package:enterprise_pos/api/vendor_service.dart';
import 'package:enterprise_pos/services/party_pick_caches.dart';

/// Fire-and-forget cache warmers for the create-sale / create-purchase
/// screens. Call these from initState (don't await) so that by the time a
/// cashier taps "Select Customer" a second or two later, the picker sheet
/// already has a first page sitting in the cache and opens instantly — no
/// spinner, no network wait.
///
/// Important: this cache only ever holds one page (a couple hundred rows at
/// most) per scope — it is NOT meant to hold an entire 10,000-row customer
/// table. Its job is to make "browse without typing" and "first keystroke"
/// instant. Once someone actually types something not found in this page,
/// PartyAutocompleteField falls through to a live server search (see
/// onSearchRemote wiring in sale_party_section.dart / purchase_create.dart)
/// which searches the full database, not just this cached page.
///
/// Every call is silent: failures are swallowed because this is purely an
/// optimization. If it fails, the picker sheets just fall back to fetching
/// on open like before.
class PartyPrefetch {
  PartyPrefetch._();

  /// How many rows to keep warm per scope for instant local browsing. Kept
  /// moderate on purpose — this is a convenience cache, not a full mirror
  /// of the database. Bump if your typical counter-sale customers are
  /// heavily concentrated in a "recent/frequent" set that's bigger than
  /// this; the live search covers everything else regardless.
  static const int _warmPageSize = 200;

  static void warmCustomers(String token) {
    final service = CustomerService(token: token);
    final key = CustomerPickCache.keyFor();
    CustomerPickCache.cache
        .refresh(
          key,
          () => CustomerPickCache.fetchPage(service, page: 1, perPage: _warmPageSize),
          requestKey: '$key::::1',
        )
        .catchError((_) {});
  }

  static void warmVendors(String token) {
    final service = VendorService(token: token);
    final key = VendorPickCache.keyFor();
    VendorPickCache.cache
        .refresh(
          key,
          () => VendorPickCache.fetchPage(service, page: 1, perPage: _warmPageSize),
          requestKey: '$key::::1',
        )
        .catchError((_) {});
  }

  static void warmSalesmen(String token, {String? branchId}) {
    final service = UsersService(token: token);
    // Filter to the 'salesman' role so the Salesman autocomplete on Create Sale
    // only shows users who can legally be assigned as a salesman.  Matches the
    // role name stored by RolePermissionSeeder ('salesman') and the same filter
    // the Delivery Boy field already uses ('delivery').
    const role = 'salesman';
    final key = UserPickCache.keyFor(branchId: branchId, role: role);
    UserPickCache.cache
        .refresh(
          key,
          () => UserPickCache.fetchPage(service, page: 1, branchId: branchId, role: role, perPage: _warmPageSize),
          requestKey: '$key::::1',
        )
        .catchError((_) {});
  }

  static void warmDeliveryBoys(String token, {String? branchId}) {
    final service = UsersService(token: token);
    final key = UserPickCache.keyFor(branchId: branchId, role: 'delivery');
    UserPickCache.cache
        .refresh(
          key,
          () => UserPickCache.fetchPage(service, page: 1, branchId: branchId, role: 'delivery', perPage: _warmPageSize),
          requestKey: '$key::::1',
        )
        .catchError((_) {});
  }

  static void warmProducts(String token, {int? vendorId}) {
    final service = ProductService(token: token);
    final key = ProductPickCache.keyFor(vendorId: vendorId);
    ProductPickCache.cache
        .refresh(
          key,
          () => ProductPickCache.fetchPage(service, page: 1, vendorId: vendorId, perPage: _warmPageSize),
          requestKey: '$key::::1',
        )
        .catchError((_) {});
  }

  /// Warms everything a counter-sale screen typically needs: customers,
  /// salesmen, and the unfiltered product list. Call once from
  /// CreateSaleScreen.initState.
  static void warmForSale(String token, {String? branchId}) {
    warmCustomers(token);
    warmSalesmen(token, branchId: branchId);
    warmDeliveryBoys(token, branchId: branchId);
    warmProducts(token);
  }

  /// Warms what a purchase screen typically needs: vendors and products
  /// (vendor-scoped product cache warms once a vendor is actually picked,
  /// since products are usually vendor-specific in purchases).
  static void warmForPurchase(String token, {String? branchId}) {
    warmVendors(token);
    warmProducts(token);
  }
}
