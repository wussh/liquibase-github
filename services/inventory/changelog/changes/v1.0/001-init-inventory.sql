--liquibase formatted sql

--changeset inventory-dev:001-create-products labels:v1.0 context:all
CREATE TABLE products (
    id          BIGINT          NOT NULL AUTO_INCREMENT,
    sku         VARCHAR(100)    NOT NULL,
    name        VARCHAR(200)    NOT NULL,
    category    VARCHAR(100)    NULL,
    price       DECIMAL(15, 2)  NOT NULL DEFAULT 0.00,
    created_at  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_products  PRIMARY KEY (id),
    CONSTRAINT uq_sku       UNIQUE (sku)
);
--rollback DROP TABLE IF EXISTS products;

--changeset inventory-dev:002-create-stock labels:v1.0 context:all
CREATE TABLE stock (
    id          BIGINT   NOT NULL AUTO_INCREMENT,
    product_id  BIGINT   NOT NULL,
    warehouse   VARCHAR(100) NOT NULL DEFAULT 'main',
    qty         INT      NOT NULL DEFAULT 0,
    reserved    INT      NOT NULL DEFAULT 0,
    updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT pk_stock            PRIMARY KEY (id),
    CONSTRAINT fk_stock_product_id FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE,
    CONSTRAINT uq_stock_product_warehouse UNIQUE (product_id, warehouse)
);
--rollback DROP TABLE IF EXISTS stock;

--changeset inventory-dev:003-create-stock-movements labels:v1.0 context:all
CREATE TABLE stock_movements (
    id          BIGINT      NOT NULL AUTO_INCREMENT,
    product_id  BIGINT      NOT NULL,
    warehouse   VARCHAR(100) NOT NULL DEFAULT 'main',
    type        VARCHAR(20) NOT NULL COMMENT 'IN / OUT / RESERVE / RELEASE',
    qty         INT         NOT NULL,
    ref_id      BIGINT      NULL     COMMENT 'order_id atau purchase_id',
    note        VARCHAR(255) NULL,
    created_at  TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_stock_movements PRIMARY KEY (id)
);
--rollback DROP TABLE IF EXISTS stock_movements;

--changeset inventory-dev:004-idx-stock-movements labels:v1.0 context:all
CREATE INDEX idx_sm_product_id ON stock_movements (product_id);
CREATE INDEX idx_sm_ref_id     ON stock_movements (ref_id);
--rollback DROP INDEX idx_sm_ref_id ON stock_movements;
--rollback DROP INDEX idx_sm_product_id ON stock_movements;
