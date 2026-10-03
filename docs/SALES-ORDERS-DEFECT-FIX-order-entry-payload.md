# CounterIQ — Sales Order Entry Defect Fix Spec

**Date:** 2026-10-03
**Scope:** Sales Order creation/edit payload contract between Flutter desktop and Go backend
**Trigger:** Four reported symptoms — (1) Submit-for-Approval produces DRAFT, (2) line discount not counted (2,095 → 2,100), (3) unclear packaging behaviour, (4) no rows in `sales_orders` while the UI lists drafts.

**Verdict after tracing both repos:** all three code defects are **frontend payload-translation bugs** in a single file. The Go backend's order contract is correct and already authoritative. Symptom (4) is not a bug at all — it is two databases. Two additional latent defects were found while tracing and are included.

> **Do not change `CreateOrder`/`UpdateOrder` packaging arithmetic.** It is correct. See §D3 for why.

---

## Repositories and anchor paths

| Repo | Root |
|---|---|
| Go backend | `E:\learning\go\pos-backend` |
| Flutter desktop | `E:\learning\flutter\enterprise_pos` |

### Backend files referenced

```
internal/modules/salesorders/models.go      # CreateOrderInput / UpdateOrderInput / CreateOrderItemInput
internal/modules/salesorders/store.go       # CreateOrder (193), UpdateOrder (438), validateOrderInput (80)
internal/modules/salesorders/handler.go     # StoreOrder (173), Update (209), Submit (269)
internal/modules/salesorders/convert.go     # order → sale payload mapping (248-282, 314-316)
internal/modules/salesorders/revalidate.go  # PRICE_DRIFT (478), STOCK_SHORTFALL (456)
internal/modules/sales/packaging.go         # economicsForSaleItem (31) — the Sale discount model
cmd/api/main.go                             # :175 startup log prints driver + db
```

### Frontend files referenced

```
lib/screens/sales/services/sales_order_submitter.dart        # THE FILE TO FIX — buildItemsPayload (204), buildOrderPayload (246)
lib/screens/sales/services/sale_cart_mutator.dart           # cartLineTotal (38) — authoritative cart line math
lib/screens/sales/services/sale_unit_conversion_service.dart# applyPackagingSelection (192-212) — cart canonicalisation
lib/screens/sales/sale_create.dart                          # _submitSalesOrder (1168), isSalesOrder mode
lib/screens/sales_orders/sales_order_form_screen.dart       # thin wrapper over CreateSaleScreen
lib/screens/sales_orders/parts/revalidation_panel.dart      # :400-413 price drift chips
lib/screens/sales_orders/sales_order_detail_screen.dart     # salesman header label
lib/api/sales_order_service.dart                            # createOrder (100), updateOrder (108), submit (116)
```

---

## The one invariant that governs all of this

> **The order's quoted total must equal exactly what the POS screen displayed when the user pressed the button.**

Every defect below is a violation of it. Fix them in the order given; D3 first because it is the only one that corrupts inventory.

---

# D3 — Packaging factor applied twice *(do this first — inventory integrity)*

**Severity:** High. Stored order quantity is wrong by `factor²`. Conversion deducts stock and books COGS on that wrong quantity.

## Root cause

`sale_unit_conversion_service.dart:192-212` already canonicalises a packaged cart row to **base units**:

```dart
next['quantity'] = baseQty;                         // displayedQty * factor   ← ALREADY BASE
next['price'] = _roundTo(packagePrice / factor, 4); // ← ALREADY PER-BASE-UNIT
next['packaging_quantity'] = displayedQty;          // the pack count
next['packaging_unit_price'] = packagePrice;        // the per-pack price
next['packaging_factor_snapshot'] = factor;
```

`sales_order_submitter.dart:buildItemsPayload()` then re-derives base units from fields that are already base:

```dart
// CURRENT — WRONG
if (packagingId != null && packagingId > 0) {
  final factor = _rowNum(it['packaging_factor_snapshot']);
  final effectiveFactor = factor > 0 ? factor : 1.0;
  final baseUnits = qty * effectiveFactor;   // 20 * 10 = 200
  final basePrice = price / effectiveFactor; // 100 / 10 = 10
  return <String, dynamic>{
    'product_id': prodId,
    'product_packaging_id': packagingId,
    'packaging_quantity': qty,          // sends 20 boxes instead of 2
    'packaging_unit_price': price,      // sends 100 instead of 1000
    'quantity': baseUnits,
    'unit_price': basePrice,
    ...
  };
}
```

The backend is **fully authoritative off the packaging fields** — `store.go:311-323` (CreateOrder) and `store.go:536-548` (UpdateOrder) both ignore the client's `quantity`/`unit_price` when packaging is present:

```go
if it.PackagingQuantity != nil {
    q := pjson.Round3(*it.PackagingQuantity)
    pkgQuantity = &q
    it.Quantity = pjson.Round3(q * factor)          // authoritative
}
if it.PackagingUnitPrice != nil && *it.PackagingUnitPrice > 0 {
    p := pjson.Round4(*it.PackagingUnitPrice)
    pkgUnitPrice = &p
    it.UnitPrice = pjson.Round4(p / factor)         // authoritative
}
```

So the backend faithfully stores what it was told: `20 × 10 = 200` pieces at `100 / 10 = 10`.

### Observed trace (2 boxes @ Rs 1,000, factor 10)

| Stage | quantity | unit_price | packaging_quantity | packaging_unit_price |
|---|---|---|---|---|
| Cart row (correct) | 20 | 100 | 2 | 1000 |
| Submitter payload (wrong) | 200 | 10 | 20 | 100 |
| Stored by backend | **200** | **10** | **20** | **100** |

Line total stays Rs 2,000.00, which is why this hid. `PRICE_DRIFT` ("Quoted 10.00, reference price now 100.00") is a **true positive** reporting it.

## Required change — `sales_order_submitter.dart`

Replace the packaging branch of `buildItemsPayload` with a straight pass-through. **No arithmetic in this function.**

```dart
if (packagingId != null && packagingId > 0) {
  return <String, dynamic>{
    'product_id': prodId,
    'product_packaging_id': packagingId,
    'packaging_quantity': _rowNum(it['packaging_quantity']),
    'packaging_unit_price': _rowNum(it['packaging_unit_price']),
    'quantity': qty,      // cart value — already base units
    'unit_price': price,  // cart value — already per base unit
    'discount': lineDiscountMoney(it),   // see D2
    'tax_rate': taxRate,
    if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
  };
}
```

Guard: if `packaging_quantity` or `packaging_unit_price` is missing/zero on a row that has `packaging_id`, treat the row as a loose line (omit `product_packaging_id` entirely) rather than sending a packaging line the backend cannot reconstruct. `convert.go:259` returns `ErrPackagingUnsupported` when `packaging_factor_snapshot` is absent, so a half-formed packaging row becomes an unconvertible order.

## Data repair required

Any order already booked with a packaged line holds a quantity inflated by `factor²` and a unit price deflated by the same. **Find them before anyone converts one.** Against the live database:

```sql
SELECT o.id, o.order_number, o.status, i.product_id,
       i.packaging_quantity, i.packaging_factor_snapshot,
       i.quantity, i.unit_price, i.total
FROM sales_order_items i
JOIN sales_orders o ON o.id = i.sales_order_id
WHERE i.product_packaging_id IS NOT NULL
ORDER BY o.id DESC;
```

A row is affected when `packaging_quantity` is not what the user typed — in practice when `packaging_quantity = typed_qty * factor`. Because the correct pack count was never persisted, it cannot be derived programmatically with certainty; recover it as `packaging_quantity / packaging_factor_snapshot` only where that yields a whole number, and otherwise correct the order by hand. Simplest safe path for a dev/test dataset: cancel the affected DRAFT/SUBMITTED orders and re-enter them after the fix. **Any order already CONVERTED needs its sale reviewed for a stock and COGS correction through the existing reversal/adjustment workflow — do not edit sale rows directly.**

---

# D2 — Line discount dropped

**Severity:** Medium. Order undercounts discount; quoted total is wrong (your 2,095 → 2,100).

## Root cause

`buildItemsPayload` forwards only `extra_discount`, which is the least-used of the cart's four discount fields:

```dart
final extraDisc = _rowNum(it['extra_discount']);
...
'discount': extraDisc,
```

The POS cart expresses line discount as (per `sale_cart_mutator.dart:38-69`):

| cart key | meaning |
|---|---|
| `discount_pct` + `discount_type: 'percentage'` | percent off the line |
| `discount_pct` + `discount_type: 'fixed'` | money **per base unit** |
| `packaging_discount_snapshot` | money **per pack** (packaged rows, `fixed` only) |
| `extra_discount` | flat money off the line |

The reported line was `100.00 T.P, Disc 5.00` with the `%` toggle → `discount_pct: 5, discount_type: 'percentage', extra_discount: 0`. Payload carried `discount: 0`.

The backend contract is correct and unambiguous — `CreateOrderItemInput.Discount` is **whole-line money**:

```go
// store.go:155 — validation
gross := pjson.Round2(item.Quantity * item.UnitPrice)
if item.Discount > gross {
    bag.Add(fmt.Sprintf("items.%d.discount", i), "Discount cannot exceed line gross amount.")
}
// store.go:333 — line math
lineGross := it.Quantity * it.UnitPrice
lineDiscount := it.Discount
lineTax := (lineGross - lineDiscount) * (it.TaxRate / 100.0)
lineTotal := pjson.Round2(lineGross - lineDiscount + lineTax)
```

and `convert.go:256` maps it straight through to the sale as `extra_discount` with `discount_pct: 0`, so whole-line money round-trips correctly into the invoice.

## Required change — `sales_order_submitter.dart`

Add a single resolver that collapses the cart's discount model to one money figure per line, **mirroring `SaleCartMutator.cartLineTotal()` exactly** so order total == POS total:

```dart
/// Collapses the POS cart's discount model (percentage / per-unit fixed /
/// per-pack fixed / extra) into the single whole-line money figure the
/// Sales Order API expects (`CreateOrderItemInput.Discount`).
///
/// Mirrors SaleCartMutator.cartLineTotal() — keep the two in step.
static double lineDiscountMoney(Map<String, dynamic> it) {
  final discountType =
      (it['discount_type'] ?? 'percentage').toString().toLowerCase();
  final extra = _rowNum(it['extra_discount']);
  double lineDisc;

  if (it['packaging_id'] != null) {
    final packQty = _rowNum(it['packaging_quantity']);
    final packPrice = _rowNum(it['packaging_unit_price']);
    final gross = _roundTo(packQty * packPrice, 2);
    lineDisc = discountType == 'fixed'
        ? _roundTo(packQty * _rowNum(it['packaging_discount_snapshot']), 2)
        : _roundTo(
            gross * (_rowNum(it['discount_pct']).clamp(0.0, 100.0) / 100.0), 2);
  } else {
    final gross = _roundTo(_rowNum(it['quantity']) * _rowNum(it['price']), 2);
    lineDisc = discountType == 'fixed'
        ? _roundTo(_rowNum(it['discount_pct']) * _rowNum(it['quantity']), 2)
        : _roundTo(
            gross * (_rowNum(it['discount_pct']).clamp(0.0, 100.0) / 100.0), 2);
  }

  final total = lineDisc + extra;
  return total.isFinite && total > 0 ? _roundTo(total, 2) : 0.0;
}
```

Add the `_roundTo` helper if it is not already in the class (copy the one in `sale_cart_mutator.dart`). Use `lineDiscountMoney(it)` for `'discount'` in **both** branches of `buildItemsPayload`.

**Do not** add `discount_pct` / `discount_type` columns to `sales_order_items`. That would duplicate the Sale domain's discount model in a second place and give two sources of truth to keep in sync; the whole-line-money contract already round-trips into the invoice unchanged.

### Rounding note for the test

For packaged rows the backend recomputes gross as `quantity × Round4(pack_price / factor)`, which for factors that do not divide evenly (e.g. price 1000, factor 3) can differ from `pack_qty × pack_price` by a sub-cent. Assert line totals with a `±0.01` tolerance per line, not exact equality.

---

# D1 — Submit for Approval always produces DRAFT

**Severity:** Medium. The approval workflow is unreachable from the UI.

## Root cause

`buildOrderPayload` sends a key the backend does not define:

```dart
'submit_for_approval': submitForApproval,   // ← no such field in Go
```

`grep -rn "submit_for_approval" internal/` returns nothing. The field the backend reads is:

```go
// models.go:131
Status string `json:"status,omitempty"` // DRAFT or SUBMITTED
```

`CreateOrder` validates it (`store.go:215-217`), honours it (`store.go:256-261`), and already logs the extra audit event (`store.go:421-431`, notes `"Submitted directly on creation"`). So create needs only the correct key.

`UpdateOrderInput` has **no** `Status` field, so saving an edited draft can never submit it. Nothing in the Flutter tree calls `service.submit()` — verified, zero call sites.

## Required change 1 — Flutter (`sales_order_submitter.dart`)

```dart
// buildOrderPayload — replace
'submit_for_approval': submitForApproval,
// with
'status': submitForApproval ? 'SUBMITTED' : 'DRAFT',
```

## Required change 2 — Go: accept `status` on update

`internal/modules/salesorders/models.go` — add to `UpdateOrderInput`:

```go
type UpdateOrderInput struct {
	CustomerID   int64                  `json:"customer_id"`
	Status       string                 `json:"status,omitempty"` // DRAFT or SUBMITTED
	DeliveryDate *string                `json:"delivery_date,omitempty"`
	Notes        *string                `json:"notes,omitempty"`
	Version      *int                   `json:"version,omitempty"`
	Items        []CreateOrderItemInput `json:"items"`
}
```

`internal/modules/salesorders/store.go` — in `UpdateOrder`, validate alongside the existing checks:

```go
if in.Status != "" && in.Status != StatusDraft && in.Status != StatusSubmitted {
	bag.Add("status", "Status must be DRAFT or SUBMITTED.")
}
```

Then fold it into the existing status-transition block near `store.go:591-600` (which currently computes `action`/`eventNotes`/`newStatus`). Required semantics — keep them exactly:

- `currentStatus == APPROVED` → **unchanged behaviour**: demote to `SUBMITTED`, clear `approved_at`/`approved_by`, action `ActionSubmitted`, note `"Order modified after approval; returned to SUBMITTED for re-approval"`. `in.Status` must **not** be able to pull an approved order back to DRAFT — ignore it in this case.
- `currentStatus == DRAFT` and `in.Status == "SUBMITTED"` → `newStatus = SUBMITTED`, set `submitted_at = now`, action `ActionSubmitted`, note `"Submitted for approval"`.
- `currentStatus == SUBMITTED` and `in.Status == "DRAFT"` → `newStatus = DRAFT`, action `ActionReturnedToDraft` (use whatever constant `ReturnToDraft` already uses), note `"Returned to draft"`. If you would rather keep that transition exclusively on `POST /{id}/return-to-draft`, instead reject it here with `bag.Add("status", "Use return-to-draft to move a submitted order back to DRAFT.")` — either is acceptable, but pick one and make the Flutter form match.
- `in.Status == ""` → current behaviour unchanged (`ActionUpdated`, status preserved).

Keep the existing `version=version+1` and the `WHERE id=? AND branch_id=? AND version=?` guard untouched.

**Do not** have the Flutter form call `updateOrder()` then `submit()` as two requests — that races the optimistic version guard and can leave an edited order stuck in DRAFT after a successful save.

## Required change 3 — Flutter success message

`executeSalesOrderSubmit` already branches its toast on `submitForApproval`. Once the server actually honours the status, verify the message matches the returned `created.status` / reloaded order rather than the requested flag, so a server-side rejection cannot show "submitted for approval" over a draft.

---

# D5 — Revalidation panel reads the wrong keys

**Severity:** Low (display only), but it actively hides the data that would have surfaced D3.

Backend emits (`revalidate.go:481-488`):

```go
Data: map[string]any{
	"product_id": item.ProductID,
	"line_index": i,
	"quoted":     pjson.Round2(item.UnitPrice),
	"reference":  pjson.Round2(refPrice),
	"delta":      delta,
	"basis":      basis,
},
```

Panel reads (`revalidation_panel.dart:400-413`):

```dart
'Quoted',    _toDouble(issue.data['quoted_price'])   // ← wrong key
'Reference', _toDouble(issue.data['current_price'])  // ← wrong key
```

**Fix:** `quoted_price` → `quoted`, `current_price` → `reference`.

`STOCK_SHORTFALL`'s keys (`ordered` / `available` / `shortfall`) already match — leave them.

---

# D6 — Header Disc / Tax / Ship and Sale Source are live but inert in order mode

**Severity:** Low functionally, high for trust — the UI accepts input that is silently discarded.

`sale_create.dart:1183-1184` reads the footer boxes and the submitter sends header `discount` / `tax`. `CreateOrderInput` has **no** such fields; order `discount` and `tax` are derived purely from line items (`store.go:338-341`). A header discount would not survive conversion either — `convert.go:314-316` hardcodes `"discount": 0` and `"delivery": 0`. The "Sale From: Counter" selector is likewise ignored: `convert.go` resolves the source to `field_sales` regardless.

Order mode has no per-line tax input either, so `tax_rate` is always 0 and order tax is always 0 — the Tax box can never do anything.

**Fix (preferred):** in `isSalesOrder` mode, hide the footer Disc / Tax / Ship inputs and the sale-source selector, and drop `discount`/`tax` from `buildOrderPayload`. Keep line-level Disc / Extra Disc, which now work via D2.

**Alternative (only if the business needs an order-level discount):** add `Discount`/`Tax` to `CreateOrderInput`/`UpdateOrderInput`, decide and implement their allocation at conversion in `convert.go` (today the sale gets `discount: 0`), and spec that separately. Do **not** half-implement it by storing a header discount that conversion throws away.

---

# D7 — `packaging_discount_snapshot` stored as whole-line money

**Severity:** Low, latent. No money impact today; will mislead later.

`store.go:324-327` (CreateOrder) and the matching block in `UpdateOrder` store the whole-line discount as the per-pack snapshot:

```go
if it.Discount > 0 {
	d := pjson.Round4(it.Discount)
	pkgDiscountSnapshot = &d
}
```

In the Sale domain that field is **money per pack** (`internal/modules/sales/packaging.go:44-50`), and the amendment path reads it as such (`amendment.go:328-329`, `discountForLimit`). No money is wrong at conversion today only because `convert.go` sends no `discount_type`, so `economicsForSaleItem` takes the percentage branch and ignores the snapshot. That is luck, not design.

**Fix:** store it per pack.

```go
if it.Discount > 0 && pkgQuantity != nil && *pkgQuantity > 0 {
	d := pjson.Round4(it.Discount / *pkgQuantity)
	pkgDiscountSnapshot = &d
}
```

Apply in both `CreateOrder` and `UpdateOrder`. This is additive to a snapshot column with no current money path, so it is safe for existing data; historical rows keep their old value and remain unused.

---

# D8 — Salesman header label contradicts the fallback warning

**Severity:** Cosmetic.

The backend attribution change is implemented and correct: `CreateOrder` (`store.go:196-208`) defaults the salesman to the actor, requires `manage-sales-orders` to attribute to someone else, and only enforces the salesman role when the attribution was explicit. `convert.go:326-335` correctly **omits** `salesman_id` from the sale payload when the order's salesman is not role-valid, so the sale falls through to the converting user (`internal/modules/sales/store.go:849-854`). The `SALESMAN_FALLBACK` warning text is therefore accurate.

What is wrong is `sales_order_detail_screen.dart` labelling a self-attributed admin as **"Salesman (Field Booking)"**. Per the attribution spec: when `salesman_id == created_by` and that user has no salesman base role, label the field **"Booked by"**. Keep the `SALESMAN_FALLBACK` warning visible — it is telling the user something true about where the invoice credit will land.

---

# D4 — "Sales in my DB but nothing in `sales_orders`" *(no code change)*

Not a defect. Verified against `E:\learning\go\pos-backend\database-test.sqlite` (read with `-wal`/`-shm` attached, so not a stale snapshot):

```
sales:                53
sales_orders:          0
sales_order_items:     0
sales_order_events:    0
```

Tables exist, zero rows — while the UI lists drafts and opens `SO-20261003-0002`. **The API being used is not writing to the database being inspected.**

`.env` says:

```
POS_DB_CONNECTION=sqlite
POS_DB_DATABASE=database-test.sqlite
# POS_DB_CONNECTION=mysql    ← commented out
```

…but `$env:POS_DB_CONNECTION` / `$env:POS_DB_DATABASE` **override `.env` and persist for the whole PowerShell session**. Those were set during the earlier MySQL `migrate` check, so the orders are almost certainly in MySQL `pos_backend` while the 53 sales are older SQLite test data.

**Definitive check** — the API prints its database on every boot (`cmd/api/main.go:175`):

```
listening addr=... driver=mysql db=pos_backend desktop=... lan=... app_url=... timezone=...
```

Whatever `driver` / `db` says there is the only database the orders exist in. To get back on SQLite, open a clean PowerShell window or:

```powershell
Remove-Item Env:POS_DB_CONNECTION, Env:POS_DB_DATABASE -ErrorAction SilentlyContinue
.\pos-api-dev.exe serve
```

Nothing is lost or corrupted. **Decide which database is the dev baseline before doing the D3 data repair, or you will repair the wrong one.**

---

# Regression test (required — this is the part that stops the next one)

`buildItemsPayload` + `buildOrderPayload` are the only translation between a Sale-shaped cart row and a different API contract. D2 and D3 both exist because the function was written against what the fields are *named* rather than what the cart actually *stores* in them. One test closes that gap permanently.

**File:** `test/screens/sales/services/sales_order_submitter_test.dart`

```dart
// Invariant under test:
//   the order payload's implied line total == SaleCartMutator.cartLineTotal(row)
// for every discount shape and for packaged and loose rows alike.

void main() {
  group('SalesOrderSubmitter payload fidelity', () {
    // Helper: what the backend will compute from a payload line.
    //   store.go:333  lineTotal = Round2(qty*unit_price - discount + tax)
    double backendLineTotal(Map<String, dynamic> line) { ... }

    test('loose line, percentage discount', () {
      // qty 1, price 100, discount_pct 5, discount_type percentage
      // expect payload discount == 5.00 and total == 95.00
    });

    test('loose line, per-unit fixed discount', () {
      // qty 4, price 100, discount_pct 2.5, discount_type fixed
      // expect payload discount == 10.00 and total == 390.00
    });

    test('loose line, extra discount only', () {
      // qty 2, price 50, extra_discount 7
      // expect payload discount == 7.00 and total == 93.00
    });

    test('packaged line passes pack fields through unchanged', () {
      // Build the row via SaleUnitConversionService.applyPackagingSelection
      // (2 boxes, factor 10, pack price 1000) — do NOT hand-write the row,
      // so the test breaks if canonicalisation changes.
      // expect payload packaging_quantity == 2        (NOT 20)
      // expect payload packaging_unit_price == 1000   (NOT 100)
      // expect payload quantity == 20                 (NOT 200)
      // expect payload unit_price == 100              (NOT 10)
    });

    test('packaged line, per-pack fixed discount', () {
      // 2 boxes, factor 10, pack price 1000, packaging_discount_snapshot 50
      // expect payload discount == 100.00 and total == 1900.00
    });

    test('mixed cart total equals sum of cart line totals', () {
      // The reported case: 100.00 @ 5% + 2 boxes @ 1000 => 2095.00, not 2100.00
      // Assert with a +/-0.01 per-line tolerance (see D2 rounding note).
    });

    test('buildOrderPayload sends status, never submit_for_approval', () {
      // submitForApproval true  => 'status' == 'SUBMITTED'
      // submitForApproval false => 'status' == 'DRAFT'
      // expect payload does NOT contain key 'submit_for_approval'
      // expect payload does NOT contain keys 'discount'/'tax' (D6)
    });
  });
}
```

Build packaged rows through `SaleUnitConversionService.applyPackagingSelection` rather than hand-writing the map — that is what makes the test catch a future change to cart canonicalisation instead of silently agreeing with a hand-written fixture.

---

# Implementation order

| # | Defect | Repo | Why this order |
|---|---|---|---|
| 1 | **D3** packaging double factor | Flutter | Only defect that corrupts stock/COGS |
| 2 | **D3** data repair / re-enter affected orders | DB + ops | Must happen before anyone converts one |
| 3 | **D2** line discount | Flutter | Wrong quoted totals on every discounted line |
| 4 | **Regression test** | Flutter | Lock D2 + D3 before touching anything else |
| 5 | **D1** status (Flutter key + Go update field) | Both | Approval workflow unreachable |
| 6 | **D5** revalidation panel keys | Flutter | One-line fix, restores diagnostic value |
| 7 | **D6** hide inert footer inputs | Flutter | Stops the UI accepting discarded input |
| 8 | **D7** per-pack discount snapshot | Go | Latent; no current money path |
| 9 | **D8** "Booked by" label | Flutter | Cosmetic |

---

# Verification before declaring complete

### Backend

```powershell
cd E:\learning\go\pos-backend
gofmt -l internal
go build ./...
go test ./internal/modules/salesorders/...
```

Then, against both engines where available:

```powershell
# SQLite
Remove-Item Env:POS_DB_CONNECTION, Env:POS_DB_DATABASE -ErrorAction SilentlyContinue
.\pos-api-dev.exe migrate
# MySQL
$env:POS_DB_CONNECTION='mysql'; $env:POS_DB_DATABASE='pos_backend'
.\pos-api-dev.exe migrate
```

No schema change is required by this spec, so `migrate` should be a no-op — confirm it reports nothing pending rather than assuming it.

### Frontend

```powershell
cd E:\learning\flutter\enterprise_pos
flutter analyze
flutter test test/screens/sales/services/sales_order_submitter_test.dart
```

### Manual acceptance — run these against a known database (check the boot log first)

1. One loose line, 100.00 @ 5% → **Save Draft**. Detail shows status **Draft**, line discount **5.00**, total **95.00**.
2. Same cart → **Submit for Approval**. Detail shows status **Submitted**, `submitted_at` set, timeline shows `CREATED` then `SUBMITTED`.
3. Packaged line, 2 boxes @ 1,000 (factor 10) → save. Detail shows **Qty 2 boxes / 20 pc**, unit price **100.00**, total **2,000.00**. Verify in the database: `packaging_quantity = 2`, `quantity = 20`, `unit_price = 100`.
4. Mixed cart (1+3) → create total is **Rs 2,095.00** and the saved order's Booked Total is **Rs 2,095.00**.
5. `POST /sales-orders/{id}/revalidate` on (3) returns **no** `PRICE_DRIFT` issue, and the panel's Quoted/Reference chips show real figures on an order that genuinely has drifted.
6. Edit a DRAFT → **Submit for Approval** moves it to SUBMITTED in one request; `version` increments by 1.
7. Edit an APPROVED order → still demotes to SUBMITTED with the existing confirmation dialog and clears `approved_at`/`approved_by`.
8. Convert the order from (3) and verify stock moved by **20** pieces, not 200, and that COGS is booked on 20.

### Report back

Per the project reporting structure: Completed / Backend Changes / Flutter Changes / Database-Migrations / Business Rules / Permissions-Branch Impact / Accounting-Inventory Impact / Tests-Verification / Files Changed / Risks-Notes / Next Recommended Step. State explicitly which database the manual acceptance ran against.

---

# Out of scope for this spec (still open from earlier rounds)

- `/convert` silently drops `credit_limit_override_reason` and `version` → a credit-blocked order can never be converted. `ConvertOrderInput` (`convert.go:21`) has only `PaymentMethod`, `Paid`, `Payments`, while `sales_order_service.dart:169-187` already sends `version` and `credit_limit_override_reason`. **This is the highest-priority remaining backend defect after the above.**
- `go:0047` packaging snapshot columns on `sales_order_items` (if still wanted after D3/D7).
- Line-ending normalisation as its own isolated commit.


---

# Implementation status & Addendum (2026-10-03)

## Status

| Defect | Status |
|---|---|
| D1 status key + `UpdateOrderInput.Status` | **Done** (Flutter + Go). `SUBMITTED→DRAFT` is accepted on update (same permission gate as any edit) so "Save Draft" on a submitted order works. |
| D2 line discount | **Done** — `SalesOrderSubmitter.lineDiscountMoney()` |
| D3 packaging double factor | **Done** — packaged rows pass through; half-formed rows degrade to loose lines. **Data repair still required (ops).** |
| D5 revalidation keys | **Done** |
| D6 inert header inputs | **Done** — Disc/Tax/Ship and Sale-From hidden in order mode; `discount`/`tax` no longer sent |
| D7 per-pack discount snapshot | **Done** (Go, create + update) |
| D8 "Booked by" label | **Done** — shown when salesman == creator and revalidation has `SALESMAN_FALLBACK` |
| D4 two databases | No code change; check the boot log |

Tests: `test/screens/sales/services/sales_order_submitter_test.dart` (9 tests), Go `TestUpdateOrderStatusTransitions`, `TestPackagingDiscountSnapshotIsPerPack`.

## Addendum — defects found in manual testing

### D9 — Discount applied twice when converting an order
**Symptom:** an order with a Rs 5 line discount opened in conversion showed Rs 5 in the line *Extra Disc* **and** Rs 5 in the footer *Disc(-)*; payable 1,090 instead of 1,095.
**Cause:** `SalesOrderSubmitter.parsePrefill` (conversion) and `parseOrder` (edit) loaded `order.discount` / `order.tax` into the footer inputs. Order discount is only the sum of line discounts, which the rows already carry as `extra_discount`.
**Fix:** neither prefill loads header discount/tax. Rule: *order-level discount/tax are derived, never inputs.*

### D10 — Packaging lost on conversion and on edit
**Symptoms:** (a) converting an order with a Box line produced a base-unit line; (b) editing showed the line but the unit dropdown only offered "Base unit".
**Cause:** (a) `parsePrefill` built rows with no `packaging_*` fields. (b) `parseOrder` stored the pack count/price in `quantity`/`price` (non-canonical) and, for both paths, rows carried no `packagings` list or unit rule — an order line only stores snapshots.
**Fix:**
1. One shared `_cartRowFromOrderItem` builds rows in the canonical cart shape (`quantity`/`price` in base units, `packaging_quantity`, `packaging_unit_price`, `packaging_factor_snapshot`, name snapshots; line discount as `extra_discount`).
2. `CreateSaleScreen._enrichPrefilledItems()` fetches each product after load and restores `packagings`, `wholesale_price` and the quantity rule (`unit_id`/`unit_name`/`unit_allow_decimal`), so the unit dropdown lists the product's real units.
**Note:** if a product fetch fails the snapshot row is kept and still saves/converts correctly; only the unit picker is limited.
**Test:** `stored order lines round-trip through prefill without drift` asserts prefill → payload → cart total is unchanged (1,095.00) with no header discount.

## Manual re-check
1. Create order: loose 100 @ 5 disc + 1 Box (10 × 100). Open **Edit** → unit dropdown shows Box and Base unit; total 1,095.
2. Approve → **Convert**: line Extra Disc 5, footer Disc 0, Box line still in Box; payable 1,095.


> **Update:** the D2 instruction "do not add `discount_pct`/`discount_type` columns" is superseded by `SALES-ORDERS-DISCOUNT-MODEL-PARITY.md`. D2 now ships as the full discount shape, `lineDiscountMoney()` was removed, and the D7 per-pack derivation was replaced by a client-supplied snapshot.
