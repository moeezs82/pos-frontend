# POS speed fix — customer / vendor / salesman / product selection

## The problem
Every "Select Customer / Vendor / Salesman / Delivery Boy / Product" sheet
re-fetched from the backend from scratch on every open, and blocked on a
spinner until that request returned. Typing in the search box just retriggered
the same blocking fetch after a debounce. For a fast counter-sale flow this
meant a network round trip (and a visible loader) on almost every tap.

## What changed
1. **`lib/services/pick_cache.dart`** (new) — a small in-memory
   "stale‑while‑revalidate" cache. Each entity type (customers, vendors,
   users/salesmen/delivery boys, products) gets its own cache bucket(s).
   `peek()` returns whatever's cached instantly, with no `await`. `refresh()`
   always hits the network in the background and updates the bucket when it
   lands.

2. **`lib/services/party_pick_caches.dart`** (new) — wraps your existing
   `CustomerService` / `VendorService` / `UsersService` / `ProductService`
   with cache-aware fetch helpers, reusing all your existing parsing logic
   (e.g. the same tolerant product-response parsing that was already in
   `ProductPickerGridSheet`).

3. **`lib/services/party_prefetch.dart`** (new) — fire-and-forget "warm the
   cache" calls. `sale_create.dart` and `purchase_create.dart` call this in
   `initState()`, so by the time staff tap "Select Customer" a second or two
   later, the data is usually already sitting in memory.

4. **`lib/widgets/party_autocomplete_field.dart`** (new) — a typeahead text
   field: typing filters the cached list instantly (no network wait), with a
   debounced background search to widen results, and a "Browse full list…"
   action / list-icon button that opens the exact same picker sheet as
   before. This satisfies the requirement that the old full-list browsing
   experience stays available for anyone who'd rather scroll than type.

5. **Picker sheets updated** (`customer_picker_sheet.dart`,
   `vendor_picker_sheet.dart`, `user_picker_sheet.dart`,
   `product_picker_grid_sheet.dart`): each one now shows cached data
   immediately on open (no spinner if anything is cached) and silently
   refreshes in the background every time, per your instruction to "always
   double check" rather than trust the cache blindly. Typing filters the
   cached list locally first; the network call only refines/confirms.

6. **`sale_create.dart` / `sale_party_section.dart`**: the Customer, Salesman,
   Delivery Boy, and Vendor fields in the sale screen are now
   `PartyAutocompleteField`s instead of plain tap-to-open buttons. Tapping the
   list icon (or "Browse full list…") still opens the original full sheet.

7. **`purchase_create.dart`**: same treatment for the Vendor field. Also
   fixed a layout bug where the row layout would crash/misrender when there
   was only one field and `isAll` was false (it indexed `fields[1]` on a
   1-item list).

## Important correctness fix made during review
While double-checking this before sending it over, I found and fixed two real
bugs in my own first draft of the cache:

- **Key mismatch**: the cache was writing fetched data under one key (bucket
  + search text + page) but every read used a different, simpler key (just
  the bucket). They never matched, which would have made the entire
  "instant" feature silently do nothing. Fixed by splitting `bucketKey`
  (what's stored/read) from `requestKey` (only used to avoid firing duplicate
  concurrent requests).
- **Cache pollution from search**: a search fetch (e.g. typing "john") would
  have overwritten the *shared* "all customers" bucket with only the
  filtered results, corrupting what every other screen sees. Fixed so only
  unfiltered (empty search) fetches write back to the shared bucket; search
  results are applied to that sheet's own local list only.
- **Quick-add scoping**: a newly created salesman could have leaked into the
  unrelated "delivery boy" cache bucket (and vice versa) because of how
  buckets are split by role. Added a scoped `insertInto` (vs the
  all-buckets `insertEverywhere`) and used it for the role/vendor-bucketed
  caches.

## What did NOT change
No backend/API changes. No changes to totals, payments, submission logic,
receipt printing, or any screen not listed above. The four picker sheets
still support full pagination and "Quick Add" exactly as before — they're
just no longer the only way to pick something, and no longer block on the
network when opened.

## Update: real search for large (10k+) customer/vendor lists
The first version of this fix only filtered whatever was sitting in the
local cache (a single ~10-20 row page), which is fine for instant feedback
but can never represent a 10,000-row table — typing a name not on that page
found nothing. Fixed by:

- **`lib/api/customer_service.dart` / `lib/api/vendor_service.dart`**: added
  a `perPage` parameter (your backend already supported `per_page` — the
  Flutter service methods just never sent it).
- **`lib/services/party_pick_caches.dart`**: added a `searchRemote()` helper
  per entity (customers, vendors, salesmen/delivery boys, products) that
  calls your backend's full-database `?search=` directly, bypassing the
  cache bucket entirely — a one-off lookup, not something that pollutes the
  shared list.
- **`lib/screens/sales/parts/sale_party_section.dart` /
  `lib/screens/purchases/purchase_create.dart`**: wired `onSearchRemote` into
  every autocomplete field. This was actually missing in the previous
  delivery — the field supported it, but no call site passed it in, so
  typing only ever filtered the local cache. Now every keystroke (after a
  short debounce) also checks the full database and merges real results in.
- **`lib/services/party_prefetch.dart`**: bumped the warm-cache page size
  from the backend default (10-20) to 200, so plain browsing/first-keystroke
  has a bigger local pool before the live search even kicks in. This is a
  convenience cache only — it intentionally does not try to hold the whole
  table; the live search covers everything beyond it.

With this, typing a customer's name does two things at once: instantly
filters whatever's cached locally (for the "already warm" feeling), and
fires a real server search a moment later that finds anyone in the full
table, merging the results in without any popup or full-page reload.


## How to verify
1. Open Create Sale. Customer/Salesman/Delivery/Vendor fields should now be
   text fields, not buttons.
2. Type 2-3 letters of an existing customer's name — a dropdown should
   appear instantly (no spinner) once the cache has loaded once this
   session.
3. Type a name that is NOT in the first ~200 warm-cached rows (e.g. a
   customer further down a 10,000-row table) — a short "Searching…" state
   should appear, then real results from the full database.
4. Tap the list icon on the right of any field — the original full sheet
   opens, with pagination and Quick Add intact.
5. Re-open the same picker sheet a second time — it should show data
   immediately instead of a blank loading spinner (watch for the small thin
   progress indicator instead, which means it's silently re-checking in the
   background).
