# CounterIQ — Phase 4: Desktop Sales Orders Screen

**Date:** 2026-10-03
**Scope:** Flutter desktop (`enterprise_pos`) only. One optional backend consistency fix, called out separately.
**Prerequisites:** backend Phases 2–3 complete — `go:0044`, `go:0045`, `go:0046`, conversion hardening, read surface. All verified.
**Repos:** backend `E:\learning\go\pos-backend` · frontend `E:\learning\flutter\enterprise_pos`

---

## 0. Why this before the mobile app

Nothing in the product can approve a sales order today. The endpoints exist; no UI does. Build the salesman app first and orders pile up in `SUBMITTED` forever, because the person who approves them sits at a desktop in the branch.

This phase makes the feature shippable with zero mobile code — a clerk keys in phone orders, a manager approves, a cashier converts — and it is the first time a human will exercise the backend end to end.

---

## 1. Read these files before writing anything

### Frontend — the patterns to copy

| Purpose | File |
| --- | --- |
| **Design system** (page shell, toolbar, badges, pagination, empty state) | `lib/widgets/enterprise/enterprise_ui.dart` |
| **Panels, section headers, stat pills** | `lib/widgets/enterprise/enterprise_panel.dart` |
| **Theme tokens and `statusColor`** | `lib/theme/app_theme.dart` |
| **List screen exemplar** — filters, page cache, pagination, row tap | `lib/screens/sales/sale_returns_screen.dart` (632 lines) |
| **Closest lifecycle analogue** — a document with approve/reject actions | `lib/screens/purchases/purchase_claim_screen.dart`, `purchase_claim_detail.dart` |
| **API service pattern** | `lib/api/credit_control_service.dart` (short and current — copy its shape) |
| **HTTP client + error taxonomy** | `lib/api/core/api_client.dart` |
| **Auth / permissions** | `lib/providers/auth_provider.dart` |
| **Nav registration** | `lib/widgets/counteriq_desktop_shell.dart` (lines 334–372 show a real leaf) |
| **Workspace route plumbing** | `lib/screens/home_screen.dart` (`_workspaceRoutes` line 60, `_buildWorkspace` line 126) |
| **Route ids / singleton navigation** | `lib/services/app_navigator.dart` (`PosRouteIds` line 15, `PosNavigation.openSingleton` line 161) |
| **Toasts** | `lib/widgets/app_feedback.dart` |
| **Credit override dialog** | `lib/widgets/credit_limit_override_dialog.dart` |
| **Sale Create (prefill target)** | `lib/screens/sales/sale_create.dart` — `CreateSaleScreen` ctor at line 105 |
| **Dashboard attention rows** | `lib/screens/dashboard/command_center_dashboard.dart` (`_AttentionItem` usage ~line 902) |

### Backend — the contract source of truth

| Purpose | File |
| --- | --- |
| Routes, permissions, add-on gate | `internal/modules/salesorders/routes.go` |
| Handlers, status codes, error bodies | `internal/modules/salesorders/handler.go` |
| JSON models and status constants | `internal/modules/salesorders/models.go` |
| Revalidation contract | `internal/modules/salesorders/revalidate.go` (types at lines 29–66) |
| Conversion contract | `internal/modules/salesorders/convert.go` |
| Queries, filters, transitions | `internal/modules/salesorders/store.go` |
| Response envelopes | `internal/platform/response/response.go` |
| Validation error shape | `internal/platform/validation/validation.go` |
| Permission catalog | `internal/permissions/catalog.go` (sales-orders keys ~line 97) |

---

## 2. Backend contract

`ApiClient.baseUrl` already ends in `/api/v1` (`lib/config/backend_config.dart:58`), so service paths are written **without** that prefix — `/sales-orders`.

### Endpoints

| Method & path | Permission | Notes |
| --- | --- | --- |
| `GET /sales-orders` | `view-sales-orders` | List. Query: `page`, `per_page`, `status`, `salesman_id`, `customer_id`, `from_date`, `to_date`, `search` |
| `GET /sales-orders/summary` | `view-sales-orders` | Query: `start_date`/`end_date` (aliases `from`/`to`), `salesman_id` |
| `GET /sales-orders/filter-options` | `view-sales-orders` | |
| `POST /sales-orders` | `create-sales-orders` | Body `{customer_id, salesman_id?, status: "DRAFT"\|"SUBMITTED", order_date?, delivery_date?, notes?, device_uuid?, items:[…]}` |
| `GET /sales-orders/{id}` | `view-sales-orders` | Detail with `items` and `events` |
| `GET /sales-orders/{id}/events` | `view-sales-orders` | |
| `GET /sales-orders/{id}/revalidate` | `view-sales-orders` | **Read-only. Safe to call on every open.** |
| `PUT /sales-orders/{id}` | `manage-sales-orders\|create-sales-orders` | Desired-state replace. Send `version` |
| `POST /sales-orders/{id}/submit` | `manage-sales-orders\|create-sales-orders` | |
| `POST /sales-orders/{id}/return-to-draft` | `manage\|approve\|create-sales-orders` | |
| `POST /sales-orders/{id}/approve` | `approve-sales-orders` | |
| `POST /sales-orders/{id}/reject` | `approve-sales-orders` | Body `{reason}` required |
| `POST /sales-orders/{id}/cancel` | `manage-sales-orders\|approve-sales-orders` | Body `{reason}` |
| `POST /sales-orders/{id}/convert` | `convert-sales-orders` | Body `{payment_method?, paid?, payments?[]}` |
| `POST /sales-orders/{id}/reconcile` | `convert-sales-orders` | Repairs a converted-but-unlinked order |

**Every one of these also sits behind `mw.RequireAddon(field_sales)`.** A branch without the add-on gets **403** with the message `The Field Sales add-on is not active for this branch.` The UI must treat that as a distinct state — hide the module from the nav and, if reached anyway, show an explanatory panel. Do **not** surface it as a generic error.

### Envelopes

Success `{"success": true, "data": …, "message": …}` · error `{"success": false, "message": "…", "errors": [] | {field: [msgs]}}`.

`AppFeedback.error(context, …)` should receive `message`, and field errors should be mapped onto form fields where a form exists.

### Statuses

`DRAFT` · `SUBMITTED` · `APPROVED` · `CONVERTED` · `REJECTED` · `CANCELLED` (`models.go`). `AppTheme.statusColor()` already maps these sensibly: approved → success, draft/pending → warning, rejected/cancel → danger. `SUBMITTED` and `CONVERTED` fall through to `textMuted`, so override those two explicitly — `SUBMITTED` → `AppTheme.info`, `CONVERTED` → `AppTheme.primary`.

### `GET /sales-orders` response — note the deviation

```json
{ "sales_orders": [ … ], "total": 42, "page": 1, "per_page": 20 }
```

This is **not** the Laravel paginator shape (`current_page`, `last_page`, `data`) that every other list endpoint returns via `internal/platform/paginate`. Consequences:

- `EnterprisePaginationBar` needs `lastPage`, which the API does not send — the client must compute `lastPage = (total / per_page).ceil()`.
- The page-cache code in `sale_returns_screen.dart` cannot be reused verbatim.

**Recommended backend fix (30 minutes, do it first):** switch `Handler.Index` to `paginate.Page` like the other modules, so the response gains `current_page`, `last_page`, `data`, `total`, `per_page`. Then the Flutter side copies the existing list pattern unchanged and the app has one pagination idiom. If you'd rather not touch it, compute `lastPage` client-side and note the exception in the service — but it will be a permanent small tax on every future list screen built from this one.

### `SalesOrder` JSON

`id`, `branch_id`, `order_number`, `customer_id`, `customer` (summary), `salesman_id`, `salesman` (summary), `status`, `order_date`, `delivery_date`, `notes`, `subtotal`, `discount`, `tax`, `total`, `submitted_at`/`submitted_by`, `approved_at`/`approved_by`, `rejected_at`/`rejected_by`, `cancelled_at`/`cancelled_by`, `converted_at`/`converted_by`, `converted_sale_id`, `sale_client_ref`, `version`, `created_by`, `device_uuid`, `items[]`, `events[]`.

`SalesOrderItem`: `id`, `product_id`, `product_name`, `product_sku`, `product_variation_id`, `product_packaging_id`, `quantity`, `unit_price`, `unit_cost`, `discount`, `tax_rate`, `subtotal`, `total`, `notes`.

`SalesOrderEvent`: `id`, `user_id`, `user`, `action`, `from_status`, `to_status`, `notes`, `created_at`. Actions include `CREATED`, `UPDATED`, `SUBMITTED`, `APPROVED`, `REJECTED`, `CANCELLED`, `CONVERTED`, `CONVERT_RECONCILED`, `CONVERT_ROLLED_BACK`, `CONVERT_FAILED`.

> `unit_cost` is on the item. **Hide it, and `subtotal`-derived margin, unless the user holds `view-sale-profit`** — same rule the sale screens already follow.

### `GET /sales-orders/{id}/revalidate` response

```json
{
  "sales_order_id": 42, "order_number": "SO-...", "status": "SUBMITTED",
  "applicable": true, "age_hours": 51.2, "stale": true, "can_convert": false,
  "blocking": [ { "code": "...", "field": "items.1.product_id", "message": "...", "data": {…} } ],
  "warnings": [ … ],
  "credit": { "party_type": "customer", "party_id": 10, "credit_limit": 1000,
              "balance": 800, "projected_balance": 1200, "exceeded_by": 200,
              "mode": "block", "can_override": true },
  "converter": { "has_open_register_shift": false },
  "checked_at": "2026-10-03 11:40:11"
}
```

Codes — **blocking**: `PRODUCT_MISSING`, `PRODUCT_INACTIVE`, `CUSTOMER_MISSING`, `SALESMAN_INVALID`, `UNIT_QUANTITY_INVALID`, `PACKAGING_UNSUPPORTED`, `CREDIT_LIMIT_BLOCKED`. **Warnings**: `STOCK_SHORTFALL`, `PRICE_DRIFT`, `CREDIT_LIMIT_WARNING`, `CUSTOMER_NOT_ACTIVE`, `ORDER_STALE`.

`credit` maps field-for-field onto the existing `CreditLimitIssue` (`lib/widgets/credit_limit_override_dialog.dart:7`) except that it has no `override_used` — pass `overrideUsed: false`.

### `GET /sales-orders/summary`

```json
{ "range": { "start_date": "…", "end_date": "…" },
  "by_status": [ { "status": "CONVERTED", "count": 9, "order_value": 3200, "invoiced_value": 3050 } ],
  "totals": { "booked_value": 5800, "invoiced_value": 3050, "pending_approval": 7 } }
```

Label discipline, in the UI as well as the API: **"Booked"** for order value, **"Invoiced"** for sale value. Never the bare word "Sales" on anything from `sales_orders`.

### `GET /sales-orders/filter-options`

`{ "statuses": ["DRAFT", …], "salesmen": [{id, name, is_active?}], "customers": [{id, name, phone?}] }`

### `POST /sales-orders/{id}/convert`

Success `{ "order": {…}, "sale": {…}, "sale_id": 123, "invoice_no": "INV-…" }`.

### Error codes the UI must handle by name

| Status | `code` | UI behaviour |
| --- | --- | --- |
| 409 | `SALES_ORDER_ALREADY_CONVERTED` | Body carries `sale_id` and `invoice_no`. Show "already invoiced as INV-x" and offer to open that sale. **Never a generic failure** |
| 409 | `SALES_ORDER_VERSION_CONFLICT` | Someone else changed it. Reload the order, show what the server has, discard the local edit |
| 422 | `PARTY_CREDIT_LIMIT_EXCEEDED` | `data` is a credit payload → `showCreditLimitOverrideDialog`, then retry convert with `credit_limit_override_reason` |
| 422 | — (validation bag) | Map `errors` onto fields; `items.N.field` keys target line N |
| 403 | — | Add-on inactive (message names it) or permission missing. Distinguish by message |
| 402 | `BRANCH_SUBSCRIPTION_EXPIRED` | The existing `SubscriptionWarningBanner` path |

---

## 3. Files to create and modify

### Create

| Path | Purpose |
| --- | --- |
| `lib/api/sales_order_service.dart` | Thin `ApiClient` wrapper. Copy the shape of `credit_control_service.dart`, including the `_query` null-dropping helper |
| `lib/models/sales_order.dart` | `SalesOrder`, `SalesOrderItem`, `SalesOrderEvent`, `SalesOrderStatus` helpers. Follow `lib/models/product_packaging.dart` for the `fromJson` style |
| `lib/models/sales_order_revalidation.dart` | `RevalidationReport`, `RevalidationIssue`, plus `toCreditLimitIssue()` |
| `lib/screens/sales_orders/sales_orders_screen.dart` | List with status tabs, filters, pagination |
| `lib/screens/sales_orders/sales_order_detail_screen.dart` | Header, revalidation panel, items, event timeline, actions |
| `lib/screens/sales_orders/parts/revalidation_panel.dart` | Blocking/warning renderer |
| `lib/screens/sales_orders/parts/sales_order_items_table.dart` | Line items, profit columns gated |
| `lib/screens/sales_orders/parts/sales_order_timeline.dart` | Event list |
| `lib/screens/sales_orders/parts/reason_dialog.dart` | Reject/cancel reason prompt |

### Modify

| Path | Change |
| --- | --- |
| `lib/services/app_navigator.dart` | Add `static const salesOrders = '/sales-orders';` to `PosRouteIds` |
| `lib/screens/home_screen.dart` | Add `PosRouteIds.salesOrders` to `_workspaceRoutes` (line 60) and a `case` in `_buildWorkspace` (line 126) returning `const SalesOrdersScreen()` |
| `lib/widgets/counteriq_desktop_shell.dart` | Nav leaf in the **Sales** group, after "Sale Returns", gated on `auth.hasPermission('view-sales-orders')` |
| `lib/screens/sales/sale_create.dart` | **One additive ctor param only** — see §5 |
| `lib/screens/dashboard/command_center_dashboard.dart` | One `_AttentionItem` for orders pending approval |

---

## 4. Screens

### 4.1 List — `SalesOrdersScreen`

Structure, copying `sale_returns_screen.dart`:

```dart
EnterprisePage(
  title: 'Sales Orders',
  subtitle: 'Field bookings awaiting review and conversion',
  icon: Icons.assignment_outlined,
  child: Column(children: [
    EnterpriseToolbar(children: [ /* status tabs, search, salesman, date range */ ]),
    // list
    EnterprisePaginationBar(page: …, lastPage: …, total: …, loading: …, onPrevious: …, onNext: …),
  ]),
)
```

- **Status tabs**: `Pending` (`SUBMITTED`) · `Approved` · `All`. Default to **Pending** — this screen is a work queue, not an archive. Put the pending count in the tab label from `/summary`.
- Filters: `EnterpriseSearchField` for order number / customer, salesman dropdown from `/filter-options`, date range using the same `showDatePicker` idiom as `sale_returns_screen.dart:315`.
- Row: order number · customer · salesman · item count · total · `EnterpriseStatusBadge` · age. Add a small warning icon when `/summary` or the row's own staleness says it is overdue. **Do not call `/revalidate` per row** — that is a detail-screen call.
- `EnterpriseMetricChip` row above the list: Pending count, Booked value, Invoiced value, from `/summary` with the same date range.
- Empty state: `EnterpriseEmptyState(icon: Icons.assignment_outlined, title: 'No sales orders', subtitle: …)`.
- State: `_pages` map + `_loadingPages` set + `_loadError` with `e.toString().replaceFirst('Exception: ', '')`, exactly as the exemplar.
- Tap → `Navigator.push` to the detail screen; on return, refresh the current page (`sale_returns_screen.dart:297` is the pattern).

### 4.2 Detail — `SalesOrderDetailScreen`

Order of the page matters. **Problems first, line items second.** A manager approving twelve orders reads the top of the page and nothing else.

1. `EnterprisePageHeader` — order number, status badge, customer, salesman, total, age.
2. **Revalidation panel** — the most important widget in this phase.
3. Line items table.
4. Totals.
5. Event timeline.
6. Action bar (sticky at the bottom).

Load `GET /sales-orders/{id}` and `GET /{id}/revalidate` in parallel on open. Re-fetch revalidation after every successful action, and on a manual refresh button — it is read-only and cheap.

**Revalidation panel rules:**

- Blocking issues in `AppTheme.danger`, warnings in `AppTheme.warning`, and when both lists are empty one `AppTheme.success` line: "Ready to convert."
- One row per issue: the `message` as written by the backend (it is already user-facing), with the line number drawn from `field` when it matches `items.N.…`.
- For `STOCK_SHORTFALL` show `ordered` / `available` / `shortfall` from `data` as a compact inline metric, not a paragraph.
- For `PRICE_DRIFT` show quoted vs reference and the `basis` ("retail"/"wholesale") so nobody mistakes a wholesale quote for an error.
- Credit block: render from the `credit` object and wire the button to `showCreditLimitOverrideDialog`.
- `converter.has_open_register_shift == false` is shown **only** when the viewer holds `convert-sales-orders` — it is irrelevant to an approver and confusing if shown to one.
- `applicable == false` (terminal order) → render the panel as a single muted line, no checks.

**Action bar**, each button gated on both permission and status:

| Button | Shown when | Call |
| --- | --- | --- |
| Approve | `SUBMITTED` + `approve-sales-orders` | `POST /approve` |
| Reject | `SUBMITTED` or `APPROVED` + `approve-sales-orders` | `POST /reject` with reason |
| Cancel | not terminal + `manage`/`approve` | `POST /cancel` with reason |
| Return to draft | `SUBMITTED`/`REJECTED` + appropriate permission | `POST /return-to-draft` |
| **Create Sale from Order** | `APPROVED` + `convert-sales-orders` | opens prefilled Sale Create (§5) |
| Reconcile | `CONVERTED` and `converted_sale_id == null` + `convert-sales-orders` | `POST /reconcile` |
| Open Invoice | `converted_sale_id != null` | navigate to the sale detail |

Approve on an order with blocking issues: **disable the button** and say why ("2 problems must be resolved first"). Approving something that cannot convert is the trap this whole phase exists to prevent.

Reject and Cancel require a reason — use `parts/reason_dialog.dart`, modelled on the `AlertDialog` at `purchase_claim_detail.dart:288`. Empty reason must be rejected client-side as well as server-side.

Send `version` with every mutation and handle `SALES_ORDER_VERSION_CONFLICT` by reloading.

### 4.3 Nav leaf

In the **Sales** group of `counteriq_desktop_shell.dart`, directly after "Sale Returns":

```dart
if (auth.hasPermission('view-sales-orders'))
  _NavEntry(
    icon: Icons.assignment_outlined,
    title: 'Sales Orders',
    active: _isActive(PosRouteIds.salesOrders),
    onTap: () => PosNavigation.openSingleton(
      routeId: PosRouteIds.salesOrders,
      builder: (_) => const SalesOrdersScreen(),
    ),
  ),
```

Because `view-sales-orders` is only granted explicitly (no role has it by default), the leaf is invisible to every existing installation until someone grants it — which is the correct upgrade behaviour.

The add-on is a separate axis from the permission. If `auth` exposes the add-on map, gate the leaf on both; if not, let the screen render the add-on explainer when the API returns 403 naming it.

### 4.4 Dashboard attention row

One `_AttentionItem` in `command_center_dashboard.dart`, in the same style as the offline-queue row (~line 916):

```dart
if (auth.hasPermission('view-sales-orders'))
  _AttentionItem(
    color: _pendingOrders > 0 ? AppTheme.warning : AppTheme.success,
    title: _pendingOrders > 0
        ? '$_pendingOrders sales orders waiting for approval'
        : 'No sales orders waiting for approval',
    subtitle: _pendingOrders > 0 ? '${_money.format(_pendingValue)} booked' : 'Field sales queue is clear',
    onTap: () => PosNavigation.openSingleton(
      routeId: PosRouteIds.salesOrders,
      builder: (_) => const SalesOrdersScreen(),
    ),
  ),
```

Fed by one `/sales-orders/summary` call inside the existing `_loadLiveData()`. Swallow its errors — a dashboard must not break because one add-on is off.

---

## 5. `sale_create.dart` — touch it as little as possible

That file is 7,820 lines. Mixing its cleanup into a new financial workflow is how regressions happen.

**Allowed changes, and nothing else:**

1. One additive constructor parameter on `CreateSaleScreen` (ctor at line 105), alongside the existing `initialCustomer` / `initialReturnInvoice` / `editSaleId`:
   ```dart
   /// When supplied, this screen becomes the conversion editor for an approved
   /// sales order. Create mode is unchanged. Final submit posts to
   /// POST /sales-orders/{id}/convert instead of POST /sales, so the backend
   /// links the sale and flips the order status in one guarded operation.
   final SalesOrderPrefill? salesOrderPrefill;
   ```
2. When it is non-null: seed customer and item state from it, and render a non-dismissible banner — *"Creating sale from order SO-… · changes are recorded against the order"*.
3. Retarget submit to `/sales-orders/{id}/convert`, including `sales_order_version`.
4. Nothing else. No refactor, no reformatting, no moving code.

**Why submit must not go to `POST /sales`.** `sales.client_ref` is globally unique and `createSaleTx` replays on conflict, so if another cashier converted the same order thirty seconds earlier, posting to `/sales` returns *their* invoice with HTTP 200 and this cashier's edits and payment choice vanish with no error. Posting to `/convert` runs the status guard first and returns a clear 409 with the existing `sale_id`.

**Edit rules at this screen** (enforced in the UI; the backend records the diff on the conversion event):

- Reduce a line quantity or remove a line → allowed with `convert-sales-orders` alone. This is how short stock is handled.
- Increase a quantity, add a line, or change a price → requires `manage-sales-orders` as well.
- Payment method, split payments, credit override → normal cashier authority, unchanged.

---

## 6. State, loading and errors

Follow what the app already does, not what would be nicer:

- **State management is `provider` / `ChangeNotifier`.** Do not introduce bloc/riverpod for this feature.
- **Loading**: the codebase uses `CircularProgressIndicator` in 161 places and has exactly one skeleton (`lib/screens/dashboard/today_snapshot_section.dart`). For the list, follow `sale_returns_screen.dart:567` — a per-row placeholder, not a full-screen spinner. For the detail, keep the loaded header visible and show the revalidation panel in its own loading state. **Never blank the whole screen because one section is refreshing.**
- **Errors**: `AppFeedback.error(context, message)` for actions; an inline retry panel for a failed load (`sale_returns_screen.dart:578`).
- **Unwrap** responses in the service, not the widget: check `res['success'] == true`, return `res['data']`, else `throw Exception(res['message'] ?? '…')`. The screen converts with `e.toString().replaceFirst('Exception: ', '')`.
- `ApiException` already distinguishes retryable / auth failures — use it rather than string-matching.

---

## 7. Permission map

| Capability | Permission |
| --- | --- |
| See the nav leaf and the list | `view-sales-orders` |
| See other people's orders | `view-all-sales-orders` (without it the API returns only own orders and **404s** on others — treat 404 as "not found", never "forbidden") |
| Approve / Reject | `approve-sales-orders` |
| Edit someone else's order, return to draft | `manage-sales-orders` |
| Create Sale from Order | `convert-sales-orders` |
| See `unit_cost`, margin, profit columns | `view-sale-profit` |
| Credit override | `override-party-credit-limit` — but prefer `credit.can_override` from the revalidation payload, which the backend already computed |

Hiding a button is UX, not security — every one of these is enforced server-side. But do hide them: a disabled button a user can never enable is worse than an absent one.

---

## 8. Acceptance checks

- [ ] `flutter analyze` clean
- [ ] Windows release build succeeds
- [ ] A user with only `view-sales-orders` sees the list, sees no action buttons, and gets 404 (rendered as "not found") on another salesman's order
- [ ] A manager approves an order; the event timeline shows it with their name
- [ ] An order with a deactivated product shows the blocking issue, **Approve is disabled**, and the reason is stated
- [ ] Short stock shows as a warning, approval is still allowed, conversion succeeds
- [ ] Wholesale customer: no false `PRICE_DRIFT` row
- [ ] Convert with no open register shift shows the existing shift message, not a generic failure
- [ ] Two windows converting the same order: the loser sees "already invoiced as INV-x" with a working link to that sale
- [ ] Credit `block` order routes through `showCreditLimitOverrideDialog` and succeeds with a reason
- [ ] A converted order's invoice opens from the detail screen
- [ ] A branch without the `field_sales` add-on sees no nav leaf, and the explainer rather than an error if reached
- [ ] A user without `view-sale-profit` sees no cost or margin anywhere on the screen
- [ ] The dashboard row appears, is accurate, and fails silently when the add-on is off
- [ ] Resulting invoices are indistinguishable from walk-in sales except for `sale_source = Field Sales` and `meta.sales_order_id`

---

## 9. Commit sequence

1. `feat(api): sales order service and models` *(+ the optional `paginate.Page` backend fix first, if taken)*
2. `feat(sales-orders): list screen with filters and pagination`
3. `feat(sales-orders): detail screen with revalidation panel and timeline`
4. `feat(sales-orders): approval actions with reason dialogs`
5. `feat(sales): create sale from approved order via prefilled sale screen`
6. `feat(shell): sales orders nav entry and dashboard attention row`

Each should build and `flutter analyze` clean on its own.

---

## 10. Not in this phase

- Creating or editing sales orders from desktop beyond what approval needs — the clerk-entry form is worth doing, but only after the approval loop is proven.
- Any mobile work.
- Packaging support (the backend rejects `product_packaging_id` on orders today, so the UI must not offer a packaging selector).
- `verify-batch`, pipeline reports, the `field_sales` report group.
- Printing an order document (the Sale invoice is the printed artefact; an order is internal).

---

## 11. Still open on the backend

Not blockers for this phase, but they belong in the same release:

1. **Line endings** — `git diff --shortstat` reads 247 files / +77k; ignoring whitespace it is ~9 files. Normalise as its own commit before the feature commit.
2. **MySQL `migrate` run** — `go:0045` is unverified on the engine the server deployment will use. Empty DB, then again for idempotency, then against a restored production copy.
3. **`go build ./...` and `go test -count=1 ./internal/...` output** — the six new read-surface tests are confirmed present but not confirmed passing.
4. **Optional:** `Handler.Index` → `paginate.Page`, per §2. Cheapest moment to do it is before any client parses the current shape.
