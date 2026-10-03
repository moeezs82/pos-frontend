# CounterIQ — Sales Order discount-model parity with Sale

**Date:** 2026-10-03 · **Status:** Implemented (backend gate green; Flutter tests green) · **Migration:** `go:0048_sales_order_item_discount_model`

A line booked at **10%** now stays 10% through storage, conversion, the invoice and the receipt. This **supersedes** §D2 of `SALES-ORDERS-DEFECT-FIX-order-entry-payload.md` ("do not add `discount_pct` / `discount_type` columns") — the requirement is now auditability, so shape fidelity matters, not just money equivalence.

## Model (identical to Sale)

| Field | Meaning |
|---|---|
| `discount_type` | `percentage` \| `fixed` |
| `discount_pct` | percent, or money when `fixed` (**per pack** for packaged lines — the API wire shape) |
| `packaging_discount_snapshot` | money per pack, packaged `fixed` only, else `NULL` |
| `extra_discount` | flat money off the whole line |
| `discount` | **derived** whole-line money = line discount + extra (unchanged name/meaning) |

Packaged `fixed` has three units for one number: cart row → per base unit; wire/order storage → per pack; `sale_items.discount` → per base unit. Order storage keeps the wire shape so `convert.go` is a pure pass-through. Invariant: packaged `fixed` ⇒ `discount_pct == packaging_discount_snapshot`.

## Backend

- **Migration 0048** adds `discount_pct`, `discount_type`, `extra_discount`; back-fills legacy rows (`extra_discount = discount`, type `percentage`, snapshot `NULL`) **only on the run that adds the columns**. Reproduces what conversion emitted before, so no existing total changes.
- **`sales.EconomicsForLine`** (exported wrapper over `economicsForSaleItem`, untouched) is the single discount authority for sales and sales orders. `sales.PackagingTolerance` exported.
- **`validateItemDiscount`** mirrors Sale rules: type enum; % in 0–100; loose fixed ≤ unit price; packaged fixed snapshot ≤ pack price (+tolerance); extra ≥ 0; resolved discount ≤ gross. Error keys: `items.N.discount_type|discount_pct|packaging_discount_snapshot|extra_discount`.
- **Legacy clients:** a line with only `discount` is coerced to `extra_discount` (type `percentage`) — same invoice as before.
- **CreateOrder/UpdateOrder** compute via the shared helper; the D7 derivation is deleted and the client's snapshot is stored verbatim.
- **convert.go** emits `discount_pct`, `discount_type`, `extra_discount`, and `packaging_discount_snapshot` (fixed only). No arithmetic.

## Flutter

- `SaleDiscountPayload.encode` (new) is the only encoder of the cart discount model; `SaleService.buildSalePayload` and `SalesOrderSubmitter.buildItemsPayload` both use it.
- `buildItemsPayload` no longer sends `discount`; `lineDiscountMoney` was removed. A half-formed packaged row degrades to a loose line *including* its discount encoding.
- `_cartRowFromOrderItem` rebuilds the original shape; packaged `fixed` converts per-pack → per-base-unit (`/ factor`).
- `SalesOrderItem` gains `discountPct`, `discountType`, `extraDiscount`.
- Items table shows what was entered (`2 %`, `Rs 2.50 / pc`, `Rs 50.00 / Box`), resolved money beneath, `+ extra`, and packaged lines as `2 Box (20 pc)` / `Rs 1,000.00 per Box`.

## Tests

- Go: `TestOrderLineDiscountShapesPersist` (6 shapes, create + update), `TestOrderDiscountValidationRejections`, `TestLegacyWholeLineDiscountStillAccepted`; migration test (back-fill + idempotent + no clobber); integration `TestSalesOrdersDiscountShapeSurvivesConversion` (2 % / 10 % / 3 %+2.50 → total 1,310; packaged fixed 50/Box×2 → `sale_items.discount 5`, snapshot 50, total 1,900, stock −20, COGS on 20). `TestPackagingDiscountSnapshotIsPerPack` was replaced (its subject, the D7 derivation, is gone).
- Flutter: payload shape, sale-vs-order encoder parity, prefill round-trips (incl. packaged fixed).
- Unrelated failures seen in full runs, not touched: Go `desktop`, `acctadmin`, `branchsettings` tests; Flutter `offline_invoice_seq`, `register_shift_provider`.

## Deploy notes

- **Deploy the backend (and run `migrate`, confirm `go:0048` applied) before the new desktop client.** A new client against an un-migrated server books zero discount.
- Confirm the target database from the boot log (`driver=` / `db=`) before testing.
- Out of scope: header discount/tax, per-line tax, `/convert` dropping edits.
