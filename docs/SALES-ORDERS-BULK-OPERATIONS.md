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


---

# Addendum 2026-10-04 — One-action pipeline (Process to Invoice)

The per-stage bulk bar was built to its spec and worked; the spec was the problem. It optimised within the state machine (one action per transition) and made the operator do the traversal by hand. The states are **kept** — the approve-time revalidation gate and the event trail are real controls — but traversal is now one action.

## What changed

**Backend — `POST /sales-orders/batch/process`** (`batch.go`, `routes.go`; cap 25)

- Walks each order along `DRAFT → SUBMITTED → APPROVED → CONVERTED` as far as **the actor's permissions and the order's state** allow. Route guard is `view-sales-orders` (the floor); real authority is checked per step inside the loop (`RequirePermission` is OR-only, so "must hold all three" is not expressible there — and per-step is the better model).
- **Permission-bounded, not permission-requiring:** owner with all three goes draft → invoice; a manager (submit + approve) stops at `APPROVED` (`no_convert_permission`); a cashier (convert only) stops at `SUBMITTED` (`no_approve_permission`) or, for someone else's draft, `no_submit_permission`.
- `stop_at`: `SUBMITTED` | `APPROVED` | `CONVERTED` (default). `payment_mode` is required **only** when the run can reach convert; it is validated by the shared `requirePaymentMode`, same no-fallback rule as `batch/convert`. The open register shift is checked **once, up front**, and only for an actor who can convert — a manager who cannot reach a sale needs no shift.
- **Version chaining:** `ref.Version` is used for the first step only; each later step takes the version from the previous step's returned order. Covered by `TestBatchProcessVersionChaining`.
- **Revalidate once**, immediately before the approve step. Blocking issues → the order stops (after being submitted, if it was a draft) with `stopped_because: "blocking_issues"` and `first_blocking`. A clean order is approved and converted without a second read; `Converter.Convert` re-guards salesman, packaging and credit inside its own transaction.
- Result extends the success record with `from_status`, `steps`, `stopped_because`, `first_blocking`. An order that advanced part-way is a **success with a stop reason**; only a genuinely errored step goes in `failed`, and a failure after earlier steps carries `status` and `steps` so the UI knows the order moved.
- Retry of a finished run is reported under `succeeded` with `"already converted"`. Credit-limit override is never set.
- `BatchConvert` was refactored to share `requirePaymentMode`, `requireOpenShift` and `convertInputFor` with `BatchProcess`; its behaviour is unchanged (all earlier batch tests still pass).

**Defect fixed — `order_date` as a raw timestamp on MySQL.** `order_date` / `delivery_date` are `DATE`; with `parseTime=true` MySQL returns `time.Time`, which `database/sql` renders as `2026-10-04T00:00:00Z` into a `string`. SQLite returns the literal date, so only the MySQL deployment was affected. Fixed on the Go side in `GetOrder` and `ListOrders` with `dateOnly` / `dateOnlyPtr` (`store.go`), so every consumer benefits. **Verify on MySQL** — it cannot be reproduced on SQLite.

**Flutter**

- `BatchAction.process` (cap 25) is the **primary, leftmost** button in the bulk bar: *Process to Invoice*. Submit / Approve / Convert / Reject / Cancel remain as secondary single-stage actions.
- **Selection is kept:** `BulkRunResult.remaining` now also keeps orders that succeeded but are not finished (anything not `CONVERTED` / `CANCELLED` / `REJECTED`), so the next stage needs no re-selection.
- **Signpost, not dead end:** *"Convert needs approved orders — you selected 1 draft, 1 pending approval. Use "Process to Invoice" to take them all the way."* The old `'…can be ${verb}d'` concatenation (which produced "convertd", "submitd") is gone; `BatchAction.pastTense` is used instead.
- The pre-flight dialog for process has an **Approve only / All the way to invoice** selector, the payment block only for the latter, and a plain-language plan (*"This will submit 4, approve 8 and invoice 10 as credit. 2 orders have blocking issues and will stop before approval."*) computed from the user's own permissions. Orders with blocking issues are **sent** (the server stops each one) rather than held back, so drafts still get submitted.
- The result sheet groups orders that advanced but stopped short by what to do next: *need approval*, *awaiting conversion*, *stopped before approval — blocking issues*.

## Tests

- Go (`sales_orders_batch_process_integration_test.go`): `TestBatchProcessFullPipeline` (steps per starting state; the DRAFT order ends with the same **4 events** as doing it by hand; credit books no receipt), `…StopsAtPermissionBoundary`, `…VersionChaining`, `…StopAtApproved`, `…BlockingStopsBeforeApprove`, `…NoOpenShift` (nothing advances, not even the submit), `…IdempotentRetry`. Plus `dateonly_test.go`.
- Flutter (`test/screens/sales_orders/bulk_process_test.dart`): `remaining` keeps advanced ids, process eligibility, `pastTense`, status breakdown, preview counts (full, blocked, approve-only, no-permission), stopped-short grouping.

## Notes

- In tests the **owner needs their own open register shift** to convert: the shift belongs to the actor, and the fixture only seeds the cashier's. In production the person pressing *Process to Invoice* must have a shift open.
- Not done: the policy lever (auto-approval). Deliberately held — measure the real flow first; the cheapest next lever is getting bookers to submit rather than save drafts.
- Not exercised in the running app; the MySQL date fix is untested on MySQL.
- Still open: `sale_client_ref` compensation (exposure is the same as `batch/convert`), and the conversion screen accepting edits that `/convert` discards.
