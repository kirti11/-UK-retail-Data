-- ============================================================
-- Data cleaning: raw_transactions (541,909 rows, as downloaded)
--   -> normalized, analysis-ready tables
-- ============================================================

CREATE INDEX IF NOT EXISTS ix_raw_invoice ON raw_transactions(InvoiceNo);
CREATE INDEX IF NOT EXISTS ix_raw_stock ON raw_transactions(StockCode);
CREATE INDEX IF NOT EXISTS ix_raw_cust ON raw_transactions(CustomerID);

-- 1. Geo lookup: assign each of the 38 countries in the data to a region
INSERT INTO geo_lookup (country, region) VALUES
    ('United Kingdom','UK'),
    ('Ireland','Ireland'),
    ('Germany','Western Europe'),('France','Western Europe'),('Netherlands','Western Europe'),
    ('Belgium','Western Europe'),('Switzerland','Western Europe'),('Austria','Western Europe'),
    ('Spain','Southern Europe'),('Italy','Southern Europe'),('Portugal','Southern Europe'),
    ('Greece','Southern Europe'),('Cyprus','Southern Europe'),('Malta','Southern Europe'),
    ('Norway','Nordics'),('Sweden','Nordics'),('Finland','Nordics'),('Denmark','Nordics'),('Iceland','Nordics'),
    ('Poland','Eastern Europe'),('Czech Republic','Eastern Europe'),('European Community','Eastern Europe'),
    ('Lithuania','Eastern Europe'),('Channel Islands','Western Europe'),
    ('Australia','Rest of World'),('Japan','Rest of World'),('Singapore','Rest of World'),
    ('USA','Rest of World'),('Canada','Rest of World'),('Israel','Rest of World'),
    ('United Arab Emirates','Rest of World'),('Bahrain','Rest of World'),('Saudi Arabia','Rest of World'),
    ('Lebanon','Rest of World'),('RSA','Rest of World'),('Brazil','Rest of World'),
    ('EIRE','Ireland'),('Unspecified','Rest of World'),('Hong Kong','Rest of World');

-- 2. Products: one row per stock code (most frequent description wins),
--    excluding non-merchandise codes (postage, adjustments, discounts, fees)
DROP TABLE IF EXISTS temp_product_desc;
CREATE TEMP TABLE temp_product_desc AS
SELECT StockCode, Description, cnt,
       ROW_NUMBER() OVER (PARTITION BY StockCode ORDER BY cnt DESC) AS rn
FROM (
    SELECT StockCode, Description, COUNT(*) AS cnt
    FROM raw_transactions
    WHERE Description IS NOT NULL
      AND UPPER(StockCode) NOT IN ('POST','DOT','M','D','S','AMAZONFEE','CRUK','PADS','B','BANK CHARGES')
    GROUP BY StockCode, Description
);

DROP TABLE IF EXISTS temp_product_price;
CREATE TEMP TABLE temp_product_price AS
SELECT StockCode, AVG(UnitPrice) AS avg_unit_price
FROM raw_transactions
WHERE UnitPrice > 0
  AND UPPER(StockCode) NOT IN ('POST','DOT','M','D','S','AMAZONFEE','CRUK','PADS','B','BANK CHARGES')
GROUP BY StockCode;

INSERT INTO products (stock_code, description, avg_unit_price)
SELECT d.StockCode, d.Description, p.avg_unit_price
FROM temp_product_desc d
LEFT JOIN temp_product_price p ON p.StockCode = d.StockCode
WHERE d.rn = 1;

-- 3. Customers: guests (missing CustomerID) rolled into customer_id = 0
DROP TABLE IF EXISTS temp_cust_country;
CREATE TEMP TABLE temp_cust_country AS
SELECT cust_id, Country, cnt,
       ROW_NUMBER() OVER (PARTITION BY cust_id ORDER BY cnt DESC) AS rn
FROM (
    SELECT COALESCE(CAST(CustomerID AS INTEGER), 0) AS cust_id, Country, COUNT(*) AS cnt
    FROM raw_transactions
    GROUP BY cust_id, Country
);

DROP TABLE IF EXISTS temp_cust_agg;
CREATE TEMP TABLE temp_cust_agg AS
SELECT COALESCE(CAST(CustomerID AS INTEGER), 0) AS cust_id,
       MIN(InvoiceDate) AS first_invoice,
       MAX(CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END) AS is_guest
FROM raw_transactions
GROUP BY cust_id;

INSERT INTO customers (customer_id, country, first_invoice, is_guest)
SELECT a.cust_id, c.Country, a.first_invoice, a.is_guest
FROM temp_cust_agg a
LEFT JOIN temp_cust_country c ON c.cust_id = a.cust_id AND c.rn = 1;

-- 4. Orders: one row per invoice. status = Cancelled when InvoiceNo starts with 'C'
DROP TABLE IF EXISTS temp_order_country;
CREATE TEMP TABLE temp_order_country AS
SELECT InvoiceNo, Country, cnt,
       ROW_NUMBER() OVER (PARTITION BY InvoiceNo ORDER BY cnt DESC) AS rn
FROM (
    SELECT InvoiceNo, Country, COUNT(*) AS cnt
    FROM raw_transactions
    WHERE UPPER(InvoiceNo) NOT LIKE 'A%'
    GROUP BY InvoiceNo, Country
);

INSERT INTO orders (invoice_no, customer_id, invoice_date, country, status_id)
SELECT
    r.InvoiceNo,
    COALESCE(CAST(r.CustomerID AS INTEGER), 0),
    MIN(r.InvoiceDate),
    oc.Country,
    CASE WHEN r.InvoiceNo LIKE 'C%' THEN 2 ELSE 1 END
FROM raw_transactions r
LEFT JOIN temp_order_country oc ON oc.InvoiceNo = r.InvoiceNo AND oc.rn = 1
WHERE UPPER(r.InvoiceNo) NOT LIKE 'A%'
GROUP BY r.InvoiceNo;

-- 5. Order lines: valid merchandise lines only
--    Excludes: non-product stock codes, zero/blank price, and quantity = 0
INSERT INTO order_lines (invoice_no, stock_code, quantity, unit_price, line_revenue)
SELECT
    InvoiceNo,
    StockCode,
    Quantity,
    UnitPrice,
    Quantity * UnitPrice
FROM raw_transactions
WHERE UPPER(StockCode) NOT IN ('POST','DOT','M','D','S','AMAZONFEE','CRUK','PADS','B','BANK CHARGES')
  AND UPPER(InvoiceNo) NOT LIKE 'A%'
  AND UnitPrice > 0
  AND Quantity <> 0;

-- 6. Audit trail of everything excluded, with a reason
INSERT INTO excluded_lines (invoice_no, stock_code, description, quantity, unit_price, customer_id, exclusion_reason)
SELECT InvoiceNo, StockCode, Description, Quantity, UnitPrice, CustomerID,
    CASE
        WHEN UPPER(InvoiceNo) LIKE 'A%' THEN 'Bad-debt adjustment invoice'
        WHEN UPPER(StockCode) IN ('POST','DOT') THEN 'Postage/carriage line, not merchandise'
        WHEN UPPER(StockCode) IN ('M','D','S','AMAZONFEE','CRUK','PADS','B','BANK CHARGES') THEN 'Manual/fee/discount/sample line, not merchandise'
        WHEN UnitPrice <= 0 THEN 'Zero or negative unit price'
        WHEN Quantity = 0 THEN 'Zero quantity'
        ELSE 'Other'
    END
FROM raw_transactions
WHERE UPPER(InvoiceNo) LIKE 'A%'
   OR UPPER(StockCode) IN ('POST','DOT','M','D','S','AMAZONFEE','CRUK','PADS','B','BANK CHARGES')
   OR UnitPrice <= 0
   OR Quantity = 0;
