# Inventra — setup and how it works

Offline-first inventory and sales app for Android and iOS.

- **Phase 1:** shops, categories, items, packs/bulk prices, price history, suppliers, barcode scanning, stock adjustments, settings.
- **Phase 6:** expenses with types, shop or whole-business costs, net profit after expenses in Reports, PDF and CSV.
- **Phase 5:** Reports tab (period presets or custom dates, this shop or all shops, comparison with the previous period, sales-by-day chart, best sellers, categories, money received by method, stock value), automatic day/week/month summaries, exchange rates (daily online or your own) for combined totals, and exports: report PDF plus sales, items-sold and stock-list CSV files for Excel.
- **Phase 4:** sign-in with Supabase, cloud backup and sync with PowerSync, restore on a new phone, Owner/Staff roles, staff invites with shop limits and permissions, new logo, app icon and splash screen.
- **Phase 3:** receive stock from suppliers (by piece, pack or carton, with cost and batch expiry), restock history per shop, item and supplier, stock count with automatic corrections, and an alerts centre for low/out-of-stock, expiring and expired items and overdue unpaid sales.
- **Phase 2:** Sell tab (search or scan), cart with pack sizes, price edits and discounts, cash/transfer/POS payments, part-paid and credit sales, receipts shared as PDF or printed, sales history, cancelling a sale (stock goes back), customers with balances, business details on receipts.

 Everything is stored on the phone; sign-in and cloud sync (Supabase + PowerSync) come in phase 4.

## First-time setup

You need Flutter 3.27 or newer (`flutter --version`).

```bash
cd inventra

# 1. Generate the android/ and ios/ folders (keeps the existing lib/ code)
flutter create . --project-name inventra --org com.inventra --platforms android,ios

# 2. Get packages
flutter pub get

# 3. Run the tests, then the app on a phone or emulator
flutter test
flutter run
```

If `flutter pub get` reports a version conflict, run `flutter pub upgrade --major-versions` and try again.

### iOS permissions (required for camera and photos)

Add these inside `<dict>` in `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Inventra uses the camera to scan barcodes and take item photos.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Inventra lets you choose item photos from your library.</string>
```

In `ios/Podfile`, set the minimum iOS version near the top:

```ruby
platform :ios, '15.5'
```

### Android

Camera permission is added automatically by the scanner package. If the build complains about `minSdk`, set `minSdk = 21` (or higher) in `android/app/build.gradle(.kts)`.

## Project layout

```
lib/
  main.dart                 opens the database, loads settings, starts the app
  app/                      app widget, router (bottom tabs), theme
  core/
    db/schema.dart          full local schema (all phases), money in minor units
    db/database.dart        opens the PowerSync SQLite database
    session.dart            business id, device code, photo folder
    local_settings.dart     phone-only preferences
    utils.dart              ids, dates, Money, currencies
    widgets.dart            shared dialogs and widgets
  features/
    home/                   stock dashboard for the current shop
    shops/                  shops (main categories), switcher
    catalogue/              item categories, items, units, status, detail/edit
    suppliers/              suppliers and item-supplier links
    scan/                   barcode scanner screen
    settings/               text size, colour, theme, analytics period
    more/                   More tab, coming-soon placeholders
    sales/                  cart, sell screen, checkout, receipt PDF, history
    customers/              customers, balances, picker used at checkout
    business/               business name/phone/address for receipts
    inventory/              restocks, stock count, alerts
    account/                sign-in, linking, team, invites, permissions
    reports/                periods, report queries, summaries, rates, exports
  core/sync/                PowerSync connector to Supabase, sync status
supabase/migrations/        database tables, RLS, functions (run in Supabase)
powersync/sync_rules.yaml   what each phone downloads (paste in PowerSync)
assets/branding/            logo, app icon, splash images
test/                       money, status, cart, payments, permissions, periods, rates, CSV
```

## How data works

- Stock is never edited directly. Every change is a row in `stock_movements` (opening stock, restock, damaged, missing, returned, correction; sales in phase 2). Current stock = sum of movements, so it stays right when several phones sync later.
- Changing a cost or selling price (including pack prices) writes a row to `price_history`.
- Money is stored as whole minor units (₦1,250.50 → 125050) to avoid rounding errors.
- Deletes are soft (`deleted_at`) so they can sync.
- Item status (available, low, out, expired, discontinued) is calculated, not stored.
- Records are written through PowerSync's local database from day one. In phase 4, connecting PowerSync to Supabase uploads everything created before sign-in.

## Updating from phase 1

Copy the new `lib/`, `test/`, `assets/` and `pubspec.yaml` over your project, then run `flutter pub get`. Your existing data stays: the new columns are added automatically.

## How sales work

- Completing a sale writes the sale, its lines, the payment and one stock movement per line in a single transaction, so stock and sales can never disagree.
- Each line stores the price and cost at the time of sale, so later price changes don't rewrite past profit.
- Receipt numbers look like `INV-A3F9-00042`: the device code keeps two offline phones from producing the same number.
- A sale that isn't fully paid needs a customer, so the balance shows on their record. Record later payments from the sale page.
- Cancelling a sale marks it cancelled and puts the stock back; it stays in history.
- Receipts use the bundled DejaVu Sans font (assets/fonts, free licence) so ₦ £ € ¥ print correctly.

## How stock control works

- **Receive stock** writes a restock record and a +stock movement. It can also update the item's cost price (logged in price history), set the item's expiry date from the batch, and update the supplier's price and last-supplied date.
- **Count stock**: type what you count; on save, each item that differs gets one correction movement (`Stock count: 12 → 10`). Uses the stock at the moment you save, so sales made during the count are respected.
- **Alerts** are worked out live from current data (no background job): the bell on Home shows the count. Thresholds are in Settings.
- Phone notifications (when the app is closed) are not included yet: they need extra Android/iOS setup and can be added later with `flutter_local_notifications`.

## Build notes

- `pubspec.yaml` pins `image: 4.5.4` under `dependency_overrides`. Newer `image` versions call an `archive` method that older `archive` versions lack. If you'd rather not pin, remove the override and run `flutter pub upgrade`.
- PowerSync files import only `PowerSyncDatabase` (`show PowerSyncDatabase`) because PowerSync's `Column` class clashes with Flutter's `Column` widget.

## Phase 4 setup: Supabase and PowerSync (one time, about 15 minutes)

The app keeps working without these steps; they are needed only for sign-in and sync.

**1. Create the database (Supabase)**
- Supabase dashboard → project *inventra* → **SQL Editor** → New query.
- Paste all of `supabase/migrations/0001_inventra.sql` → **Run**. (Safe to run again later.)
- It creates every table, the access rules (RLS), the setup functions, and the `powersync` publication.

**2. Email sign-in (Supabase)**
- **Authentication → Sign In / Providers → Email**: make sure it's enabled.
- While testing, turn **Confirm email** off so new accounts can sign in immediately. Turn it back on before launch.

**3. Connect PowerSync to the database**
- PowerSync dashboard → your instance → **Database Connections** → Connect to Supabase.
- In Supabase click **Connect** (top bar) → **Direct connection** and copy the details. Host is `db.fvsjuqcdsxdiqejvqygd.supabase.co`, port `5432`, database `postgres`, user `postgres`, and your database password (Project Settings → Database → reset it if you don't have it).
- If PowerSync can't reach that host, use the **Session pooler** connection details from the same Connect window instead.

**4. Let PowerSync trust Supabase sign-ins**
- PowerSync → your instance → **Client Auth** → turn on **Use Supabase Auth** (enter the project URL `https://fvsjuqcdsxdiqejvqygd.supabase.co` if asked) → Save and deploy.

**5. Sync rules**
- PowerSync → your instance → **Sync Rules**: replace the contents with `powersync/sync_rules.yaml` → **Validate** → **Deploy**.

**6. Check the instance URL**
- PowerSync → your instance → **Connect** shows the instance URL. If it differs from `powersyncUrl` in `lib/core/config.dart`, paste it there.

**7. Android internet permission (release builds)**
- In `android/app/src/main/AndroidManifest.xml`, above `<application`, add:
  `<uses-permission android:name="android.permission.INTERNET"/>`
  (Debug builds already have it; release builds won't sync without it.)

**8. Icon and splash**
```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

### Try it
1. Owner phone: More → **Account and sync** → Create account → **I own the business** → name it. Everything already on the phone uploads. Check Supabase → Table Editor → `items`.
2. Owner: More → **Team** → **Invite staff** → pick shops and permissions → share the 6-letter code.
3. Staff phone: install, More → Account and sync → Create account → **I work for a business** → type the code. The business downloads, limited to their shops.
4. New phone for the owner: sign in → tap the business → everything downloads (this is your backup/restore).

### How sync works
- Every screen reads and writes the phone's own database; nothing waits for the internet.
- PowerSync uploads each change to Supabase (through RLS) and streams other phones' changes down.
- Records made before signing in use a placeholder user; the uploader swaps in your real account.
- If the server refuses a change (for example staff without permission), it's skipped so the rest can sync, and Account and sync shows a warning.
- Staff limited to some shops only see those shops in the app; the server also refuses their writes to other shops. They do download the whole business's data, so treat staff phones as trusted.

## How reports work

- Reports read the phone's database, so they work offline and include sales from other phones once synced.
- Cancelled sales are excluded. Profit = sales − cost recorded on each sale line, so fill in cost prices.
- **Summaries**: when the owner opens the app, a summary is saved for every finished day, week or month (Settings → Analytics) for each shop. Ids come from the period, so two phones never create duplicates. Find them under Reports → history icon.
- **Exchange rates**: fetched at most once a day from ExchangeRate-API's free endpoint (`open.er-api.com`, no key; attribution shown in the app). A rate you type replaces the online one until you switch back. Rates sync to every phone.
- **Exports** open the share sheet: PDF report, or CSV files (with a BOM so Excel shows ₦ correctly). CSV opens directly in Excel and Google Sheets.
- Staff see Reports only with the "See cost prices, profit and stock value" permission, and only for their shops.

## Expenses

- More → **Expenses** (or the Home shortcut). Pick a type (rent, salaries, generator fuel…) or type your own.
- An expense belongs to the current shop, or (owner) to the **whole business**.
- Reports show **Expenses** and **Net profit = profit − expenses** with comparison to the previous period. A shop view counts that shop's expenses; "All shops" also counts whole-business ones.
- Staff need the "Record expenses" permission.

Releasing to the Play Store and App Store: see [RELEASE.md](RELEASE.md).
