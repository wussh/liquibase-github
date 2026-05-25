--liquibase formatted sql

--changeset orders-dev:001-create-orders labels:v1.0 context:all
CREATE TABLE orders (
    id          BIGINT         NOT NULL AUTO_INCREMENT,
    user_id     BIGINT         NOT NULL,
    order_code  VARCHAR(50)    NOT NULL,
    total       DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
    status      VARCHAR(30)    NOT NULL DEFAULT 'pending',
    notes       TEXT           NULL,
    created_at  TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_orders       PRIMARY KEY (id),
    CONSTRAINT uq_order_code   UNIQUE (order_code)
);
--rollback DROP TABLE IF EXISTS orders;

--changeset orders-dev:002-create-order-items labels:v1.0 context:all
CREATE TABLE order_items (
    id          BIGINT         NOT NULL AUTO_INCREMENT,
    order_id    BIGINT         NOT NULL,
    product_id  BIGINT         NOT NULL,
    qty         INT            NOT NULL DEFAULT 1,
    unit_price  DECIMAL(15, 2) NOT NULL,
    subtotal    DECIMAL(15, 2) GENERATED ALWAYS AS (qty * unit_price) STORED,
    CONSTRAINT pk_order_items          PRIMARY KEY (id),
    CONSTRAINT fk_order_items_order_id FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE
);
--rollback DROP TABLE IF EXISTS order_items;

--changeset orders-dev:003-idx-orders-user labels:v1.0 context:all
CREATE INDEX idx_orders_user_id ON orders (user_id);
--rollback DROP INDEX idx_orders_user_id ON orders;
