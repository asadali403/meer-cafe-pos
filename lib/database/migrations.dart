/// Ordered schema migrations. Index 0 upgrades an empty database to version 1,
/// index 1 upgrades version 1 to 2, and so on. Never edit a released migration;
/// append a new one instead and bump [schemaVersion] automatically.
const List<List<String>> migrations = [
  // ---------------- Version 1 ----------------
  [
    '''
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL UNIQUE COLLATE NOCASE,
      display_name TEXT NOT NULL,
      password_hash TEXT NOT NULL,
      role TEXT NOT NULL CHECK (role IN ('admin','cashier')),
      active INTEGER NOT NULL DEFAULT 1,
      must_change_password INTEGER NOT NULL DEFAULT 1,
      failed_attempts INTEGER NOT NULL DEFAULT 0,
      locked_until TEXT,
      last_login_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''
    CREATE TABLE categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE COLLATE NOCASE,
      sort_order INTEGER NOT NULL DEFAULT 0,
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''
    CREATE TABLE products (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
      price INTEGER NOT NULL CHECK (price >= 0),
      description TEXT NOT NULL DEFAULT '',
      active INTEGER NOT NULL DEFAULT 1,
      deleted_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    'CREATE INDEX idx_products_category ON products(category_id)',
    'CREATE INDEX idx_products_name ON products(name)',
    '''
    CREATE TABLE bills (
      id TEXT PRIMARY KEY,
      invoice_no TEXT NOT NULL UNIQUE,
      invoice_seq INTEGER NOT NULL,
      business_date TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      cashier_id INTEGER NOT NULL REFERENCES users(id),
      cashier_name TEXT NOT NULL,
      customer_note TEXT NOT NULL DEFAULT '',
      subtotal INTEGER NOT NULL CHECK (subtotal >= 0),
      discount INTEGER NOT NULL DEFAULT 0 CHECK (discount >= 0),
      rounding INTEGER NOT NULL DEFAULT 0,
      total INTEGER NOT NULL CHECK (total >= 0),
      amount_paid INTEGER NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
      balance_due INTEGER NOT NULL DEFAULT 0 CHECK (balance_due >= 0),
      payment_status TEXT NOT NULL CHECK (payment_status IN ('paid','partial','unpaid')),
      print_count INTEGER NOT NULL DEFAULT 0,
      last_printed_at TEXT,
      sync_status TEXT NOT NULL DEFAULT 'pending',
      UNIQUE (business_date, invoice_seq)
    )''',
    'CREATE INDEX idx_bills_date ON bills(business_date)',
    'CREATE INDEX idx_bills_cashier ON bills(cashier_id)',
    'CREATE INDEX idx_bills_status ON bills(payment_status)',
    '''
    CREATE TABLE bill_items (
      id TEXT PRIMARY KEY,
      bill_id TEXT NOT NULL REFERENCES bills(id) ON DELETE RESTRICT,
      line_no INTEGER NOT NULL,
      product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
      product_name TEXT NOT NULL,
      category_name TEXT NOT NULL DEFAULT '',
      quantity INTEGER NOT NULL CHECK (quantity > 0),
      unit_price INTEGER NOT NULL CHECK (unit_price >= 0),
      line_total INTEGER NOT NULL CHECK (line_total >= 0),
      UNIQUE (bill_id, line_no)
    )''',
    'CREATE INDEX idx_bill_items_bill ON bill_items(bill_id)',
    'CREATE INDEX idx_bill_items_product ON bill_items(product_id)',
    '''
    CREATE TABLE payments (
      id TEXT PRIMARY KEY,
      bill_id TEXT NOT NULL REFERENCES bills(id) ON DELETE RESTRICT,
      amount INTEGER NOT NULL CHECK (amount > 0),
      tendered INTEGER NOT NULL CHECK (tendered >= amount),
      change_given INTEGER NOT NULL DEFAULT 0 CHECK (change_given >= 0),
      method TEXT NOT NULL,
      received_by_id INTEGER NOT NULL REFERENCES users(id),
      received_by_name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      business_date TEXT NOT NULL
    )''',
    'CREATE INDEX idx_payments_bill ON payments(bill_id)',
    'CREATE INDEX idx_payments_date ON payments(business_date)',
    '''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''
    CREATE TABLE sync_queue (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','synced','failed')),
      version INTEGER NOT NULL DEFAULT 1,
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      next_attempt_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      synced_at TEXT,
      UNIQUE (entity_type, entity_id)
    )''',
    'CREATE INDEX idx_sync_queue_status ON sync_queue(status, next_attempt_at)',
    '''
    CREATE TABLE sync_logs (
      id TEXT PRIMARY KEY,
      started_at TEXT NOT NULL,
      finished_at TEXT,
      trigger TEXT NOT NULL,
      sent INTEGER NOT NULL DEFAULT 0,
      succeeded INTEGER NOT NULL DEFAULT 0,
      failed INTEGER NOT NULL DEFAULT 0,
      message TEXT NOT NULL DEFAULT ''
    )''',
    'CREATE INDEX idx_sync_logs_started ON sync_logs(started_at)',
  ],
  // ---------------- Version 2 ----------------
  // Bill types (customer sale / personal food / expense), custom bill items,
  // and kitchen-ticket routing per category.
  [
    "ALTER TABLE bills ADD COLUMN bill_type TEXT NOT NULL DEFAULT 'sale' "
        "CHECK (bill_type IN ('sale','personal','expense'))",
    'CREATE INDEX idx_bills_type ON bills(bill_type, business_date)',
    'ALTER TABLE bill_items ADD COLUMN is_custom INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE bill_items ADD COLUMN kitchen INTEGER NOT NULL DEFAULT 1',
    'ALTER TABLE categories ADD COLUMN kitchen INTEGER NOT NULL DEFAULT 1',
    "UPDATE categories SET kitchen = 0 WHERE name IN ('Drinks')",
  ],
];

int get schemaVersion => migrations.length;
