# CounterIQ — Sales Orders bulk operations & review triage

**Date:** 2026-10-03 · **Status:** Backend implemented and tested; Flutter implemented, unit-tested, **not run visually** · **Migration:** none

Problem: approving and invoicing ~100 field bookings a day was a per-order loop (~6 clicks, ~9 requests, 2 full-screen mounts each). Fix: triage — clean orders go through bulk actions after a server pre-flight; exceptions go to a split review pane.

## Backend (`internal/modules/salesorders/batch.go`, `routes.go`)

Six endpoints under the same middleware chain as every other sales-order route. No new permissions.

| Endpoint | Permission | Cap |
|---|---|---|
| `POST /sales-orders/batch/revalidate` | view-sales-orders | 200 |
| `POST /sales-orders/batch/submit` | manage\|create-sales-orders | 50 |
| `POST /sales-orders/batch/approve` | approve-sales-orders | 50 |
| `POST /sales-orders/batch/reject` | approve-sales-orders | 50 |
| `POST /sales-orders/batch/cancel` | manage\|approve-sales-orders | 50 |
| `POST /sales-orders/batch/convert` | convert-sales-orders | 25 |

Rules held:

- **Scheduling, not new semantics.** Each handler loops, sequentially, over the existing `SubmitOrder` / `ApproveOrder` / `RejectOrder` / `CancelOrder` / `Converter.Convert`. No outer transaction; partial success is the outcome.
- **Envelope.** Always 200 for a well-formed batch with `{succeeded, failed, summary}`. 422 only for a malformed envelope (empty, over cap — message names the limit, bad id, missing `reason` / `payment_mode`). Ids are de-duplicated.
- **Scoping.** Branch-scoped; a user without `view-all-sales-orders` can only act on orders where they are salesman or creator. Anything out of scope is `NOT_FOUND` with **no order number** returned.
- **Failure codes** map 1:1 to the single-order errors: `NOT_FOUND`, `PERMISSION_DENIED`, `INVALID_STATUS`, `VERSION_CONFLICT` (current order attached), `SALESMAN_INVALID`, `PACKAGING_UNSUPPORTED`, `CREDIT_LIMIT_BLOCKED`, `VALIDATION_FAILED`, `SERVER_ERROR`.
- **Convert payment.** `payment_mode` is **required, no fallback**: `credit` → `paid: 0` for every order (no receipt booked); `full` → paid = order total with an explicit `payment_method`. Never a credit-limit override — blocked orders are reported and cleared one at a time.
- **Open register shift is checked once** up front; with none, the whole batch is rejected with 422 and zero sales.
- **Retries.** `ErrAlreadyConverted` on a retry is reported under `succeeded` with `"note": "already converted"` and the resolved `sale_id` / `invoice_no`.

### Deviation from the spec

`batch/revalidate` **loops over the existing `Store.Revalidate`** rather than hoisting lookups across orders. Hoisting would mean re-implementing ~450 lines of validation in a second place, which risks the two disagreeing — the one thing the batch verdict must not do. The cost is query count (roughly 7 per order, local DB), not correctness. `TestBatchRevalidateAgreesWithSingle` holds either implementation to the single-order result, so hoisting can be done later behind that test. Measure before doing it.

## Flutter

- `lib/models/sales_order_batch.dart` — `BatchAction` (with caps), `BatchRef`, `BatchVerdict`, `BatchSuccess`/`BatchFailure`, `BatchOutcome`, `chunkList`.
- `lib/api/sales_order_service.dart` — `batchRevalidate`, `batchAction`, and `runBatchChunks`. A chunk the server rejects with 422 fails its orders with the server message; any other chunk error (network, 5xx) marks them **`unknown`**, never `failed`.
- `sales_orders_screen.dart` — checkbox column with tri-state select-all-on-page, bulk action bar, page-size selector (20/50/100), selection pruned to visible ids (with a note), held-back reasons shown on the row, last bulk summary kept in the status bar.
- `parts/sales_order_bulk_actions.dart` — pre-flight (counts, total value, warning count, held-back count), payment-mode selector defaulting to **Credit** with open-shift state, determinate chunk progress, result sheet (succeeded with invoice numbers, failures grouped by code, unknown wording, already-converted noted).
- `sales_order_detail_screen.dart` — **Submit for Approval** action (one request via `SalesOrderService.submit`), action bar converted from a bare `Row` to a wrapping layout (no overflow in a narrow pane), `embedded` / `onChanged` for hosting.
- Split review pane (window ≥ 1200 px): toggle in the header; compact list on the left, the detail screen embedded on the right, `↑` / `↓` to move. Below 1200 px the row tap still pushes the full-screen route.

## Policy (§5) — not implemented

No approval-skipping behaviour was added: no approve-and-convert, no auto-approve threshold, no trusted-salesman flag. That is an owner decision (§5 of the brief) and none was given. Removing *Save Draft* from the field build (§5a) is a mobile-app change and is also not done.

## Tests

- Go (`internal/server/sales_orders_batch_integration_test.go`): `TestBatchApproveMixedOutcomes`, `TestBatchConvertHappyPathCredit`, `TestBatchConvertRequiresPaymentModeAndShift`, `TestBatchConvertPartialFailure` (credit-blocked order compensated back to `APPROVED`, `sale_client_ref` cleared), `TestBatchConvertRetryIsIdempotent`, `TestBatchConvertFullPaymentMode`, `TestBatchCapRejected`, `TestBatchActorScoping`, `TestBatchRevalidateAgreesWithSingle` — all pass.
- Flutter (`test/api/sales_order_batch_test.dart`): chunking at both caps and order preservation, aggregation, already-converted bucketing, 422 vs transport-error handling, grouping by code — pass.
- **Not written:** the widget tests for select-all-on-page / selection clearing, and the pre-flight "sends only ready ids" test. The pre-flight flow lives in dialogs driven by a concrete `SalesOrderService`; it needs a seam (injectable service) first.
- The `internal/server` package has unrelated failing tests that fail identically with these changes stashed.

## Risks

- **Not exercised in the running app.** The list, bulk dialogs, embedded detail and split pane compile and analyze clean but nobody has clicked through them. Do that on a database whose boot log (`driver=` / `db=`) you have confirmed.
- **Long requests on SQLite.** A 25-order convert is serialized single-writer work; measure it before raising any cap.
- **Compensation window.** Open item #2 (clearing `sale_client_ref` after a committed sale) is more exposed under batch conversion; consider fixing it next.
- **Embedded detail and focus.** The detail screen keeps its own `Focus(autofocus: true)` and shortcuts; the list's arrow bindings sit above it. If focus behaves oddly in the pane, that is the first place to look.
