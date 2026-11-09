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
var MENU_TITLE = 'Meer Cafe';
var MENU_TAGLINE = 'Our Circle. Your Place.';

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

/**
 * Opening the web app URL (e.g. by scanning the QR code on a receipt) shows the
 * cafe menu, built from the active products in the "Products" sheet.
 */
function doGet() {
  var sh = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Products');
  var values = sh && sh.getLastRow() >= 2 ? sh.getDataRange().getValues() : [];
  var head = values.length ? values[0].map(String) : [];
  var col = function (name) { return head.indexOf(name); };
  var rows = values.slice(1).filter(function (r) {
    return r[col('name')] !== '' && r[col('active')] !== 'NO' && r[col('deleted')] !== 'YES';
  });
  rows.sort(function (a, b) { return Number(a[col('id')]) - Number(b[col('id')]); });

  var groups = {};
  var order = [];
  rows.forEach(function (r) {
    var c = String(r[col('category')] || 'Menu');
    if (!groups[c]) { groups[c] = []; order.push(c); }
    groups[c].push(r);
  });

  var html = '<!doctype html><html><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width, initial-scale=1">' +
    '<title>' + esc_(MENU_TITLE) + '</title><style>' +
    'body{margin:0;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:#111;color:#f5f0e1}' +
    'header{text-align:center;padding:28px 16px 12px}h1{margin:0;color:#d4a937;font-size:28px}' +
    'header p{margin:6px 0 0;color:#bbb;font-size:14px}main{max-width:640px;margin:0 auto;padding:0 16px 32px}' +
    'h2{color:#d4a937;font-size:19px;border-bottom:1px solid #333;padding-bottom:6px;margin:26px 0 6px}' +
    '.i{display:flex;justify-content:space-between;gap:12px;padding:9px 0;border-bottom:1px solid #222}' +
    '.n{font-weight:600}.d{color:#aaa;font-size:13px;margin-top:2px}.p{color:#d4a937;font-weight:700;white-space:nowrap}' +
    '</style></head><body><header><h1>' + esc_(MENU_TITLE) + '</h1><p>' + esc_(MENU_TAGLINE) + '</p></header><main>';
  if (!order.length) html += '<p style="text-align:center;color:#aaa">The menu is being updated. Please ask our staff.</p>';
  order.forEach(function (c) {
    html += '<h2>' + esc_(c) + '</h2>';
    groups[c].forEach(function (r) {
      var desc = col('description') >= 0 ? String(r[col('description')] || '') : '';
      html += '<div class="i"><div><div class="n">' + esc_(r[col('name')]) + '</div>' +
        (desc ? '<div class="d">' + esc_(desc) + '</div>' : '') + '</div>' +
        '<div class="p">Rs. ' + Number(r[col('price')] || 0).toLocaleString('en-US') + '</div></div>';
    });
  });
  html += '<p style="text-align:center;color:#777;font-size:12px;margin-top:28px">Prices in Pakistani Rupees (PKR)</p></main></body></html>';
  return HtmlService.createHtmlOutput(html)
    .setTitle(MENU_TITLE)
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
}

function esc_(v) {
  return String(v).replace(/[&<>"']/g, function (ch) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch];
  });
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
