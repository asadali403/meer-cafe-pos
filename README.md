# Meer Cafe POS

Offline-first billing, receipt printing, product management and reporting for **Meer Cafe**,
built with Flutter for Windows. Bills are stored in a local SQLite database and copied to
Google Sheets when internet is available.

*Our Circle. Your Place.*

---

## Install on a Windows laptop (no Flutter needed)

1. On the GitHub page click **Code → Download ZIP**.
2. Right-click the downloaded ZIP → **Extract All** → **Extract**.
3. Open the extracted folder and double-click **`Install.bat`**.
   *(If Windows shows "Windows protected your PC", click **More info → Run anyway**.)*
4. Double-click **Meer Cafe POS** on the Desktop. On the first start create the admin account.

The ready-built app is in `dist\MeerCafePOS\` (Windows 10/11, 64-bit). It works offline.
To move your existing cafe data to the new laptop, make a backup on the old laptop
(**Backup → Back up to USB / folder**) and restore it on the new one
(**Backup → Restore from file**). See `docs\BACKUP_RESTORE.md`.

---

## 1. Daily use (no VS Code, no commands)

* Double-click **Meer Cafe POS** on the Desktop (or Start Menu). It opens maximized on the
  login screen. No internet is needed to start, sign in, bill or print.
* **Cashier:** Billing → tap products → adjust quantities → enter *Amount received* →
  **Complete Bill (F9)** → receipt prints → **New Bill**.
* **Admin:** Dashboard, Products, Reports, Sync, Users, Settings, Backup. Click the sidebar
  logo to open Users and view account roles, status and last-login information.

Keyboard: **F2** = search products, **F9** = complete bill, **Enter** in the
"Amount received" box = complete bill.

## 2. First run

On the very first start the app shows **First-time setup**: choose the admin username
and password (min. 8 characters, letters + numbers). There is **no default password**
anywhere in the app. Tick *Load sample cafe menu* to start with 23 sample products.

Create cashier accounts in **Users → Add user** with a temporary password. Each new or
reset account **must change its password at first login**.

## 3. Features

| Area | What it does |
|---|---|
| Roles | Admin (everything) and Cashier (billing, own bill history, payments, reprints). Checked in the data layer, not only hidden in the UI. |
| Passwords | PBKDF2-HMAC-SHA256 (120,000 iterations, random salt). 5 wrong attempts lock the account for 5 minutes. |
| Products | Add/edit/delete (soft delete), activate/deactivate, custom categories, descriptions. Cashiers cannot change prices. |
| Billing | Search, category filters, product cards, qty +/−, remove, clear, discount (Rs or %), optional cash rounding shown as its own line, amount received, change / balance due, payment method. |
| Money | Stored as integer **paisa** — no floating-point maths. Displayed as `Rs. 1,250.00`. |
| Bills | Bill + items + first payment saved in **one SQLite transaction**. Each cart has a unique id, so double-clicking *Complete Bill* can never create two bills. |
| Invoice numbers | `MC-YYYYMMDD-NNNN`, sequential per day, stored in the DB (continue after restart), unique index. Only one copy of the app can run at a time. |
| Payments | Partial payments and later payments on outstanding balances. Collected money is tracked separately from billed sales. |
| Receipts | Real PDF receipt layout for 58 mm / 80 mm thermal and A4 printers: logo, tagline, address, phone, invoice, cashier, items, totals, received, change/balance, PAID / PARTIALLY PAID, QR code, thank-you message. Preview, printer selection, reprint (marked *DUPLICATE COPY*). A failed print never affects the saved bill. |
| Reports | Daily / weekly / monthly / custom range, product-wise, cashier-wise, payment methods, payments collected, paid / partial / unpaid bills, outstanding balances. Export to CSV (opens in Excel). |
| Sync | Google Sheets via a signed Apps Script endpoint, persistent queue, automatic retry, idempotent upserts, status counts, Sync Now, error list and log. See `docs\GOOGLE_SHEETS_SETUP.md`. |
| Backup | Automatic daily backup (30 kept), manual backup to any folder/USB, restore with validation. See `docs\BACKUP_RESTORE.md`. |

## 4. Where things are stored

| What | Location |
|---|---|
| Installed app | `%LOCALAPPDATA%\Programs\Meer Cafe POS\MeerCafePOS.exe` |
| Database | `%APPDATA%\MeerCafePOS\data\meer_cafe.db` |
| Automatic backups | `%APPDATA%\MeerCafePOS\backups\` |

The database is **outside** the project and install folders, so rebuilding or reinstalling
the app never deletes data.

## 5. Building from source

Requirements (already set up on this laptop): Flutter 3.x stable, Visual Studio 2022/2026
with **Desktop development with C++**.

```powershell
cd "C:\Users\asada\OneDrive\Desktop\cafe system\meer_cafe_pos"
flutter pub get
flutter test                                              # run automated tests
powershell -ExecutionPolicy Bypass -File tool\install.ps1  # release build + install + shortcuts
```

`tool\install.ps1` builds `build\windows\x64\runner\Release\`, copies it to
`%LOCALAPPDATA%\Programs\Meer Cafe POS`, and creates Desktop + Start Menu shortcuts.
To move the app to another PC, copy the whole `Release` folder (it is self-contained) and
run `MeerCafePOS.exe`, or run `install.ps1 -NoBuild` there.

To change the logo: replace `assets\images\logo.png` (square PNG), delete nothing else,
run `powershell -ExecutionPolicy Bypass -File tool\make_logo.ps1` to rebuild the app icon,
then reinstall. The receipt logo can also be changed in **Settings → Choose logo**.

## 6. Project structure

```
lib/
  main.dart                 entry point
  app/                      theme, root widget, AppController (DB, session, services)
  models/                   User, Product, Category, Bill, BillItem, Payment, AppSettings
  database/                 SQLite open/migrations/integrity check/backup copy
  repositories/             data access + role checks (users, products, bills, reports, settings, sync queue)
  services/                 billing calculator, password hashing, receipt PDF, printing, sync, backup, CSV
  screens/                  login, dashboard, billing, products, reports, settings (sync/users/backup)
  widgets/                  shared UI pieces and bill dialogs
  utils/                    money, dates, ids, errors
google_apps_script/Code.gs  Google Sheets endpoint
test/                       automated tests
tool/                       install.ps1, make_logo.ps1
docs/                       setup, backup, troubleshooting guides
```

## 7. Tests

`flutter test` covers: money parsing/formatting, subtotal/discount/rounding/change/balance,
password hashing & lockout, role checks (cashier cannot change prices), product persistence
across restarts, atomic bill transactions with rollback, duplicate-click protection, price
snapshots, invoice numbering (per day, across restarts), partial/additional payments, and
Google Sheets sync deduplication, offline retry and signature verification.

See also: `docs\TROUBLESHOOTING.md`, `docs\BACKUP_RESTORE.md`, `docs\GOOGLE_SHEETS_SETUP.md`.
