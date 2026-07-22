# Offline-First POS Spec — Code Audit

**Scope:** Verifies the architecture spec's claims against the actual `enterprise_pos` (Flutter) + `pos-backend` (Laravel) source. No code changed. Every claim below was checked against the referenced file.

**Verdict:** The spec is unusually accurate. All seven "already correct" claims in §0.2 hold, and all nine gaps G1–G9 are real. Two places need a precision correction that actually matters for how you prioritise the work — both are in the sync-engine failure story (G3/G6).

---

## Part A — §0.2 "already implemented and correct" claims

| Claim | Verdict | Evidence |
|---|---|---|
| Durable local queue, `client_ref UNIQUE`, `ConflictAlgorithm.ignore` | **Accurate** | `offline_sales_queue_service.dart:94-104` (schema, `client_ref TEXT UNIQUE NOT NULL`), `:135` (`conflictAlgorithm: ConflictAlgorithm.ignore`). Status enum `{pending,syncing,synced,failed}` at `:14`. |
| Idempotency key on every sale, `occurredAt` captured at save | **Accurate** | `sale_create.dart:738-739` — `clientRef = const Uuid().v4()` and `occurredAt = DateTime.now()` generated unconditionally, before the online/offline branch. |
| Queue-on-any-failure (not just network) | **Accurate** | `sale_create.dart:781-806` — the `catch (e)` around `createSaleFromPayload` enqueues on *any* exception; `isNetworkFailure` only shapes the stored message, not whether it queues. |
| Server idempotency: fast-path + UNIQUE + 1062 race-catch | **Accurate** | `SaleController.php:180-189` (fast-path `where('client_ref')`), migration `2026_07_03_090000:21` (`uuid('client_ref')->nullable()->unique()`), `:265-284` (QueryException catch → `isUniqueViolation` → re-fetch), `:605-608` (23000/1062 check). Textbook-correct. |
| Reconciliation via `verify-batch` | **Accurate** | `SaleController.php:619-645` returns `{found,missing}`; client `offline_sync_service.dart:82-99` `_tryReconcile` calls it *before* any resend. Route exists: `routes/api.php:192`. |
| `occurred_at` preserves original sale time (invoice_date, number prefix, created_at) | **Accurate** | `SaleController.php:242` (`$occurredAt`), `:247` (number prefix via `generateInvoiceNo($occurredAt)`), `:249` (`invoice_date`), `:291-294` (`created_at` via `saveQuietly`). |
| Server-authoritative stock, negative allowed, `meta.stock_conflict` flagged, no local stock cache | **Accurate** | `SalePostingService.php:82-103` decrements at posting only, allows negative, sets `stock_conflict=true` at `:101-103,120-124`. No local stock table anywhere in the client. |
| Auto-sync scoped as a nicety over manual Sync Now | **Accurate** | `connectivity_auto_sync_service.dart:26-42` — best-effort `syncAll()` on connectivity regain, errors swallowed, documented as not a replacement for manual sync. |

**Part A result: 8/8 claims accurate.** Do not rebuild any of this.

---

## Part B — Gaps G1–G9

| Gap | Verdict | Evidence / precision note |
|---|---|---|
| **G1 — Sale composition not offline** | **Confirmed (critical)** | `pick_cache.dart:14-16` is explicitly "plain singleton in-memory cache (per app run). No persistence." `party_prefetch.dart:24-32` warms *one page (~200 rows)* into that same in-memory cache. The product autocomplete reads `ProductPickCache.cache.peek()` (`sale_create.dart:1175-1179`). After restart the cache is empty → offline picker returns nothing. No `catalog_cache.db`, no `CatalogController`, no `/catalog/snapshot` route exists (the `/catalog` route at `api.php:309` is a *report*, not a sync endpoint). |
| **G2 — Invoice-number race** | **Confirmed (high)** | `SaleController.php:586-597` — `SELECT max invoice_no LIKE prefix … +1`, no lock, no counter table. `invoice_no` **is** UNIQUE (`create_sales_table:16`), so a concurrent-sync collision throws a QueryException; the `:274` catch only re-fetches by `client_ref`, finds nothing (different sale), and re-throws at `:284` → HTTP 500 → client marks it `failed`. Failure mode is exactly as the spec's E6 describes. |
| **G3 — Binary error taxonomy** | **Confirmed, with a correction** | `network_failure.dart:12-17` classifies only Socket/Timeout/ClientException/Handshake as retryable. `api_client.dart:152-156` `_handleResponse` throws a **bare `Exception(message)` with no status code** — so the sync layer literally *cannot* see 401/429/500 vs 422. `offline_sync_service.dart:63-78`: non-network → `markFailed`. **Correction below.** |
| **G4 — Token expiry while offline** | **Confirmed** | `AuthController.php:37` — `createToken('pos-token', ['*'], now()->addDays(6))`. A sync after >6 days offline returns 401 → not a network failure → `markFailed`. No re-auth-and-retry path. |
| **G5 — Queue vs token durability on logout** | **Confirmed** | `AuthController@logout:54-58` deletes tokens; nothing checks `pendingCount()` before logout/clear-data. No export/backup of the queue. Queue lifetime is not coupled to auth, but nothing *guards* the token/data either. |
| **G6 — No dead-letter / retry cap / aging** | **Confirmed, with a correction** | Queue schema (`offline_sales_queue_service.dart:94-104`) has no `attempts`, no `next_retry_at`. **Correction below** re: "sit forever." |
| **G7 — Device-clock trust** | **Confirmed** | `SaleController.php:242` — `Carbon::parse($data['occurred_at'])` with only `nullable|date` validation (`:169`). No skew clamp, no `received_at`. A wrong terminal clock mis-dates the whole day-book. |
| **G8 — Per-sale sync round-trips** | **Confirmed (perf)** | `offline_sync_service.dart:37-47` `syncAll` loops one `POST /sales` per item. No `/sales/batch` route exists. `_tryReconcile:84` also sends one `client_ref` at a time despite `verify-batch` accepting an array. |
| **G9 — At-rest PII in queue** | **Confirmed** | `offline_sales_queue.db` opened plaintext (`:86-107`), payload includes `meta.customer_snapshot` with name, **phone, and address** (`sale_create.dart:620-632`). Note: spec says "name + phone are enough"; the code also stores address, so the minimisation gap is slightly larger than stated. |

**Part B result: 9/9 gaps real.**

---

## Corrections — read these before scheduling Phase 2

The spec describes the G3/G6 failure as sales being "marked **terminally** failed" / "sit **forever**." The code is more nuanced, and the nuance changes the symptom you'll actually see:

1. **`failed` is not a dead end — it is silently retried on every sync.** `pendingOrFailed()` selects `status IN ('pending','failed')` (`offline_sales_queue_service.dart:141-150`), and both `syncAll` and the connectivity auto-sync iterate that set. So a transient 500 that gets mislabeled `failed` **is** re-attempted on the next Sync Now / reconnect. The real damage of G3 is therefore not "lost until a human acts" but: **(a)** a transient blip surfaces to the cashier as a red *"needs manual review"* alarm (`offline_sync_screen.dart:87,113`), and **(b)** with no backoff or attempt cap it re-hammers a struggling server on every trigger.

2. **G6's true bug is the opposite of "sits forever" — it's "loops forever."** Because `failed` items are re-picked every sync, a *genuinely* terminal 422 (deleted product) is retried indefinitely with no cap and no dead-letter parking. The enqueue comment at `offline_sales_queue_service.dart:113-117` claims a broken item "surfaces as failed … rather than looping forever" — in practice it re-runs on each subsequent sync. So both classes (transient and terminal) are handled wrongly, just in mirror-image ways.

Net effect: Phase 2B is still the right fix (typed `ApiException(statusCode)`, three-way retry/auth/terminal classification, `attempts` + backoff + cap, real dead-letter). But frame it as *"stop mislabeling and stop uncapped looping,"* not *"rescue sales stuck at failed"* — the QA probe for §2.3 should assert an attempt **cap** and backoff timing, not just that a retry eventually happens.

---

## Prerequisites the spec's Phase-2 fix silently depends on

- **G2 and G3 share a root cause: `ApiClient` swallows the HTTP status.** Both the "distinguish which UNIQUE fired" work (backend, G2) and the "classify by status" work (client, G3) assume the client can read the status code. Today it can't (`api_client.dart:155`). Introducing a typed `ApiException(statusCode, message)` in `_handleResponse` is a hard prerequisite for G3/G4 and should be the first commit of Phase 2.
- **`generateInvoiceNo` runs inside the `DB::transaction` but takes no row lock** (`SaleController.php:215,586`). The spec's "counter table + `lockForUpdate`" is the correct fix; the "minimum" retry-loop variant only works *if* the catch first distinguishes the `invoice_no` index from the `client_ref` index — currently `isUniqueViolation` can't tell them apart, so that branch would still mis-handle it.

---

## Bottom line

The spec is safe to build from as written, with two amendments: (1) treat the G3/G6 problem as *mislabeling + uncapped looping* rather than *terminal loss*, and adjust the acceptance probe accordingly; (2) make the typed-status `ApiException` refactor the explicit first step of Phase 2, since G2, G3, and G4 all depend on it. Phase 1 (offline catalog cache) remains correctly identified as the highest-value gap — it is the only one that breaks the core "complete a sale offline" mandate outright.
