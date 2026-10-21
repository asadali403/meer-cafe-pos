# Google Sheets sync — setup guide

Meer Cafe POS always saves bills on the laptop first (SQLite). Google Sheets is an
**online copy** that is filled in automatically whenever internet is available.
Billing and printing never wait for, or depend on, Google.

## How it works (and why it is secure)

```
Meer Cafe POS (laptop)  --HTTPS + HMAC signature-->  Google Apps Script web app  -->  your Spreadsheet
   SQLite = source of truth                             (runs as YOU, inside Google)
```

* No Google password, API key or private key is stored in the app or its source code.
* The Apps Script runs under your Google account and is the only thing that can write
  to the spreadsheet.
* Every request is signed with a random **sync secret** (HMAC-SHA256). The script rejects
  any request without a valid signature, so knowing the URL alone is not enough.
* The secret lives only in (a) the Apps Script "Script properties" and (b) the POS
  laptop's local database. Never paste it into chats or emails.
* Rows are **upserted by `id`**: re-sending the same bill updates the same row, so retries
  can never create duplicates.

## One-time setup (about 5 minutes)

1. Go to <https://sheets.google.com> and create a blank spreadsheet. Name it
   **Meer Cafe POS Data**.
2. In the spreadsheet: **Extensions → Apps Script**.
3. Delete everything in `Code.gs`, then paste the full contents of
   `google_apps_script\Code.gs` from this project. Click **Save** (disk icon).
4. In the function drop-down at the top choose **setupMeerCafe** and click **Run**.
   * Google asks for permission: **Review permissions → choose your account →
     Advanced → Go to (project) → Allow**. (It only asks for access to this spreadsheet.)
   * Open **Execution log** — copy the long value after `SYNC_SECRET`.
   * The six worksheets are now created: Products, Bills, BillItems, Payments,
     DailySummary, SyncLog.
5. Click **Deploy → New deployment**.
   * Gear icon → **Web app**.
   * Execute as: **Me**.
   * Who has access: **Anyone** (required so the POS can reach it without a Google login;
     the signature check protects it).
   * Click **Deploy** and copy the **Web app URL** (ends with `/exec`).
6. In Meer Cafe POS sign in as **admin → Sync**:
   * Paste the Web app URL and the secret.
   * Turn on **Enable automatic Google Sheets sync** → **Save**.
   * Click **Test connection** — it should say *Connected to "Meer Cafe POS Data"*.
   * Click **Sync Now**.

## When does it sync?

* When the app starts, every minute while running, when the network comes back, and
  when an admin clicks **Sync Now**.
* Failed uploads are retried automatically with increasing delays (up to 30 minutes).
  **Sync Now** retries immediately.
* The sidebar shows *All synced*, *N pending sync* or *N waiting to sync*.

## Testing it

1. Make a bill → within a minute it appears in **Bills**, **BillItems**, **Payments**.
2. Disconnect Wi-Fi → make 2 bills → they print normally; Sync screen shows them pending/failed.
3. Reconnect → click **Sync Now** (or wait) → each bill appears **exactly once**.
4. Record a payment on a partially paid bill → the same Bills row changes to PAID.

## Changing the secret

Apps Script editor → run **rotateSecret** → copy the new secret from the log → paste it
in POS → Sync → Save. (Old secret stops working immediately.)

## Updating the script later

After editing `Code.gs`: **Deploy → Manage deployments → Edit (pencil) → Version: New
version → Deploy**. The URL stays the same.

## Troubleshooting

| Message | Fix |
|---|---|
| Invalid signature | The secret in POS differs from the script's. Copy it again (run `setupMeerCafe` to view it). |
| Unexpected response from Google | Deployment access is not "Anyone", or the URL is not the `/exec` Web app URL. |
| Request timestamp is too old | Laptop date/time is wrong. Fix Windows clock (Settings → Time → Sync now). |
| Server not configured | Run `setupMeerCafe` once in the Apps Script editor. |
| No connection / did not respond | Offline — nothing to do; it retries automatically. |
