# Backup and restore

All data (users, products, bills, payments, settings, sync queue) is in one SQLite file:

```
%APPDATA%\MeerCafePOS\data\meer_cafe.db
```

(Paste `%APPDATA%\MeerCafePOS` into the File Explorer address bar to open it.)

## Automatic backups

Every day, the first time the app starts, a full copy is saved to
`%APPDATA%\MeerCafePOS\backups\auto_YYYYMMDD.db`. The newest 30 are kept.

## Manual backup (recommended weekly, to a USB drive)

1. Sign in as **admin** → **Backup**.
2. Click **Back up to USB / folder...** and choose the USB drive (or click **Back up now**
   to save in the backups folder).
3. A file named `meer_cafe_backup_YYYYMMDDHHMMSS.db` is created. Backups are made with
   SQLite `VACUUM INTO`, so they are consistent even while billing continues.

## Restore

1. Admin → **Backup** → click **Restore** next to a backup, or **Restore from file...**.
2. Confirm. The app checks the file (integrity check + required tables), saves the current
   database as `pre_restore_*.db` in the backups folder, replaces it, and returns to the
   login screen.

If the database is ever damaged, the app shows a **Database problem** screen at startup
with the latest backups and a **Choose backup file...** button. The damaged file is kept as
`damaged_*.db`.

### Manual restore (if the app will not open at all)

1. Close Meer Cafe POS.
2. Open `%APPDATA%\MeerCafePOS\data\`.
3. Rename `meer_cafe.db` to `meer_cafe.db.old` and delete `meer_cafe.db-wal` and
   `meer_cafe.db-shm` if present.
4. Copy your backup file into this folder and rename it to `meer_cafe.db`.
5. Start Meer Cafe POS.

## Moving to a new laptop

Install the app on the new laptop, start it once and close it, then do the manual restore
above with your latest backup. After restoring, sign in with your existing accounts.
