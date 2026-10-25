# Troubleshooting

| Problem | Solution |
|---|---|
| Double-clicking the icon does nothing | The app is probably already open — check the taskbar. Only one copy can run; a second click brings it to the front. |
| "Database problem" screen | See `BACKUP_RESTORE.md` → restore the latest backup from that screen. |
| Forgot admin password | Another admin can reset it (Users → Reset password). If there is no other admin, restore a backup from before the change, or contact your developer — passwords cannot be recovered, only reset. |
| "Too many failed attempts" | Wait 5 minutes, or ask an admin to reset the password. |
| Receipt did not print | The bill is already saved. Check printer power/cable/paper, then **Bills → select bill → Reprint** (or *Print Receipt* on the billing screen). It never creates a second bill. |
| Thermal printer plugged in but not in the list (shows as "80Series", "POS-80" in Device Manager) | Double-click `Setup Printer.bat`, click **Yes**, then choose *Meer Receipt Printer* in Settings → Printer with Printer type = *Thermal*. |
| Receipt prints as garbage characters | Settings → Printer → Printer type: use *Thermal* for 58/80 mm receipt printers, *Windows printer driver* for normal/A4 printers. |
| Printer not in the list | Install the printer's Windows driver, print a Windows test page, then Settings → Printer → refresh. |
| Receipt is cut off / too small | Settings → Printer → Paper width: choose 58 mm or 80 mm to match your roll. In the printer's Windows *Printing preferences* set paper to the roll width. |
| Want the Windows print dialog each time | Settings → Printer → "Ask every time". |
| Sync shows "waiting to sync" | Normal while offline. It retries automatically. Admin → Sync shows the exact error. |
| Sync error "Invalid signature" / "Unexpected response" | See `GOOGLE_SHEETS_SETUP.md` → Troubleshooting. |
| Duplicate rows in Google Sheet | Should not happen (rows are keyed by id). If someone manually copied rows, delete the extra copies; the app will keep updating the original rows. |
| Product missing on billing screen | It is inactive, deleted, or its category is inactive (Products → Categories). |
| Wrong date on invoices | Fix the Windows date/time (Settings → Time & language → Sync now). |

## Developer issues

| Problem | Solution |
|---|---|
| `flutter doctor` says Visual Studio is incomplete | Visual Studio Installer → Modify → tick **Desktop development with C++** → Modify. |
| Build fails with file-in-use errors | Close the running app, then `flutter clean` and build again. OneDrive can lock files in `build\` — pause OneDrive syncing during builds if it happens. |
| `flutter test` cannot load sqlite3 | Run `flutter pub get` again (the sqlite3 package provides the native library). |
