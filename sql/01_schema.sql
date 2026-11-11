-- E-Commerce Sales Analytics: schema (MySQL 8.0+)
-- Five tables: customers, products, orders, order_items, payments.
-- Written in portable SQL so the same file also loads in SQLite for quick checks.

DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id   INT          PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    city          VARCHAR(60)  NOT NULL,
    signup_date   DATE         NOT NULL
);

CREATE TABLE products (
    product_id    INT           PRIMARY KEY,
    product_name  VARCHAR(100)  NOT NULL,
    category      VARCHAR(50)   NOT NULL,
    list_price    DECIMAL(10,2) NOT NULL CHECK (list_price >= 0)
);

-- No stored order total: the total is always derived from order_items,
-- so there is a single source of truth.
CREATE TABLE orders (
    order_id      INT         PRIMARY KEY,
    customer_id   INT         NOT NULL,
    order_date    DATE        NOT NULL,
    status        VARCHAR(20) NOT NULL
                  CHECK (status IN ('delivered', 'shipped', 'cancelled', 'returned')),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE order_items (
    order_item_id INT           PRIMARY KEY,
    order_id      INT           NOT NULL,
    product_id    INT           NOT NULL,
    quantity      INT           NOT NULL CHECK (quantity > 0),
    unit_price    DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),  -- price at time of sale
    FOREIGN KEY (order_id)   REFERENCES orders(order_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- An order can have more than one payment row (split payment, e.g. wallet + card).
CREATE TABLE payments (
    payment_id     INT           PRIMARY KEY,
    order_id       INT           NOT NULL,
    payment_method VARCHAR(20)   NOT NULL,
    amount         DECIMAL(10,2) NOT NULL CHECK (amount >= 0),
    payment_status VARCHAR(20)   NOT NULL CHECK (payment_status IN ('completed', 'refunded')),
    paid_on        DATE          NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_date     ON orders(order_date);
CREATE INDEX idx_items_order     ON order_items(order_id);
CREATE INDEX idx_items_product   ON order_items(product_id);
CREATE INDEX idx_payments_order  ON payments(order_id);
