/**
 * Meer Cafe POS — Google Sheets sync endpoint (Google Apps Script web app).
 *
 * Setup (see docs/GOOGLE_SHEETS_SETUP.md):
 *   1. Open your spreadsheet > Extensions > Apps Script, paste this file as Code.gs.
 *   2. Run `setupMeerCafe` once (authorize it). It creates the worksheets and a
 *      random SYNC_SECRET, which is shown in the execution log.
 *   3. Deploy > New deployment > Web app: Execute as "Me", Who has access "Anyone".
 *   4. Paste the Web app URL and the secret into Meer Cafe POS > Sync settings.
 *
 * Security: every request must carry an HMAC-SHA256 signature made with
 * SYNC_SECRET (stored only in Script Properties and in the POS settings).
 * Unsigned or wrongly signed requests are rejected. Writes are idempotent
 * upserts keyed by the "id" column, so retries never create duplicate rows.
 */

var SHEETS = ['Products', 'Bills', 'BillItems', 'Payments', 'DailySummary', 'SyncLog'];
var MAX_CLOCK_SKEW_MS = 24 * 60 * 60 * 1000; // tolerate laptop clock drift; replays are harmless (idempotent)
var MAX_RECORDS = 200;

function doPost(e) {
  try {
    var secret = PropertiesService.getScriptProperties().getProperty('SYNC_SECRET');
    if (!secret || secret.length < 16) {
      return json_({ ok: false, error: 'Server not configured: run setupMeerCafe to create SYNC_SECRET.' });
    }
    if (!e || !e.postData || !e.postData.contents) return json_({ ok: false, error: 'Empty request.' });

    var envelope = JSON.parse(e.postData.contents);
    var payload = envelope.payload;
    var sig = envelope.sig;
    if (typeof payload !== 'string' || typeof sig !== 'string') {
      return json_({ ok: false, error: 'Malformed request.' });
    }
    var expected = hex_(Utilities.computeHmacSha256Signature(payload, secret, Utilities.Charset.UTF_8));
    if (!safeEquals_(expected, sig.toLowerCase())) {
      return json_({ ok: false, error: 'Invalid signature. Check the sync secret in POS settings.' });
    }

    var body = JSON.parse(payload);
    if (Math.abs(Date.now() - Number(body.ts)) > MAX_CLOCK_SKEW_MS) {
      return json_({ ok: false, error: 'Request timestamp is too old. Check the laptop date and time.' });
    }

    var ss = SpreadsheetApp.getActiveSpreadsheet();
    var lock = LockService.getScriptLock();
    lock.waitLock(30000);
    try {
      ensureSheets_(ss);
      if (body.ping) return json_({ ok: true, spreadsheet: ss.getName() });
      var records = body.records || [];
      if (records.length > MAX_RECORDS) return json_({ ok: false, error: 'Too many records in one request.' });
      var results = upsertAll_(ss, records);
      SpreadsheetApp.flush();
      return json_({ ok: true, results: results });
    } finally {
      lock.releaseLock();
    }
  } catch (err) {
    return json_({ ok: false, error: String((err && err.message) || err) });
  }
}

function doGet() {
  return json_({ ok: true, service: 'Meer Cafe POS sync endpoint', note: 'Use POST.' });
}

/** Run once from the Apps Script editor. Creates sheets and the shared secret. */
function setupMeerCafe() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  ensureSheets_(ss);
  var props = PropertiesService.getScriptProperties();
  var secret = props.getProperty('SYNC_SECRET');
  if (!secret) {
    secret = (Utilities.getUuid() + Utilities.getUuid()).replace(/-/g, '');
    props.setProperty('SYNC_SECRET', secret);
  }
  Logger.log('SYNC_SECRET (copy into Meer Cafe POS > Settings > Google Sheets): ' + secret);
}

/** Run to replace the secret (then update it in the POS app). */
function rotateSecret() {
  PropertiesService.getScriptProperties().deleteProperty('SYNC_SECRET');
  setupMeerCafe();
}

function ensureSheets_(ss) {
  SHEETS.forEach(function (name) {
    var sh = ss.getSheetByName(name);
    if (!sh) {
      sh = ss.insertSheet(name);
      sh.getRange(1, 1).setValue('id');
      sh.setFrozenRows(1);
      sh.getRange('A:A').setNumberFormat('@');
      sh.getRange(1, 1, 1, 1).setFontWeight('bold');
    }
  });
}

function upsertAll_(ss, records) {
  var results = [];
  var bySheet = {};
  records.forEach(function (r) {
    if (SHEETS.indexOf(r.sheet) < 0 || !r.key || typeof r.row !== 'object') {
      results.push({ sheet: r.sheet, key: r.key, ok: false, error: 'Invalid record' });
      return;
    }
    (bySheet[r.sheet] = bySheet[r.sheet] || []).push(r);
  });

  Object.keys(bySheet).forEach(function (name) {
    var sh = ss.getSheetByName(name);
    var recs = bySheet[name];
    try {
      // Headers: keep existing order, append any new columns.
      var lastCol = Math.max(sh.getLastColumn(), 1);
      var headers = sh.getRange(1, 1, 1, lastCol).getDisplayValues()[0].filter(String);
      if (headers.length === 0 || headers[0] !== 'id') headers = ['id'].concat(headers.filter(function (h) { return h !== 'id'; }));
      recs.forEach(function (r) {
        Object.keys(r.row).forEach(function (k) {
          if (headers.indexOf(k) < 0) headers.push(k);
        });
      });
      sh.getRange(1, 1, 1, headers.length).setValues([headers]).setFontWeight('bold');
      sh.getRange('A:A').setNumberFormat('@');

      // Index existing ids -> row number.
      var lastRow = sh.getLastRow();
      var index = {};
      if (lastRow >= 2) {
        var ids = sh.getRange(2, 1, lastRow - 1, 1).getDisplayValues();
        for (var i = 0; i < ids.length; i++) {
          if (ids[i][0] !== '') index[ids[i][0]] = i + 2;
        }
      }

      var appends = [];
      var appendKeys = {};
      recs.forEach(function (r) {
        var key = String(r.key);
        var values = headers.map(function (h) {
          if (h === 'id') return key;
          var v = r.row[h];
          return v === null || v === undefined ? '' : v;
        });
        if (index[key]) {
          sh.getRange(index[key], 1, 1, headers.length).setValues([values]);
        } else if (appendKeys[key] !== undefined) {
          appends[appendKeys[key]] = values; // same key twice in one batch
        } else {
          appendKeys[key] = appends.length;
          appends.push(values);
        }
      });
      if (appends.length) {
        sh.getRange(sh.getLastRow() + 1, 1, appends.length, headers.length).setValues(appends);
      }
      recs.forEach(function (r) {
        results.push({ sheet: name, key: r.key, ok: true });
      });
    } catch (err) {
      recs.forEach(function (r) {
        results.push({ sheet: name, key: r.key, ok: false, error: String((err && err.message) || err) });
      });
    }
  });
  return results;
}

function hex_(bytes) {
  return bytes
    .map(function (b) {
      var v = (b < 0 ? b + 256 : b).toString(16);
      return v.length === 1 ? '0' + v : v;
    })
    .join('');
}

function safeEquals_(a, b) {
  if (a.length !== b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
