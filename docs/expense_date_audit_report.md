# Expense Date Bug — Root-Cause Audit Report

**System:** CounterIQ Enterprise POS  
**Date:** 2026-07-22  
**Reported symptom:** An expense with `txn_date = 2026-07-22` (Asia/Karachi) appears in the P&L only when the date range is widened to include 2026-07-21.  
**Constraint:** This report is read-only. No code was patched during the audit.

---

## 1. Confirmed Evidence (User-Supplied)

| Fact | Value |
|---|---|
| App timezone | `Asia/Karachi` (UTC+5), confirmed in `.env` |
| DB engine | SQLite (`database/database.sqlite`) |
| P&L `from` Carbon | `2026-07-22 00:00:00.000000 Asia/Karachi` — correct |
| P&L `to` Carbon | `2026-07-22 23:59:59.000000 Asia/Karachi` — correct |
| Expense appears in range | `2026-07-21 → 2026-07-22` (and any start ≤ 2026-07-21) |
| Expense absent from range | `2026-07-22 → 2026-07-22` (exact single-day) |

---

## 2. Full Data Flow Trace

### 2.1 Flutter — date picker and serialization

**File:** `lib/screens/cashbook/expense_create_screen.dart`

```dart
DateTime _txnDate = DateTime.now();   // local DateTime, no UTC conversion

String _fmtDate(DateTime d) =>        // formats as YYYY-MM-DD (pure date, no time)
    "${d.year.toString().padLeft(4,'0')}-…";

txnDate: _fmtDate(_txnDate),          // passes "2026-07-22" to API service
```

**File:** `lib/api/cash_ledger_service.dart`

```dart
if (txnDate != null && txnDate.isNotEmpty) 'txn_date': txnDate,
```

**Verdict:** Flutter sends `"txn_date": "2026-07-22"` — a plain YYYY-MM-DD string. No `toUtc()`, no ISO-8601 full timestamp, no timezone problem at the HTTP layer.

### 2.2 Laravel — request validation

**File:** `app/Http/Requests/CashLedgerEntryRequest.php`

```php
'txn_date' => ['nullable', 'date_format:Y-m-d'],
```

`"2026-07-22"` validates correctly. `toServicePayload()` passes it unchanged.

### 2.3 Laravel — CashLedgerService (domain write)

**File:** `app/Services/CashLedgerService.php`

```php
$txnDate = $data['txn_date'] ?? now()->toDateString();   // "2026-07-22"

CashLedgerEntry::create(['txn_date' => $txnDate, …]);

$journal = $this->accounting->post(
    …,
    entryDate: $txnDate,    // "2026-07-22" forwarded as string
    …
);
```

### 2.4 Laravel — AccountingService (journal write)

**File:** `app/Services/AccountingService.php`

```php
$je = JournalEntry::create([
    'entry_date' => $entryDate ?? now()->toDateString(),   // "2026-07-22"
    …
]);
```

`entry_date` is a `date not null` column in SQLite. When a plain PHP string `"2026-07-22"` is written, SQLite stores it verbatim as the 10-character string `'2026-07-22'`.

**Verified in DB:**

```
entry_date stored as pure date (len = 10): 392 rows   ← expenses + sales
entry_date stored as datetime string (len > 10):  16 rows   ← some payment receipts
                                                              (Carbon passed instead of string)
```

The 16 datetime-format outliers (`'2026-07-22 00:00:00'`) come from callers such as `SalePostingService` that pass a Carbon object rather than `->toDateString()`. The JournalEntry model has no `date` cast to normalize storage.

### 2.5 Laravel — P&L query (the break point)

**File:** `app/Services/ProfitLossService.php`

```php
// Date-range normalization
$from = $p['from'] instanceof Carbon
    ? $p['from']->copy()->startOfDay()   // Carbon in Asia/Karachi
    : Carbon::parse($p['from'])->startOfDay();
$to   = …->endOfDay();

// ← WRONG COALESCE ORDER
$effDateExpr = "COALESCE(jp.created_at, je.entry_date, je.created_at)";

$q->whereRaw("$effDateExpr >= ?", [$from->format('Y-m-d H:i:s')]);
// → binds "2026-07-22 00:00:00"  (datetime string)
$q->whereRaw("$effDateExpr <= ?", [$to->format('Y-m-d H:i:s')]);
// → binds "2026-07-22 23:59:59"
```

**P&L controller call site:**

```php
$data = $svc->summary([
    'from' => $request->date('from'),   // Carbon in Asia/Karachi
    'to'   => $request->date('to'),
    …
]);
```

---

## 3. Two Confirmed Root Causes

### BUG-1 — Wrong COALESCE column order (primary)

`jp.created_at` — the journal **posting's** row-creation timestamp — is first in the COALESCE. It is **never NULL**.

```
journal_postings with NULL created_at: 0   ← confirmed, 0 of 408 journal entries
```

Because COALESCE stops at the first non-NULL value, `je.entry_date` (the user-selected accounting date) is **completely ignored in every P&L query**. The report runs on the physical database insert timestamp, not the business date.

**Impact:**

| Scenario | entry_date | jp.created_at | COALESCE result | P&L shows |
|---|---|---|---|---|
| Normal (entered today, dated today) | 2026-07-22 | 2026-07-22 xx:xx | 2026-07-22 xx:xx | Correct |
| Forward-dated (entered Jul 21, txn_date Jul 22) | 2026-07-22 | 2026-07-21 xx:xx | **2026-07-21 xx:xx** | **Wrong — July 21** |
| Backdated (entered Jul 22, txn_date Jul 21) | 2026-07-21 | 2026-07-22 xx:xx | **2026-07-22 xx:xx** | **Wrong — July 22** |

### BUG-2 — SQLite date-vs-datetime text comparison (secondary, independently fatal)

`entry_date` is stored as a 10-character date string (`'2026-07-22'`). The P&L filter binds a 19-character datetime string (`'2026-07-22 00:00:00'`). SQLite compares text columns lexicographically.

**Proven in the live database:**

```sql
SELECT '2026-07-22' >= '2026-07-22 00:00:00'  →  0  (FALSE)
SELECT '2026-07-22' <  '2026-07-22 00:00:00'  →  1  (TRUE)
SELECT '2026-07-22' <= '2026-07-22 23:59:59'  →  1  (TRUE)
SELECT '2026-07-22' >= '2026-07-21 00:00:00'  →  1  (TRUE)
```

**Consequence:** If the COALESCE were corrected to use `je.entry_date` first, every expense stored as `'2026-07-22'` would:

- **Fail** `>= '2026-07-22 00:00:00'` → excluded from the July 22 P&L
- **Pass** `>= '2026-07-21 00:00:00'` AND `<= '2026-07-22 23:59:59'` → appears when July 21 is in range

This is the exact symptom described in the bug report.

---

## 4. Why the Bug Produces the Exact Reported Symptom

For the forward-dated scenario (expense created July 21, txn_date = July 22):

```
entry_date        = '2026-07-22'        (user's intended business date)
jp.created_at     = '2026-07-21 HH:MM'  (physical insert time)

COALESCE result   = '2026-07-21 HH:MM'  ← BUG-1 picks insert time

P&L filter [Jul 22 only]:
  '2026-07-21 HH:MM' >= '2026-07-22 00:00:00' → FALSE → EXCLUDED

P&L filter [Jul 21 → Jul 22]:
  '2026-07-21 HH:MM' >= '2026-07-21 00:00:00' → TRUE
  '2026-07-21 HH:MM' <= '2026-07-22 23:59:59' → TRUE → INCLUDED (on wrong date)
```

For the SQLite comparison scenario (if BUG-1 were fixed but BUG-2 remained):

```
entry_date        = '2026-07-22'        (pure date string from CashLedgerService)

COALESCE result   = '2026-07-22'        ← correct date, wrong format

P&L filter [Jul 22 only]:
  '2026-07-22' >= '2026-07-22 00:00:00' → FALSE → EXCLUDED  ← BUG-2

P&L filter [Jul 21 → Jul 22]:
  '2026-07-22' >= '2026-07-21 00:00:00' → TRUE
  '2026-07-22' <= '2026-07-22 23:59:59' → TRUE → INCLUDED
```

Both bugs independently reproduce the reported symptom. In production they compound each other.

---

## 5. Scope of Impact Across All Report Services

| Service | COALESCE order | Comparison format | Status |
|---|---|---|---|
| `ProfitLossService` | `jp.created_at` first ❌ | `format('Y-m-d H:i:s')` datetime ❌ | **Both bugs present** |
| `LedgerService` | `jp.created_at` first ❌ | `DATE()` + date string ✓ | BUG-1 only |
| `UnifiedCashFlowService` | `je.entry_date` first ✓ | `DATE()` + date string ✓ | Clean |
| `SubledgerService` | `je.entry_date` first ✓ | `DATE()` + date string ✓ | Clean |
| `DayBookService` | `je.entry_date` direct ✓ | `whereDate()` Laravel helper ✓ | Clean |

**UnifiedCashFlowService** (`COALESCE(je.entry_date, je.created_at, jp.created_at)` with `DATE()`) is the correct reference pattern.

---

## 6. Inconsistent entry_date Storage Format

16 of 408 journal entries have `entry_date` stored as a datetime string (`'YYYY-MM-DD HH:MM:SS'`) instead of a pure date. These come from callers (e.g., sale payment receipts) that pass a `Carbon` object to `AccountingService::post()` without calling `->toDateString()`.

The `JournalEntry` model has no `$casts = ['entry_date' => 'date']` to normalize input at the model level. This is a latent inconsistency that `DATE()` wrapping at query time would absorb, but the model should be fixed regardless.

---

## 7. What Was Explicitly Eliminated

| Hypothesis | Result |
|---|---|
| Flutter sends UTC ISO-8601 timestamp | Eliminated — `_fmtDate()` sends pure `YYYY-MM-DD`, no time, no UTC conversion |
| UTC midnight shift (midnight local = prior day UTC) | Eliminated — APP_TIMEZONE is Asia/Karachi; timestamps stored in local time; no UTC shift in filter |
| Wrong Carbon from/to in P&L controller | Eliminated — user-confirmed Carbon objects are correct |
| P&L reads from wrong table/column | Eliminated — reads journal_postings joined to journal_entries correctly |
| `entry_date` not being written | Eliminated — DB confirms entry_date='2026-07-22' for the expense row |

---

## 8. Recommended Fix

### 8.1 ProfitLossService (fixes both bugs)

```php
// BEFORE (both bugs):
$effDateExpr = "COALESCE(jp.created_at, je.entry_date, je.created_at)";
$q->whereRaw("$effDateExpr >= ?", [$from->format('Y-m-d H:i:s')]);
$q->whereRaw("$effDateExpr <= ?", [$to->format('Y-m-d H:i:s')]);

// AFTER (follows the UnifiedCashFlowService pattern):
$effDateExpr = "DATE(COALESCE(je.entry_date, je.created_at))";
$q->whereRaw("$effDateExpr >= ?", [$from->toDateString()]);
$q->whereRaw("$effDateExpr <= ?", [$to->toDateString()]);
```

`DATE()` normalizes both pure-date strings and datetime strings to `YYYY-MM-DD`. Comparing against `toDateString()` (`YYYY-MM-DD`) avoids the lexicographic mismatch entirely.

### 8.2 LedgerService (fixes BUG-1)

```php
// BEFORE:
$effDateExpr = "COALESCE(jp.created_at, je.entry_date, je.created_at)";

// AFTER:
$effDateExpr = "COALESCE(je.entry_date, je.created_at)";
// (LedgerService already uses DATE() + date strings — only COALESCE order needs fixing)
```

### 8.3 JournalEntry model (normalizes storage)

Add to `app/Models/JournalEntry.php`:

```php
protected $casts = [
    'entry_date' => 'date:Y-m-d',   // ensures Carbon is stored as YYYY-MM-DD
];
```

This prevents future callers from accidentally storing datetime-format values in the date column.

### 8.4 AccountingService — defensive normalization

Optionally, add a guard in `AccountingService::post()`:

```php
'entry_date' => $entryDate
    ? Carbon::parse($entryDate)->toDateString()   // normalize any format to Y-m-d
    : now()->toDateString(),
```

---

## 9. Historical Data

392 existing journal entries have `entry_date` correctly stored as `'YYYY-MM-DD'`. Once the query is fixed (using `DATE()` and date-string comparisons), these rows will be matched correctly without any data migration. The 16 datetime-format outliers will also be handled correctly by `DATE()`.

**No historical accounting records need to be altered.**

---

## 10. Test Plan

| # | Scenario | Expected after fix |
|---|---|---|
| T-01 | Expense entered and dated on the same day | Appears in P&L for that date only |
| T-02 | Expense entered July 21, txn_date set to July 22 | Appears in P&L for July 22 only, not July 21 |
| T-03 | Expense entered July 22, backdated txn_date to July 21 | Appears in P&L for July 21 only, not July 22 |
| T-04 | P&L range `Jul 22 → Jul 22` (single day) | Expenses with entry_date Jul 22 appear; no leakage from other days |
| T-05 | P&L range `Jul 21 → Jul 22` (two days) | Expenses split correctly by their entry_date, not insert timestamp |
| T-06 | Sale (entry_date stored as datetime string) in P&L range | Appears on the correct date via DATE() normalization |
| T-07 | Voided expense | Does not appear in P&L (reversal cancels it) |
| T-08 | Ledger for a party with backdated receipts | Opening balance and movements respect entry_date |
| T-09 | P&L with no date filter | All entries returned without date exclusion |
| T-10 | Concurrent expenses on the same date from different branches | Correctly partitioned by branch_id |

---

## 11. Assumptions and Open Questions

1. The fix assumes SQLite remains the production DB. If migrating to MySQL or PostgreSQL, `DATE()` behaviour is consistent across all three — no further changes needed.
2. `LedgerService` uses `jp.created_at` first in COALESCE. Whether party ledger history for existing data should be recalculated with `entry_date`-ordered history is a business decision. The fix does not retroactively reorder displayed ledger rows.
3. The `endOfDay()` fence (`23:59:59`) excludes postings stamped at `23:59:59.500` or beyond. A cleaner boundary is `< nextDay 00:00:00`, but this is a pre-existing design choice and not part of the reported bug.

---

*Audit performed on: 2026-07-22 | Files read: read-only | No code was patched during this audit.*
