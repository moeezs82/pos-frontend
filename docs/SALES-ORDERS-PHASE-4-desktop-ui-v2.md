# CounterIQ — Phase 4 (v2): Desktop Sales Orders, with Order Entry

**Date:** 2026-10-03
**Supersedes:** `docs/SALES-ORDERS-PHASE-4-desktop-ui.md`
**Scope:** Flutter desktop (`enterprise_pos`) + two small backend fixes + one backend migration.
**Repos:** backend `E:\learning\go\pos-backend` · frontend `E:\learning\flutter\enterprise_pos`

---

## 0. What changed from v1, and why

v1 deferred desktop order creation. That was wrong, for a reason v1's own acceptance list exposed: it says *"a manager approves an order; the timeline shows their name"* — but nothing in the desktop app can create an order to approve. You would be POSTing through Postman to test your own UI.

Creation is a Phase 4 dependency, not a follow-on. It also carries real business weight: phone orders, wholesale quotations, pre-orders for out-of-stock items, counter bookings for later delivery. And it de-risks mobile — the item-entry rules get built and proven once on a desktop screen where everything is visible.

**The order entry screen must feel as fast as the POS screen.** That is the substance of this document: §4 lists the exact machinery `sale_create.dart` uses for speed, and §5 requires the order form to reuse it rather than reinvent a slower version.

### Already done (verified — do not redo)

List screen, detail screen, revalidation panel, items table, timeline, reason dialog, service, models, route id, `home_screen` wiring, nav leaf, `salesOrderPrefill` on `CreateSaleScreen`, dashboard attention row. Approve-gated-on-blocking, the 409/version-conflict handling, `view-sale-profit` gating and the add-on panel are all in place.

### New in this phase

1. Two backend fixes to `/convert` (§1) — **one is blocking a shipped feature**.
2. Migration `go:0047` for packaging on order items (§1).
3. `SalesOrderFormScreen` — create and edit (§5).
4. Global and screen shortcuts (§6).

---

## 1. Backend prerequisites

### 1.1 `/convert` drops two fields the client already sends — BLOCKING

`ConvertOrderInput` (`internal/modules/salesorders/convert.go:21`) is only `PaymentMethod`, `Paid`, `Payments`. The frontend sends `credit_limit_override_reason` and `version` (`lib/api/sales_order_service.dart:181-184`) and **both are silently discarded.**

The credit one is a dead end for users: on a `block`-mode over-limit order the override dialog opens, the user types a reason, `CreateSale` runs *without* `credit_limit_override`, and `creditcontrol.Finalize` returns the same `422 PARTY_CREDIT_LIMIT_EXCEEDED`. Forever. Both override entry points are affected — `revalidation_panel.dart:449` and the retry inside `sale_create.dart:3501`.

```go
type ConvertOrderInput struct {
    PaymentMethod             string           `json:"payment_method,omitempty"`
    Paid                      *float64         `json:"paid,omitempty"`
    Payments                  []map[string]any `json:"payments,omitempty"`
    CreditLimitOverrideReason *string          `json:"credit_limit_override_reason,omitempty"`
    Version                   *int             `json:"version,omitempty"`
}
```

In `saleMap`:

```go
if in.CreditLimitOverrideReason != nil && strings.TrimSpace(*in.CreditLimitOverrideReason) != "" {
    saleMap["credit_limit_override"] = map[string]any{"reason": strings.TrimSpace(*in.CreditLimitOverrideReason)}
}
```

That key is what `input.go:617` already reads. No extra permission check — `creditcontrol.Finalize` enforces `override-party-credit-limit` itself and surfaces `PermissionDenied` through `CreateSale`.

For `Version`, add `AND version = ?` to the TX1 CAS and return `ErrVersionConflict` on zero rows, matching every other mutation in the module.

**Tests:** convert a `block`-mode over-limit order → 422; convert again with a reason → succeeds and writes the credit audit row. Convert with a stale `version` → 409.

### 1.2 `go:0047_sales_order_item_packaging` — required before the form ships

`sale_create.dart` has 154 packaging references; a wholesale clerk books in cartons. The backend currently 422s on `product_packaging_id` for orders. A desktop order form that only accepts base units, sitting next to a sale screen that does cartons, will read as broken and will produce quantity errors.

Mirror `sale_items`, on `sales_order_items`:

| Column | Type |
| --- | --- |
| `packaging_name_snapshot` | VARCHAR(255) NULL |
| `packaging_short_name_snapshot` | VARCHAR(255) NULL |
| `packaging_factor_snapshot` | DECIMAL(18,4) NULL |
| `packaging_quantity` | DECIMAL(18,3) NULL |
| `packaging_unit_price` | DECIMAL(18,4) NULL |
| `packaging_discount_snapshot` | DECIMAL(18,4) NULL |

House style from `tenant_isolation.go`: `columnExists` guards, driver-branched DDL, preflight before any DDL.

Then:

- **Order create/update** resolves the packaging against the product and branch, requires a whole-number `packaging_quantity`, and canonicalises `quantity` to base units — the same rules `normalizeSalePackagings` applies (`sales/packaging.go:99`). Remove the `PACKAGING_UNSUPPORTED` rejection from `validateOrderInput`.
- **Conversion** passes all six snapshot fields plus `packaging_id` into the sale payload, so `normalizeSalePackagings` accepts the line. Keep the `PACKAGING_UNSUPPORTED` code in `revalidate.go` as a defensive check for legacy rows.
- **`revalidate`** adds a `PACKAGING_DRIFT` **warning** when the live factor differs from the stored snapshot (the current factor governs the derived quantity, so the difference is real and the approver should see it).

Until 0047 lands, the form must hide the packaging selector entirely rather than offer one that 422s.

---

## 2. Read these first

### Frontend — speed machinery (the heart of this phase)

| What | File |
| --- | --- |
| Generic pick cache | `lib/services/pick_cache.dart` — `PickCache<T>`, `PickCacheEntry<T>`, `refresh(key, fetcher)`, `insertEverywhere`, `insertInto`, `put`, `clear` |
| Party caches | `lib/services/party_pick_caches.dart` — `CustomerPickCache`, `UserPickCache`, `VendorPickCache`; each with `cache`, `keyFor()`, `fetchPage`, `searchRemote`, and `hydrateFromCatalog` on customers |
| Cache warming | `lib/services/party_prefetch.dart` — `warmCustomers`, `warmSalesmen`, `warmProducts`, `warmForSale(token, branchId:)`; page size 200 |
| Offline catalog | `lib/services/catalog_cache_service.dart` — `searchProducts`, `productByBarcode(code, branchId:, vendorId:)`, `searchCustomers`, `customerAreas` |
| Price rule | `lib/services/sale_pricing.dart` — `normalizeCustomerType`, `isWholesale`, `effectiveProductPrice`, `effectivePackagingPrice` |
| Stock lookups | `lib/services/product_stock.dart` |
| Global shortcuts + guide | `lib/widgets/app_keyboard_shortcuts.dart` — `PosShortcutInfo`, `showAppShortcutGuide(context, includeSaleCreate:)`, `_ctrl/_ctrlShift/_ctrlAlt/_cmd` helpers (line 267) |
| Screen shortcuts, focus, scanner | `lib/screens/sales/sale_create.dart` — shortcut block at 4861, `_restoreSaleScreenFocus` 4511, `_focusAndSelectAll` 4502, `_onBarcodeScanned` 2389, barcode field 2768 |
| Pickers | `lib/widgets/{customer_picker_sheet,product_picker_sheet,product_picker_grid_sheet,user_picker_sheet,variant_picker_dialog,party_autocomplete_field,quick_variant_create_dialog,product_packaging_editor}.dart` |
| Item section layout | `lib/screens/sales/parts/{create_sale_items_section,sale_product_panel,sale_totals_card}.dart` |
| Design system | `lib/widgets/enterprise/{enterprise_ui,enterprise_panel}.dart` |
| Theme | `lib/theme/app_theme.dart` |
| Toasts | `lib/widgets/app_feedback.dart` |

### Backend contract

`internal/modules/salesorders/{routes,handler,models,store,convert,revalidate}.go`, `internal/platform/{response,validation}`, `internal/permissions/catalog.go`.

---

## 3. Backend contract for create and edit

Service paths omit `/api/v1` — `ApiClient.baseUrl` already carries it.

**`POST /sales-orders`** — permission `create-sales-orders`

```json
{
  "customer_id": 10,
  "salesman_id": 7,
  "status": "DRAFT",
  "order_date": "2026-10-03",
  "delivery_date": "2026-10-07",
  "notes": "Phone order, confirm before dispatch",
  "device_uuid": null,
  "items": [
    { "product_id": 5, "quantity": 12, "unit_price": 450,
      "discount": 50, "tax_rate": 0, "notes": null,
      "product_packaging_id": 3, "packaging_quantity": 1 }
  ]
}
```

- `status` accepts `DRAFT` or `SUBMITTED` only. `SUBMITTED` allocates `order_number` server-side.
- `salesman_id` is ignored unless the actor is Master Admin or holds base role `admin` (`store.go:141`) — otherwise it is forced to the actor. Do not present a salesman picker to users who cannot set it.
- `discount` is **whole-line money**, not a percentage. `tax_rate` is a per-line percentage.
- `quantity` is base units. With a packaging, send `packaging_quantity` as the carton count and let the server canonicalise (after `go:0047`).
- **Server recomputes** `subtotal`, `discount`, `tax`, `total` from the items. Client figures are display only.

**`PUT /sales-orders/{id}`** — desired-state replace of header and items. Send `version`. Allowed on `DRAFT`, `SUBMITTED`, `APPROVED`; editing an `APPROVED` order **demotes it to `SUBMITTED`** and clears approval (`store.go:424`). The form must say so before saving.

Ownership: without `view-all-sales-orders` a user may only touch orders where they are the salesman or the creator; anything else is **404**, never 403.

Validation errors come back as a `validation.Bag` 422 with `items.N.field` keys — map them onto the corresponding row.

---

## 4. The speed contract

These are not suggestions. The POS screen is fast because of these specific mechanisms, and an order form that skips them will feel like a different, worse application.

### 4.1 Warm the caches on open

```dart
@override
void initState() {
  super.initState();
  final token = context.read<AuthProvider>().token!;
  PartyPrefetch.warmForSale(token, branchId: _branchIdStr);
}
```

`warmForSale` warms customers, salesmen and products — exactly the three this form needs. Add a `warmForSalesOrder` alias to `party_prefetch.dart` only if you want to drop delivery boys; reusing `warmForSale` is acceptable and cheaper.

### 4.2 Pickers read the cache, not the network

Customer and salesman pickers go through `CustomerPickCache` / `UserPickCache`:

- `fetchPage` for the initial list, `searchRemote` only when the local filter finds nothing.
- `UserPickCache.keyFor(branchId: …, role: 'salesman')` for the salesman list.
- After creating a customer inline, call `CustomerPickCache.cache.insertEverywhere(newCustomer)` so it appears immediately without a refetch.
- `CustomerPickCache.hydrateFromCatalog(branchId: …)` so the picker still works when the server is unreachable.

### 4.3 Barcode first, cache as fallback

Copy the shape of `_onBarcodeScanned` (`sale_create.dart:2389`):

1. Live lookup via `ProductService.getProductByBarcode(code, vendorId: …)`.
2. On null **or throw**, fall back to `CatalogCacheService.instance.productByBarcode(code, branchId: …)`. A network error and a not-found both fall through — that is deliberate, so scanning survives an offline moment.
3. Found → add or increment the line, then `_barcodeController.clear()` and `_barcodeFocusNode.requestFocus()` in the same frame (2422-2424) so the next scan lands with no click.
4. Not found → `AppFeedback.warning`, keep focus in the field.

Mirror `_scannerEnabled`: a listener on the barcode focus node drives a visual "scanner armed" indicator (289-291).

### 4.4 Product search reads the local catalog

Text search uses `CatalogCacheService.instance.searchProducts(...)` so results appear as the user types without a round trip. Reuse `product_picker_grid_sheet.dart` for the grid — it already does in-cart badges, which the order form wants for the same reason.

### 4.5 Keyboard is the primary input

`CallbackShortcuts` must be an **ancestor** of `Focus(_pageFocusNode)` — the comment at `sale_create.dart:4839` explains why, and getting it the wrong way round silently breaks every shortcut.

Two helpers to copy verbatim:

- **`_restoreSaleOrderFocus()`** — modelled on `_restoreSaleScreenFocus` (4511): a post-frame callback that checks `ModalRoute.of(context)?.isCurrent == true` and returns focus to the page node. Call it after **every** sheet, dialog or autocomplete dropdown closes. Without it, focus drifts out of the shortcut scope and the user has to click before F2 works again.
- **`_focusAndSelectAll(node, ctrl)`** (4502) for every numeric field, so typing replaces rather than appends.

### 4.6 Register the shortcuts in the guide

Add `PosShortcutInfo` entries with `section: 'Create Sales Order'` and `permission: 'create-sales-orders'` so they appear in the F1 / Ctrl+/ guide. Call `showAppShortcutGuide(context, includeSaleCreate: false)` from the form, or extend the guide with an `includeSalesOrder` flag following the existing parameter pattern.

### 4.7 Enter-to-advance

Every field sets an explicit `textInputAction` and `onSubmitted` that moves to the next logical field. A clerk taking a phone order should be able to complete a line without touching the mouse: scan or type → quantity → Enter → next line.

---

## 5. `SalesOrderFormScreen` — create and edit

**Create** `lib/screens/sales_orders/sales_order_form_screen.dart`, plus `parts/sales_order_line_editor.dart` if the line row grows past ~150 lines.

```dart
class SalesOrderFormScreen extends StatefulWidget {
  /// Pre-selects a customer when opened from a customer screen.
  final Map<String, dynamic>? initialCustomer;

  /// When supplied, the screen edits that existing order through
  /// PUT /sales-orders/{id} instead of creating a new one.
  final SalesOrder? editOrder;

  const SalesOrderFormScreen({super.key, this.initialCustomer, this.editOrder});
}
```

**Deliberately much smaller than `sale_create.dart`.** No payments, no register, no printing, no returns or exchanges, no offline queue, no amendments, no walk-in customer fields (an order needs a real customer). Target well under 1,000 lines.

### Layout

`EnterprisePage(title: 'New Sales Order' | 'Edit Sales Order', icon: Icons.assignment_add)` with:

1. **Party row** — customer (`party_autocomplete_field.dart` + `customer_picker_sheet.dart`), salesman (only when settable, §3), order date, expected delivery date.
2. **Customer context strip**, shown once a customer is selected: outstanding balance, credit limit, headroom, and last order date. This is what makes the screen useful for a clerk on the phone. Source it from the customer payload the picker already carries (`credit_limit`, `credit_limit_mode`, `trade_balance` are in the catalog feed) — no extra call.
3. **Barcode field** — armed indicator, `onSubmitted: _onBarcodeScanned`.
4. **Product panel** — reuse `product_picker_grid_sheet.dart`.
5. **Line items** — product, packaging selector (after `go:0047`), quantity, unit price, line discount (money), tax rate, line total, remove. Price seeded from `SalePricing.effectiveProductPrice(product, customerType)` / `effectivePackagingPrice(...)`.
6. **Totals card** — subtotal, discount, tax, total. Clearly labelled **"Quoted totals — recalculated by the server on save."**
7. **Notes.**
8. **Action bar** — *Save Draft* · *Submit for Approval* · *Cancel*.

### Rules

- **Price must come from `SalePricing`.** If the form computes prices its own way, an order and a sale for the same wholesale customer will quote different prices and nobody will work out why.
- **Credit is advisory here.** If the customer is over limit, show a clear `AppTheme.warning` banner — *"This order will exceed the credit limit by X; approval will require an override"* — and **do not block**. The authoritative check runs at conversion. This matches the backend decision exactly; blocking here would make the form stricter than the domain it feeds.
- **Stock is advisory.** When online and the user holds `view-stock`, show available quantity per line with an "as of HH:MM" label. Never block on shortfall — negative stock is permitted.
- **Unit rules apply.** A unit that disallows decimals must reject a fractional quantity client-side with the same message the server uses; the server re-checks via `units.Validate`.
- **Editing an `APPROVED` order** shows a confirmation first: *"This order is approved. Saving changes returns it to Submitted and it will need approval again."*
- **Hide profit.** Without `view-sale-profit`, no `unit_cost`, no margin, nothing derived from cost.
- On save, 422 field errors map onto rows via the `items.N.field` keys; on success `AppFeedback.success` and pop back to the list, or straight into the detail screen for an order that was just submitted.

### Entry points

- **New Sales Order** button on `sales_orders_screen.dart`, gated on `create-sales-orders`.
- Nav leaf in the **Sales** group, directly above "Sales Orders", same gate.
- Optional, and genuinely useful for wholesale: a **Reorder** action on a converted or past order that opens the form prefilled with the same lines at current prices. Cheap, because the form already accepts an initial line set — but treat it as a follow-on if it adds schedule.

---

## 6. Shortcuts

### Global — `app_keyboard_shortcuts.dart`

| Keys | Action | Permission |
| --- | --- | --- |
| `Ctrl+Shift+F` | Open Sales Orders list | `view-sales-orders` |
| `Ctrl+Alt+F` | New Sales Order | `create-sales-orders` |

I checked the whole map: both are free. The obvious letter, `Ctrl+Shift+S`, is already bound **locally** in `sale_create.dart` (lines 4895 and 4934, focus salesman), so a global binding on it would be silently shadowed whenever the user is on the POS screen. `F` also mirrors the existing create/list pair precedent — `Ctrl+Shift+C` customers list, `Ctrl+Alt+C` create customer.

### Inside the order form — reuse the POS keys

Same keys as `sale_create` so muscle memory carries over. They are screen-scoped, so there is no conflict.

| Keys | Action |
| --- | --- |
| `F2` / `Ctrl+I` | Add item (open picker) |
| `F3` / `Ctrl+Shift+C` | Pick customer |
| `F9` | Focus barcode scanner |
| `Ctrl+Shift+S` | Focus salesman |
| `Ctrl+Shift+P` | Focus product search |
| `Ctrl+Enter` | Submit for approval |
| `Ctrl+S` | Save draft |
| `Ctrl+/` | Shortcut guide |
| `Esc` | Back (global binding already handles it) |

### Inside the detail screen

| Keys | Action |
| --- | --- |
| `Ctrl+Enter` | Approve (when enabled) |
| `Ctrl+Shift+R` | Reject |
| `Ctrl+Shift+V` | Create Sale from Order |
| `Ctrl+E` | Edit order |

Each gated on the same permission as its button, and each must respect the blocking-issues rule — a shortcut must never do what a disabled button refuses to do.

---

## 7. Build order

1. **Backend §1.1** — the two `/convert` fields. Unblocks a feature that is already shipped and broken.
2. **Backend §1.2** — `go:0047` packaging, order-entry resolution, conversion pass-through, `PACKAGING_DRIFT`.
3. `SalesOrderFormScreen` create mode, with §4 speed machinery.
4. Edit mode and the approved-demotion confirmation.
5. Global and screen shortcuts, plus guide registration.
6. Entry points: list button, nav leaf.

Steps 1 and 2 are backend and can run in parallel with nothing else; step 3 depends on 2 only for the packaging selector, so it can start before 2 lands if the selector is stubbed out behind a flag.

### Commits

1. `fix(salesorders): accept credit override reason and version on convert`
2. `feat(db): go:0047 sales order item packaging snapshots`
3. `feat(salesorders): resolve packaging at order entry and pass snapshots on conversion`
4. `feat(sales-orders): order entry form with cached pickers and barcode entry`
5. `feat(sales-orders): edit existing orders with approval demotion guard`
6. `feat(shell): sales order shortcuts and entry points`

---

## 8. Acceptance checks

### Correctness

- [ ] `go build ./...`, `go test -count=1 ./internal/...`, `flutter analyze`, Windows release build
- [ ] Credit-blocked order: override dialog → reason → conversion succeeds, credit audit row written
- [ ] Convert with a stale `version` → 409, no sale created
- [ ] An order booked in cartons converts to the correct base-unit quantity and the invoice matches the quoted total to the cent
- [ ] Packaging factor changed between booking and conversion → `PACKAGING_DRIFT` warning, conversion still correct against the current factor
- [ ] Order totals after save equal the server's recomputation, not the client's
- [ ] Wholesale customer: the form quotes the same price the POS screen would for the same product
- [ ] Editing an approved order demotes it to `SUBMITTED` and clears approval, with the warning shown first
- [ ] A user without `view-all-sales-orders` gets 404 (shown as "not found") editing another salesman's order
- [ ] A user who cannot set `salesman_id` sees no salesman picker, and the order is attributed to them
- [ ] No cost or margin anywhere without `view-sale-profit`
- [ ] Full loop with no mobile app: create → submit → approve → Create Sale from Order → invoice printed

### Speed — test these explicitly

- [ ] Opening the form shows customers and products with **no visible spinner** on a warm cache
- [ ] Scanning five barcodes in a row adds five lines with **zero mouse clicks**
- [ ] A barcode scan still resolves with the server unreachable (catalog cache fallback)
- [ ] Closing the customer picker leaves `F2` working immediately, without a click
- [ ] Tab/Enter walks the whole form to a submittable order without the mouse
- [ ] Typing in a numeric field replaces the value rather than appending
- [ ] The new shortcuts appear in the F1 guide, and only for users holding the permission

---

## 9. Decisions for you

1. **Self-approval.** A user holding both `create-sales-orders` and `approve-sales-orders` can approve their own order. Fine for a two-person shop, wrong for control. I'd ship permissive and add a branch setting if a customer asks — but decide it rather than discover it.
2. **Printing an order.** Once clerks use this for quotations, customers will want it on paper or WhatsApp. That is a real template, not a checkbox. Not in this phase; expect the ask immediately after.
3. **Commercial naming.** The add-on key is `field_sales` and it gates *every* sales-order route, so a branch wanting only desktop quotations still needs "Field Sales" switched on. Keep the stored key, but the customer-facing name should be **Sales Orders** now that desktop entry is part of the product.

---

## 10. Not in this phase

Mobile anything · offline order queue (`verify-batch` is for Phase 7) · pipeline reports and the `field_sales` report group · printing an order document · `approve_first` on convert · `sales.CreateSaleWithTx` · branch settings for stale hours and max discount percent · the security phase (sliding token expiry, `/auth/sessions`, the Flutter 402 taxonomy fix).

---

## 11. Still open on the backend

1. **Line endings** — `git diff --shortstat` reads ~247 files / +77k; ignoring whitespace it is ~9. Normalise as its own commit before the feature commit.
2. **MySQL `migrate` run** — `go:0045` and now `go:0047` are unverified on the engine the server deployment will use. Empty DB, then again for idempotency, then against a restored production copy.
3. **`Handler.Index`** still returns `{sales_orders, total, page, per_page}` rather than `paginate.Page`. The client already parses both shapes and computes `lastPage`, so this is now cosmetic consistency rather than a blocker.
