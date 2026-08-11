-- ============================================================
-- UK Online Retail Performance Analysis
-- Schema: normalized structure mirroring a production retail DB
-- ============================================================

DROP TABLE IF EXISTS order_lines;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS order_status;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS geo_lookup;
DROP TABLE IF EXISTS excluded_lines;

-- Reference table mapping each country to a region, used for
-- regional roll-ups (mirrors the geo_lookup dimension pattern).
CREATE TABLE geo_lookup (
    country     TEXT PRIMARY KEY,
    region      TEXT NOT NULL
);

CREATE TABLE order_status (
    status_id   INTEGER PRIMARY KEY,
    status_name TEXT NOT NULL UNIQUE
);

CREATE TABLE customers (
    customer_id     INTEGER PRIMARY KEY,   -- UCI CustomerID (guests = 0)
    country         TEXT,
    first_invoice   TEXT,
    is_guest        INTEGER DEFAULT 0
);

CREATE TABLE products (
    stock_code      TEXT PRIMARY KEY,
    description     TEXT,
    avg_unit_price  REAL
);

CREATE TABLE orders (
    invoice_no      TEXT PRIMARY KEY,
    customer_id     INTEGER,
    invoice_date    TEXT NOT NULL,
    country         TEXT,
    status_id       INTEGER DEFAULT 1,      -- 1 = completed, 2 = cancelled
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (status_id) REFERENCES order_status(status_id)
);

CREATE TABLE order_lines (
    line_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    invoice_no      TEXT NOT NULL,
    stock_code      TEXT NOT NULL,
    quantity        INTEGER NOT NULL,
    unit_price      REAL NOT NULL,
    line_revenue    REAL NOT NULL,
    FOREIGN KEY (invoice_no) REFERENCES orders(invoice_no),
    FOREIGN KEY (stock_code) REFERENCES products(stock_code)
);

-- Rows we deliberately excluded during cleaning (fees, adjustments,
-- test entries) kept for transparency / audit trail.
CREATE TABLE excluded_lines (
    invoice_no      TEXT,
    stock_code      TEXT,
    description     TEXT,
    quantity        INTEGER,
    unit_price      REAL,
    customer_id     REAL,
    exclusion_reason TEXT
);

INSERT INTO order_status (status_id, status_name) VALUES
    (1, 'Completed'),
    (2, 'Cancelled');
