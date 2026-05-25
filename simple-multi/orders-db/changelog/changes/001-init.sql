--liquibase formatted sql

--changeset dev:001-create-orders
CREATE TABLE orders (
    id       BIGINT         NOT NULL AUTO_INCREMENT,
    user_id  BIGINT         NOT NULL,
    total    DECIMAL(15, 2) NOT NULL DEFAULT 0.00,
    status   VARCHAR(30)    NOT NULL DEFAULT 'pending',
    CONSTRAINT pk_orders PRIMARY KEY (id)
);
--rollback DROP TABLE IF EXISTS orders;
