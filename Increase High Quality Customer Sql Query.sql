create database quality_cus;
use quality_cus;

-- ================================================================
-- PROJECT: Identify & Grow "Quality Customers"
-- STAGE: SQL — Data Understanding + Extraction
--
-- Business context: Company ke paas customers, orders, order_items,
-- aur products ka raw data bikhra hua hai 4 alag tables mein.
-- Goal: Is raw data ko ek "customer-level summary" mein convert
-- karna, jisse pata chale kaunse customers zyada value la rahe hain.
-- ================================================================

USE quality_cus;


-- ----------------------------------------------------------------
-- STEP 1: Database mein kaunsi tables hain, confirm karna
-- Soch: Kaam shuru karne se pehle apna "raw material" verify karenge ham
-- ----------------------------------------------------------------
SHOW TABLES;


-- ----------------------------------------------------------------
-- STEP 2: orders table ka structure samajhna
-- Soch: Query likhne se pehle exact column names/spelling
-- confirm karni hai, warna aage error aayega
-- ----------------------------------------------------------------
DESCRIBE orders;
Describe customers;


-- ----------------------------------------------------------------
-- STEP 3: Data Quality Audit — customers table mein kitni kharaab hai
-- Soch: Company ko yeh dikhana hai ki maine blindly analysis nahi
-- kiya — pehle data ki health check ki, taaki pata chale kya-kya
-- cleaning aage karni hogi hame
-- ----------------------------------------------------------------
SELECT
  SUM(CASE WHEN email IS NULL or email = '' then 1 ELSE 0 END) AS null_email,
  SUM(CASE WHEN city IS NULL or city = '' THEN 1 ELSE 0 END) AS null_city,
  SUM(CASE WHEN gender IS NULL or gender = '' THEN 1 ELSE 0 END) AS null_gender,
  COUNT(*) AS total_rows,
  COUNT(DISTINCT customer_id) AS distinct_customers
FROM customers;

-- ----------------------------------------------------------------
-- STEP 3B: Customer duplicate check
-- Soch: STEP 3 mein pata chala total_rows > distinct_customers hai,
-- ab exactly dekhte hain kaunse customer_id duplicate hain
-- ----------------------------------------------------------------
SELECT customer_id, COUNT(*) AS cnt
FROM customers
GROUP BY customer_id
HAVING COUNT(*) > 1;


-- ----------------------------------------------------------------
-- STEP 3C: Distinct values check — inconsistent formatting dhoondhna
-- Soch: Categorical columns mein same value alag spelling/case mein
-- ho sakti hai (jaise "Delhi" vs "delhi") — cleaning se pehle pata
-- karna zaroori hai
-- ----------------------------------------------------------------
SELECT DISTINCT city FROM customers;
SELECT DISTINCT order_status FROM orders;
SELECT DISTINCT gender FROM customers;


-- ----------------------------------------------------------------
-- STEP 3D: Min/Max range check — invalid values dhoondhna
-- Soch: Negative quantity, outlier prices, ya galat dates pakadne
-- ke liye range dekhna zaroori hai
-- ----------------------------------------------------------------
SELECT MIN(quantity) AS min_qty, MAX(quantity) AS max_qty FROM order_items;
SELECT MIN(order_date) AS earliest, MAX(order_date) AS latest FROM orders;


-- ----------------------------------------------------------------
-- STEP 3E: Referential integrity — orphan records check
-- Soch: Kya koi order aisa hai jiska customer_id 'customers' table
-- mein exist hi nahi karta (data sync issue)
-- ----------------------------------------------------------------
SELECT o.customer_id
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;


-- Insight jo yahan se milega: agar total_rows > distinct_customers,
-- matlab duplicate customer entries hain — data entry error ka sign


-- ----------------------------------------------------------------
-- STEP 4: Duplicate order_id dhoondhna
-- Soch: Agar ek order do baar system mein aa gaya (glitch/duplicate
-- entry), toh uska revenue bhi do baar count ho jaayega — jo
-- business metrics ko galat dikhayega. Isliye pehle hi flag karna
-- zaroori hai.
-- ----------------------------------------------------------------
SELECT order_id, COUNT(*) AS cnt
FROM orders
GROUP BY order_id
HAVING COUNT(*) > 1
LIMIT 5;


-- ----------------------------------------------------------------
-- STEP 5: MAIN DELIVERABLE — Customer-Level RFM Base Table
-- Soch: Business ne poocha "kaunse customers quality wale hain?"
-- Iska jawab dene ke liye har customer ka pehle yeh pata karna
-- padega: (a) kitni baar order kiya (Frequency),
-- (b) kitna total spend kiya (Monetary), (c) last order kab tha
-- (Recency ka base). Yeh 3 metrics RFM framework ki foundation hain.
-- ----------------------------------------------------------------

-- Pehle ek temporary result (CTE) banate hain: har ORDER ka total
-- value nikalna hai (kyunki ek order mein multiple items ho sakte
-- hain, unhe pehle jodna padega)
WITH order_value AS (
  SELECT
    o.order_id,
    o.customer_id,
    o.order_date,
    SUM(
      -- unit_price kuch rows mein "Rs.1,234.56" jaise text format
      -- mein hai (currency symbol + comma) — inhe number banane
      -- ke liye pehle clean karna zaroori hai
      CAST(REPLACE(REPLACE(oi.unit_price, 'Rs.', ''), ',', '') AS DECIMAL(10,2))
      -- kuch rows mein quantity galti se negative hai (data-entry
      -- error) — ABS se usse positive bana rahe hain
      * ABS(oi.quantity)
    ) AS order_total
  FROM orders o
  -- JOIN: orders aur order_items do alag tables hain; JOIN unhe
  -- order_id ke through jodta hai taaki pata chale har order mein
  -- kaunse products the aur kitne
  JOIN order_items oi ON o.order_id = oi.order_id
  -- Business rule: sirf "Delivered" orders ko revenue mein ginna
  -- hai — Cancelled/Returned orders ko nahi, warna revenue ka
  -- number fake/inflated lagega
  WHERE o.order_status IN ('Delivered', 'delivered', 'DELIVERED')
  GROUP BY o.order_id, o.customer_id, o.order_date
)

-- Ab is temporary result se, har CUSTOMER ka summary nikal rahe hain
SELECT
  customer_id,
  COUNT(order_id) AS frequency,          -- kitni baar order kiya
  ROUND(SUM(order_total), 2) AS monetary,-- total kitna spend kiya
  MAX(order_date) AS last_order_date_raw -- sabse recent order kab
FROM order_value
GROUP BY customer_id
ORDER BY monetary DESC   -- sabse zyada value dene wale customers upar
LIMIT 10;


-- ----------------------------------------------------------------
-- summary
-- "Maine 4 raw tables (customers, products, orders, order_items) ko
-- pehle data-quality audit kiya, phir orders aur order_items ko JOIN
-- karke, sirf delivered orders leke, ek customer-level RFM base
-- table banayi jisme har customer ka frequency aur monetary value
-- hai. Yeh table ab Python stage ko jaayega jahan RFM scoring aur
-- ML model banega."
-- ----------------------------------------------------------------